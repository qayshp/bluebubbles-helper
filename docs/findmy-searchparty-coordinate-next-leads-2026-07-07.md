# SearchParty coordinate next leads

This note captures the next focused leads for getting item/device coordinates
from SearchParty internals.

## Priority order

1. Inspect the real `SPLocationFetchContext` construction path.
   - We can already see `lastOnlineLocationInfo` with beacon identifiers and
     timestamps, but not coordinates.
   - The missing piece is likely a matching location result object produced
     after context construction.

2. Hook and inspect `SPOwnerSessionLocationFetch receivedUpdatedLocation:`.
   - This is the strongest coordinate lead because the selector name describes
     the exact event we want.
   - If Find My receives item/device coordinates asynchronously, they may arrive
     here instead of through the completion blocks we are manually calling.
   - Instrument the argument deeply and serialize every ivar/accessor/key path
     that looks location-bearing.

3. Hook and inspect `SPLocationFetchResult setLocationsByBeaconIdentifier:`.
   - `locationsByBeaconIdentifier` is the exact container shape we want.
   - If Find My sets it during normal app use, this hook should expose the
     dictionary before UI filtering or cache storage.

4. Hook and inspect `SPOwnerSessionLocationFetch` location update blocks.
   - The class has `_locationUpdates`.
   - Coordinates may be delivered by subscription callbacks instead of request
     completions.
   - Inspect payloads when `setLocationUpdateBlock:` / `setLocationUpdates:` is
     called and when the wrapped block fires.

## Current plan

Start with `receivedUpdatedLocation:`. This avoids guessing the right XPC
argument shape and instead listens where Find My's own SearchParty pipeline
appears to receive location updates.

## Static inspection: `receivedUpdatedLocation:`

Runtime method diagnostics for `SPOwnerSessionLocationFetch` show:

```text
receivedUpdatedLocation:
type encoding: v24@0:8@16
```

The signature is a void instance method with one object argument. This makes it
a good passive hook target because the app's own SearchParty flow supplies the
payload object.

Related `SPOwnerSessionLocationFetch` methods and ivars seen during prior
inspection:

- `locationForContext:completion:`
- `subscribeAndFetchLocationForContext:completion:`
- `receivedUpdatedDeviceEvents:`
- `setLocationUpdates:`
- `setLocationUpdateBlock:`
- `_locationUpdates`
- `_deviceEventUpdates`
- `_lastContext`
- `_proxy`
- `_session`

The helper was already swizzling `receivedUpdatedLocation:` through the generic
SearchParty object-argument capture path. The instrumentation has now been made
more explicit:

- The hook records selector `receivedUpdatedLocation:`.
- The hook records phase `receivedUpdatedLocation`.
- The argument is serialized through the `SPLocationFetchResult` compaction
  path.
- If the argument responds to `locationsByBeaconIdentifier`, that dictionary is
  captured as a separate accessor snapshot.

Expected useful evidence:

- A `result_class` of `SPLocationFetchResult` or another location-bearing class.
- A non-zero `locations_by_beacon_identifier_count`.
- Entries whose values serialize through the existing location serializer with
  latitude/longitude fields.

## Live try: `receivedUpdatedLocation:`

Tested locally on 2026-07-07 with helper dylib md5
`54f5cf244ea027ea1c3e06de0a4ee7b1`.

Baseline debug route:

```text
POST /api/v1/icloud/findmy/searchparty/debug
```

Findings:

- `receivedUpdatedLocation:` fired without manual UI interaction.
- The captured source class was `SPOwnerSessionLocationFetch`.
- The captured argument class was `SPLocationFetchResult`.
- `locationsByBeaconIdentifier` was present, but it was empty:
  - `locations_by_beacon_identifier_count = 0`
  - `locations_by_beacon_identifier_entries = []`
- A separate accessor capture for `locationsByBeaconIdentifier` also returned
  `__NSDictionary0`.

Representative baseline timestamps:

```text
2026-07-07T08:51:34.791555 receivedUpdatedLocation: SPLocationFetchResult locations count 0
2026-07-07T08:51:34.793219 receivedUpdatedLocation: SPLocationFetchResult locations count 0
```

Then the focused latest-single probe was triggered:

```text
POST /api/v1/icloud/findmy/searchparty/locations/latest-single
POST /api/v1/icloud/findmy/searchparty/debug
POST /api/v1/icloud/findmy/searchparty/locations
```

Findings after the focused probe:

- `receivedUpdatedLocation:` fired again.
- The payload was still `SPLocationFetchResult`.
- `locationsByBeaconIdentifier` was still empty:
  - `locations_by_beacon_identifier_count = 0`
  - `locations_by_beacon_identifier_entries = []`
- The focused latest-single probe itself timed out with one pending completion.
- Completed probe callbacks remained:
  - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` returned `<nil>`.
  - `SPOwnerSession.locationsForBeacons:completion:` returned `__NSDictionary0`.

Representative post-probe timestamps:

```text
2026-07-07T08:52:20.016563 receivedUpdatedLocation: SPLocationFetchResult locations count 0
2026-07-07T08:52:20.017904 receivedUpdatedLocation: SPLocationFetchResult locations count 0
```

Interpretation:

The selector is definitely part of the live SearchParty update path, and its
argument type is exactly the expected `SPLocationFetchResult`. The current
problem is not that we are looking at the wrong method; it is that the result
object delivered on this path currently contains an empty
`locationsByBeaconIdentifier` dictionary. The next lead should be earlier in
the result population path, especially `SPLocationFetchResult
setLocationsByBeaconIdentifier:` or the XPC-side method that constructs the
result before `receivedUpdatedLocation:` observes it.

## Static inspection: `setLocationsByBeaconIdentifier:`

Runtime method diagnostics for `SPLocationFetchResult` show:

```text
locationsByBeaconIdentifier
type encoding: @16@0:8

setLocationsByBeaconIdentifier:
type encoding: v24@0:8@16
```

The setter is the earliest local point seen so far where the result dictionary
can be observed before `receivedUpdatedLocation:` or `locationsByBeaconIdentifier`
getter reads it.

Instrumentation added:

- Swizzle `SPLocationFetchResult setLocationsByBeaconIdentifier:`.
- Capture the assigned dictionary before calling the original setter.
- Preserve the existing getter hook for `locationsByBeaconIdentifier`.
- Increase the retained passive SearchParty accessor snapshot window from 40 to
  80 entries, and expose the latest 24 entries through the debug route.

The same setter pattern was also added for `SPDeviceEventFetchResult
setBeaconEventByBeaconIdentifier:` because device events may point to a
parallel payload path.

## Live try: `setLocationsByBeaconIdentifier:`

Tested locally on 2026-07-07 with helper dylib md5
`d6fbd914230d2fbb30d66a74c2256705`.

Baseline debug route:

```text
POST /api/v1/icloud/findmy/searchparty/debug
```

Findings:

- `setLocationsByBeaconIdentifier:` fired during Find My's normal startup or
  subscription flow.
- The source class was `SPLocationFetchResult`.
- The setter argument was `__NSDictionary0`.
- The setter argument had:
  - `result_count = 0`
  - `entries = []`
- The getter `locationsByBeaconIdentifier` then returned the same empty
  dictionary.
- `receivedUpdatedLocation:` then received an `SPLocationFetchResult` whose
  compacted `locations_by_beacon_identifier_count` was also 0.

Representative baseline sequence:

```text
2026-07-07T08:59:37.223641 setLocationsByBeaconIdentifier: __NSDictionary0 count 0
2026-07-07T08:59:37.227887 locationsByBeaconIdentifier __NSDictionary0 count 0
2026-07-07T08:59:37.227602 receivedUpdatedLocation: SPLocationFetchResult locations count 0
```

Then the focused latest-single probe was triggered:

```text
POST /api/v1/icloud/findmy/searchparty/locations/latest-single
POST /api/v1/icloud/findmy/searchparty/debug
POST /api/v1/icloud/findmy/searchparty/locations
```

Findings after the focused probe:

- `setLocationsByBeaconIdentifier:` fired again.
- The setter argument was still `__NSDictionary0`.
- No retained SearchParty accessor snapshot had a non-zero `result_count`.
- `receivedUpdatedLocation:` again saw `SPLocationFetchResult` with
  `locations_by_beacon_identifier_count = 0`.
- The latest-single probe timed out. This run had one completed callback at the
  status sample time and two pending completions.

Representative post-probe sequence:

```text
2026-07-07T09:00:12.355670 setLocationsByBeaconIdentifier: __NSDictionary0 count 0
2026-07-07T09:00:12.359008 locationsByBeaconIdentifier __NSDictionary0 count 0
2026-07-07T09:00:12.358832 receivedUpdatedLocation: SPLocationFetchResult locations count 0
```

Interpretation:

The empty result is not caused by a getter/serialization problem and is not
introduced between the setter and `receivedUpdatedLocation:`. The local
`SPLocationFetchResult` is being assigned an empty dictionary. The coordinate
source is likely upstream of this object, either in the XPC service before the
result is delivered to Find My, or in a different result path that is not
`locationsByBeaconIdentifier` on the local `SPLocationFetchResult` instances
seen so far.

Next better leads:

- Inspect the XPC proxy methods around
  `latestLocationsForIdentifiers:fetchLimit:sources:completion:` and
  `locationForContext:completion:` for error/completion shape, not just result
  object shape.
- Hook `SPOwnerSessionLocationFetch receivedUpdatedDeviceEvents:` and
  `SPDeviceEventFetchResult setBeaconEventByBeaconIdentifier:` more directly,
  since device event payloads may indicate why locations are withheld.
- Inspect `SPLocationFetchContext` values immediately before the empty result is
  produced, especially `searchLocationSources`, `searchTypes`,
  `searchPriority`, `cachePolicy`, and `primaryIndexRange`.

## Static inspection: fetch context detail

`SPLocationFetchContext` exposes the fields most likely to explain why the
local `SPLocationFetchResult` is empty:

```text
_subscribe
_reportDeviceEvents
_cachePolicy
_searchIdentifiers
_searchPriority
_searchTypes
_searchLocationSources
_lastOnlineLocationInfo
_bundleIdentifier
_primaryIndexRange
```

Instrumentation added on 2026-07-07:

- When a SearchParty probe result or related object is an
  `SPLocationFetchContext`, attach `context_detail`.
- For `searchIdentifiers`, `searchTypes`, `searchPriority`, and
  `searchLocationSources`, capture the runtime class, summary, count, and a
  bounded sample.
- Capture scalar/summary values for `cachePolicy`, `bundleIdentifier`,
  `subscribe`, `reportDeviceEvents`, and `primaryIndexRange`.
- Capture `lastOnlineLocationInfo` runtime class, count, key sample, and a
  bounded sample of value accessors/ivars.
- Keep the payload bounded so `/api/v1/icloud/findmy/searchparty/debug`
  returns valid JSON instead of overflowing the helper output path.

## Live try: fetch context detail

Tested locally on 2026-07-07 with helper dylib md5
`e907b486ccdd5b54ddb8cb5d31af8389`.

Baseline Android-facing route results from the same server run:

```text
GET /api/v1/icloud/findmy/friends  -> status 200, data list count 8
GET /api/v1/icloud/findmy/devices  -> status 200, data null
GET /api/v1/icloud/findmy/items    -> status 200, data null
```

The trimmed debug route returned clean JSON:

```text
POST /api/v1/icloud/findmy/searchparty/debug
response size: 41843 bytes
context_detail_count: 4
```

Observed real `SPLocationFetchContext` values:

```text
context_class: SPLocationFetchContext
searchIdentifiers_class: Swift.__EmptyArrayStorage
searchIdentifiers_count: 0
searchIdentifiers_sample: []
searchTypes_class: Swift.__SwiftDeferredNSArray
searchTypes_count: 6
searchTypes_sample: hele, selfBeaconing, accessory, localFindable, accessory, durian
searchPriority_class: <nil>
searchPriority_count: 0
searchPriority_sample: []
searchLocationSources_class: Swift.__SwiftDeferredNSArray
searchLocationSources_count: 12
searchLocationSources_sample:
  connectionEvent
  connectionmaintenance
  disconnection
  harvesterNetwork
  harvesterOnDiskNearOwner
  harvesterOnDiskWild
  intentLocationUpdate
  intentResponse
  localReductiveFilter
  pairingLocationManager
  selfPublish
  ownedDeviceLocation
cachePolicy: foregroundRefresh
bundleIdentifier: com.apple.findmy
subscribe: true
reportDeviceEvents: false or true depending on captured context snapshot
primaryIndexRange: { location: 0, length: 0 }
lastOnlineLocationInfo_class: _TtGCs26_SwiftDeferredNSDictionaryV10Foundation4UUIDCSo24SPLastOnlineLocationInfo_$
lastOnlineLocationInfo_count: 10
```

The sampled `lastOnlineLocationInfo` keys were UUIDs. The sampled values were
`SPLastOnlineLocationInfo` objects with timestamp-only state:

```text
accessors: timestamp
ivars: _timestamp, _updatedOn
```

No sampled `SPLastOnlineLocationInfo` value exposed latitude, longitude, or a
nested location object through the existing accessor/ivar serializers.

Then the active latest-single route was triggered:

```text
POST /api/v1/icloud/findmy/searchparty/locations/latest-single
POST /api/v1/icloud/findmy/searchparty/locations
```

The probe path itself constructed or passed 53 identifiers and 12 sources:

```text
latest_locations_identifier_count: 53
latest_locations_source_count: 12
context_search_identifier_count: 53
context_search_location_source_count: 12
context_report_device_events: true
```

However, Find My's real retained `lastContext` still reported:

```text
searchIdentifiers_count: 0
primaryIndexRange: { location: 0, length: 0 }
lastOnlineLocationInfo_count: 10
```

The completed callbacks were still empty:

```text
SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion: -> nil
SPOwnerSession.locationsForBeacons:completion: -> __NSDictionary0 count 0
```

Interpretation:

The local result path is now well-instrumented, and it consistently shows
empty locations. The strongest new signal is that the real
`SPLocationFetchContext` retained by `SPOwnerSessionLocationFetch` has no
`searchIdentifiers` and a zero-length `primaryIndexRange`, even though it has a
non-empty `lastOnlineLocationInfo` map and the full set of location sources.

The active probe can collect 53 beacon identifiers and call the XPC
`latestLocationsForIdentifiers:fetchLimit:sources:completion:` path, but that
does not appear to mutate Find My's real retained context or produce a non-empty
`locationsByBeaconIdentifier` result on this machine.

Next better lead:

- Stop treating the retained Find My context as authoritative for identifier
  population. Instead, build a controlled `SPLocationFetchContext` using the 53
  known identifiers and the 12 observed sources, then call
  `SPOwnerSessionLocationFetch locationForContext:completion:` or
  `subscribeAndFetchLocationForContext:completion:` with that explicit context.
- If constructing the context through public initializers is not possible,
  clone the real context and set `_searchIdentifiers` / `_primaryIndexRange`
  with KVC or ivar writes before invoking the fetch method.

## Live try: controlled fetch context

Tested locally on 2026-07-07 with helper dylib md5
`37ea2f55f305ba1a976d48c813aa1154`.

Implementation changes:

- The focused `locations/proxy-context` probe now builds a controlled
  `SPLocationFetchContext` with a generated `NSArray` of beacon identifiers
  instead of an `NSSet`.
- It records whether KVC actually populated context fields.
- It directly writes `_primaryIndexRange` to `{0, identifierCount}` because
  there is no setter exposed in the observed runtime method list.
- It invokes the local `SPOwnerSessionLocationFetch` methods with the
  controlled context:
  - `locationForContext:completion:`
  - `subscribeAndFetchLocationForContext:completion:`
- It still invokes the XPC proxy `locationForContext:completion:` path as a
  comparison.
- The location-probe status payload was trimmed below the helper socket decode
  limit by replacing the full lower-layer class dump with a class-name list and
  reducing related-object method/ivar summaries.

Route sequence:

```text
POST /api/v1/icloud/findmy/searchparty/locations/proxy-context
POST /api/v1/icloud/findmy/searchparty/locations
```

The controlled context was successfully populated:

```text
controlled_context_assignment:
  identifier_array_class: __NSArrayI_Transfer
  identifier_array_count: 53
  search_identifiers_after_kvc_count: 53
  search_identifiers_final_count: 53
  source_argument_class: Swift.__SwiftDeferredNSArray
  source_count: 12
  search_location_sources_after_kvc_count: 12
  search_location_sources_final_count: 12
  primary_index_range_ivar_write: true

context_detail:
  searchIdentifiers_count: 53
  searchLocationSources_count: 12
  primaryIndexRange: { location: 0, length: 53 }
  subscribe: true
  reportDeviceEvents: true
```

The probe still did not return coordinates:

```text
probe_status: timed_out
pending_completion_count: 3
completion_count: 2

SPOwnerSession.locationsForBeacons:completion:
  result_class: __NSDictionary0
  count: 0

SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.controlledContext
  result_class: <nil>
```

A late status read 45 seconds later was unchanged:

```text
probe_status: timed_out
pending_completion_count: 3
completion_count: 2
```

Interpretation:

The previous blocker, an empty `searchIdentifiers` array and zero-length
`primaryIndexRange`, was removed for the controlled context. SearchParty still
did not return item/device coordinates on this machine. The local subscribe
method completed with `nil`, while `locationsForBeacons:` completed with an
empty dictionary. The remaining pending calls are consistent with
`startUpdatingSimpleBeaconsWithContext:completion:`, local
`locationForContext:completion:`, and proxy `locationForContext:completion:`
not calling their completions within the observed window.

This suggests the next coordinate-bearing lead is no longer context population
alone. The likely missing requirement is either:

- a different context construction initializer or service-owned context token,
- a required authorization/session state inside the SearchParty XPC service,
- a different identifier namespace for `locationForContext:` than the beacon
  UUIDs collected from `allBeaconsWithCompletion:`, or
- a device-event / live-location request path that must be triggered before
  location results are materialized.

## Live try: `requestLiveLocationForUUID:completion:`

Tested locally on 2026-07-07 with helper dylib md5
`ed38884efd0daf3a04467d68517cb14a`.

Implementation changes:

- Added a focused SearchParty location probe step for
  `SPOwnerSessionXPCProtocol requestLiveLocationForUUID:completion:`.
- Added server route:
  `POST /api/v1/icloud/findmy/searchparty/locations/live-request`.
- Added `searchPartyIdentifierCandidateMapForBeacon:` so the probe records
  which identifier namespace each request used.
- Capped the live request matrix to four candidates to keep the helper response
  below the socket decode limit.
- Rebuilt `packages/server/dist/main.js` directly with webpack because
  `npm run build` failed on this machine with:

```text
npm error Invalid property "devEngines.node"
```

Route sequence:

```text
POST /api/v1/icloud/findmy/searchparty/locations/live-request
POST /api/v1/icloud/findmy/searchparty/locations
POST /api/v1/icloud/findmy/searchparty/debug
```

The route registered and started successfully:

```text
focused_probe_step: 5
pending_completion_count: 6
invoked_location_selectors:
  SPOwnerSession.locationsForBeacons:completion:
  SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:
  SPOwnerSessionXPCProtocol.requestLiveLocationForUUID.identifierVariants
```

The live request matrix used these identifier shapes. Values and names are
anonymized, but formats are preserved:

```text
candidate 0:
  variant: identifier
  request_value_class: __NSConcreteUUID
  identifier format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  name format: item display name

candidate 1:
  variant: stableIdentifier
  request_value_class: __NSCFString
  identifier format: A:/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX~#XXXXXXXXXXXXXXX
  name format: same item display name as candidate 0

candidate 2:
  variant: productUUID
  request_value_class: __NSConcreteUUID
  identifier format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  name format: same item display name as candidate 0

candidate 3:
  variant: identifier
  request_value_class: __NSConcreteUUID
  identifier format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  name format: different item display name
```

Observed completions after the normal wait and a late follow-up read:

```text
probe_status: timed_out
pending_completion_count: 4
completion_count: 2

SPOwnerSessionXPCProtocol.requestLiveLocationForUUID.variant.0:
  result_class: <nil>

SPOwnerSession.locationsForBeacons:completion:
  result_class: __NSDictionary0
  count: 0
```

The remaining live-request variants did not call their completion blocks during
the observed window. A late status read was unchanged.

Passive debug snapshot after the live request:

```text
POST /api/v1/icloud/findmy/searchparty/debug
response size: 42126 bytes
searchparty_accessors count: 24

recent relevant events:
  receivedUpdatedLocation: SPLocationFetchResult
  locationsByBeaconIdentifier: __NSDictionary0 count 0
  setLocationUpdateBlock: SPLocationFetchResult locations count 0
```

Interpretation:

`requestLiveLocationForUUID:completion:` is callable, and at least one UUID
candidate reaches its completion block, but it completed with `nil`. The live
request did not cause a later non-empty `SPLocationFetchResult`; passive
captures still show empty `locationsByBeaconIdentifier` dictionaries.

The `stableIdentifier` string is probably not a valid argument for the UUID
selector even though its format is useful evidence. The next identifier-focused
probe should split method calls by expected argument type:

- send only `NSUUID` candidates to `requestLiveLocationForUUID:completion:`,
- try string/stable identifiers through methods whose names say
  `Identifier`, especially `beaconForIdentifier:completion:`, and
- inspect whether those methods return a service-owned beacon object or
  identifier that differs from the local `allBeaconsWithCompletion:` UUIDs.

## Next track: identifier resolution before location fetch

The next probe should resolve local beacon identifiers through SearchParty XPC
before asking for coordinates. The live request path proved the selector is
callable, but raw local UUID candidates either completed with `nil` or did not
complete. A reasonable explanation is that the location APIs expect a
service-owned identifier or service-returned beacon object rather than every
identifier visible on local `SPBeacon` instances.

Planned instrumentation:

- Add a focused route for identifier resolution.
- Call `SPOwnerSessionXPCProtocol beaconForIdentifier:completion:` with string
  identifiers, especially `stableIdentifier`.
- Call `SPOwnerSessionXPCProtocol beaconForUUID:completion:` with `NSUUID`
  variants such as `identifier`, `productUUID`, and `ownerBeaconIdentifier`
  when present.
- Optionally call `beaconGroupsForUUIDs:completion:` with a small UUID sample.
- Compact returned beacon objects with the existing beacon serializer and
  direct field inspection.
- Compare returned service-side identifiers to the local `allBeacons` fields.

Expected useful outcomes:

- A non-nil service-returned beacon whose identifiers differ from the local
  cached beacon.
- A returned object exposing a location-bearing field or a provider-specific
  identifier.
- A consistent `nil` or timeout result, which would push the next lead toward
  SearchParty authorization/session state rather than identifier translation.

## Static inspection: fetch context detail

The next instrumentation pass focuses on the context object passed into
`subscribeAndFetchLocationForContext:completion:` and related fetch methods.
The result setter showed that `SPLocationFetchResult` receives an empty
dictionary, so the useful question is whether the inbound context asks for a
location fetch that SearchParty considers ineligible or empty.

Instrumentation added:

- Add `searchPartyFetchContextDiagnosticsForContext:`.
- Attach `context_detail` to every captured location invocation with a context.
- Attach `context_detail` to `SPLocationFetchContext` summaries.
- Capture bounded samples for:
  - `searchIdentifiers`
  - `searchTypes`
  - `searchPriority`
  - `searchLocationSources`
  - `lastOnlineLocationInfo`
- Capture scalar/simple context fields when available:
  - `cachePolicy`
  - `bundleIdentifier`
  - `subscribe`
  - `reportDeviceEvents`
  - `primaryIndexRange`
- For sampled `lastOnlineLocationInfo` values, capture accessors, ivars,
  descriptions, and any direct location serialization result.

## Live try: identifier resolution

Helper build copied into the server for this run:
`9f7f173e66ea8d169cdd0ed9bdd04615`.

Routes exercised:

- `POST /api/v1/icloud/findmy/searchparty/locations/resolve-identifiers`
- `POST /api/v1/icloud/findmy/searchparty/locations`

The focused probe found these methods on the
`__NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol` proxy:

- `beaconForIdentifier:completion:`
- `beaconForUUID:completion:`
- `beaconGroupsForUUIDs:completion:`

The helper built a small candidate set from local beacon fields while keeping
the route output bounded. The useful argument formats were:

- `identifier`: `__NSConcreteUUID`, format `UUID`
- `stableIdentifier`: `__NSCFString`, format `A:/UUID~#SERIAL`
- `productUUID`: `__NSConcreteUUID`, format `UUID`

The live status response timed out with `pending_completion_count` at `5`.
Only one completion fired:

```text
SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0
  count: 0
```

No completion arrived during the observed window for:

- `beaconForIdentifier:completion:`
- `beaconForUUID:completion:`
- `beaconGroupsForUUIDs:completion:`

The same run captured a populated fetch context later in the log:

- `searchIdentifiers`: `__NSArrayI_Transfer`, count `53`, element class
  `__NSConcreteUUID`
- `primaryIndexRange`: `{ location: 0, length: 53 }`
- `lastOnlineLocationInfo`: Swift deferred dictionary, count `10`
- `searchLocationSources`: count `12`
- `searchTypes`: count `6`

Interpretation:

The identifier-resolution selectors are present and can be invoked without an
immediate Objective-C exception, but they did not call back in this combined
probe. That points either to SearchParty service/session gating, missing call
preconditions, or the combined probe issuing too many XPC calls at once. The
separate context capture is still promising because SearchParty itself is
building a 53-identifier location fetch context.

Next useful probe:

- split these into one-method routes so a single `beaconForUUID:` or
  `beaconForIdentifier:` call cannot be masked by other pending XPC calls;
- start with one `beaconForUUID:` call using a UUID from the captured
  `searchIdentifiers` array rather than a local beacon property; and
- inspect unified logs around the XPC call for service-side rejection or
  authorization errors.

## Live try: split identifier resolution

Helper build copied into the server for this run:
`3e1b33b4fa1ed55b8245c9e3b3acb367`.

Important runtime note: when running from `packages/server/dist/main.js`, the
injected helper is loaded from `packages/server/dist/appResources/...`, not the
source `packages/server/appResources/...` path. The first attempt hit the old
helper until the dylib was also copied into `dist/appResources` and Find My was
restarted.

Routes added:

- `POST /api/v1/icloud/findmy/searchparty/locations/resolve-context-uuid`
- `POST /api/v1/icloud/findmy/searchparty/locations/resolve-stable-identifier`

### `beaconForUUID:` with one context UUID

Result: successful.

The route used one UUID candidate from the SearchParty location context shape:

- argument variant: `generatedSearchIdentifiers`
- argument class: `__NSConcreteUUID`
- context search identifier count: `53`
- selector availability: `beaconForUUID:completion:` present

Completions:

```text
SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:
  result class: <nil>

SPOwnerSessionXPCProtocol.beaconForUUID.contextIdentifier.single:
  result class: SPBeacon

SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0
  count: 0
```

The returned `SPBeacon` exposed the expected beacon fields. Anonymized field
formats:

- `serialNumber`: string
- `role`: `SPBeaconRole`
- `batteryLevel`: numeric string
- `identifier`: `__NSConcreteUUID`
- `name`: string
- `stableIdentifier`: `PRODUCT~#PAIRING_OR_GROUP_ID~#SERIAL`

This is the first internal probe that resolves a context identifier back into
a service-owned beacon object.

### `beaconForIdentifier:` with one stable string

Result: unsafe for the current route shape.

The request to start the route timed out. The server log showed Find My force
quit immediately after the route request, then the dylib plugin relaunched
Find My and the helper reconnected. The status route afterwards returned
`not_started`, so the crash happened before a probe result could be stored.

Interpretation:

- `beaconForUUID:` with one UUID is viable and returns an `SPBeacon`.
- `beaconForIdentifier:` with the local stable string shape is not a good next
  coordinate path and may crash the injected process.
- The next coordinate-focused lead is to chain from the returned `SPBeacon`:
  call location fetch methods with `@[resolvedBeacon]`, and separately try the
  returned beacon's own `identifier` through `latestLocationsForIdentifiers`.

## Live try: resolved beacon location chain

Helper build copied into the server for this run:
`910e59d647b4c02ef7631ca4e0c476f7`.

Route added:

- `POST /api/v1/icloud/findmy/searchparty/locations/resolved-beacon-location`

Probe shape:

1. Resolve one context/search identifier UUID with
   `SPOwnerSessionXPCProtocol beaconForUUID:completion:`.
2. If that returns an `SPBeacon`, call
   `SPOwnerSession locationsForBeacons:completion:` with an array containing
   only that returned beacon.
3. Also call
   `SPOwnerSessionXPCProtocol latestLocationsForIdentifiers:fetchLimit:sources:completion:`
   with the returned beacon's own `identifier`.

Observed method availability:

- `beaconForUUID:completion:` present
- `locationsForBeacons:completion:` present
- `latestLocationsForIdentifiers:fetchLimit:sources:completion:` present

Result after 60 seconds, and unchanged after a later read:

```text
status: timed_out
pending_completion_count: 1
completion count: 4

SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:
  result class: <nil>

SPOwnerSessionXPCProtocol.beaconForUUID.resolvedBeaconLocation:
  result class: SPBeacon

SPOwnerSession.locationsForBeacons:completion:.resolvedBeacon
  result class: __NSDictionary0
  count: 0

SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0
  count: 0
```

The missing fifth completion is:

```text
SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.resolvedBeaconIdentifier
```

Interpretation:

Resolving a SearchParty UUID to a service-owned `SPBeacon` is now confirmed and
repeatable. However, feeding that returned object into `locationsForBeacons:`
still returns an empty dictionary, and feeding its `identifier` into
`latestLocationsForIdentifiers` does not call back in the observed window.

This suggests the remaining coordinate gap is not just "wrong local beacon
object"; it is likely in the location fetch context, service-side eligibility,
or a different result/callback path used by Find My after it obtains the beacon.

## Live try: single identifier context fetch

Helper build copied into the server for this run:
`09c6b407636e5eb8b0896415fe79a6fb`.

Route added:

- `POST /api/v1/icloud/findmy/searchparty/locations/context-single-identifier`

Probe shape:

1. Start from the same real SearchParty context shape captured from Find My.
2. Copy context fields where available:
   - `bundleIdentifier`
   - `cachePolicy`
   - `subscribe`
   - `reportDeviceEvents`
   - `searchTypes`
   - `searchLocationSources`
   - `lastOnlineLocationInfo`
3. Replace `searchIdentifiers` with a one-element UUID array.
4. Set `_primaryIndexRange` to `{ location: 0, length: 1 }`.
5. Call:
   - `SPOwnerSessionLocationFetch locationForContext:completion:`
   - `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
   - `SPOwnerSessionXPCProtocol locationForContext:completion:`

The constructed single-identifier context looked correct:

- argument class: `__NSConcreteUUID`
- argument variant: `generatedSearchIdentifiers`
- `searchIdentifiers` final count: `1`
- `searchLocationSources` final count: `12`
- `_primaryIndexRange` ivar write: `true`
- original generated context identifier count: `53`

Observed method availability:

- `locationFetch.locationForContext`: present
- `locationFetch.subscribeAndFetchLocationForContext`: present
- `proxy.locationForContext`: present

Result after 75 seconds, unchanged after a later read:

```text
status: timed_out
pending_completion_count: 3
completion count: 2

SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.singleIdentifierContext
  result class: <nil>

SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0
  count: 0
```

The missing completions were:

```text
SPOwnerSessionLocationFetch.locationForContext:completion:.singleIdentifierContext
SPOwnerSessionXPCProtocol.locationForContext:completion:.singleIdentifierContext
SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:
```

Interpretation:

The one-identifier context is accepted enough for
`subscribeAndFetchLocationForContext:` to return, but it returns `nil`. The two
direct `locationForContext:` variants did not call back. This makes the
remaining likely gap more specific: the context object shape alone is not
sufficient, even when narrowed cleanly to one UUID. The next useful work should
inspect what Find My does after a context fetch is subscribed, especially
delegate/block callbacks such as `receivedUpdatedLocation` and
`latestLocationsUpdatedBlock`, rather than only completion-returning methods.
