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

## Live try: delegated owner-context checkpoints

Tested locally on 2026-07-07 with helper dylib md5
`c2ec414d629c99d8db06510469dc7dda`.

Route shape:

```text
POST /api/v1/icloud/findmy/searchparty/locations/delegated-checkpoint/:checkpoint
```

The route was extended with owner-only checkpoints that avoid reading the
`SPOwnerSession` proxy. This matters because prior `proxy`, `responds-proxy`,
and `signature-proxy` checkpoints timed out and crashed Find My by touching the
XPC proxy path. These checkpoints instead read the already captured context or
the `SPOwnerSessionLocationFetch` object.

Checkpoint results:

| Checkpoint | Result |
| --- | --- |
| `captured-context` | Completed. `captured_context_class = SPLocationFetchContext`; context pointer `0x60000366eee0`; owner session count `2`. |
| `captured-context-detail` | Completed. The captured context includes `searchTypes_count = 6`, `searchLocationSources_count = 12`, `searchIdentifiers_count = 0`, `lastOnlineLocationInfo_count = 10`, `cachePolicy = foregroundRefresh`, `subscribe = true`, `reportDeviceEvents = true`. |
| `owner-last-context` | Completed. `SPOwnerSession.lastContext` is nil. |
| `location-fetch-last-context` | Completed. `location_fetch_class = SPOwnerSessionLocationFetch`; `location_fetch_last_context_class = SPLocationFetchContext`; pointer matches the captured context `0x60000366eee0`. |

The captured `SPLocationFetchContext` has these `searchTypes`:

```text
hele
selfBeaconing
accessory
localFindable
accessory
durian
```

It has these `searchLocationSources`:

```text
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
```

The `lastOnlineLocationInfo` dictionary is a Swift deferred dictionary keyed by
`NSUUID` values. It contained 10 UUID keys in this run. Sample entries serialize
as `SPLastOnlineLocationInfo` with timestamp fields such as:

```text
key 243A7F6E-B4ED-481F-A2E0-54EF9AD6EDB6
timestamp 2026-07-07 20:35:26 +0000
updatedOn 2026-07-07 20:35:29 +0000

key 127D90D3-0E42-436B-8BFB-564EF996A8E6
timestamp 2026-07-04 21:36:59 +0000
updatedOn 2026-07-07 20:35:23 +0000
```

Server logs for these four requests showed normal completion and did not show a
Find My crash. The only unrelated warning still present was the existing System
Events Automation denial from the old UI-hiding path.

Interpretation:

The useful context is not stored on `SPOwnerSession.lastContext`; it is stored
on `SPOwnerSessionLocationFetch.lastContext`, and it is the same
`SPLocationFetchContext` already captured by the hook. That context is
configured broadly enough to include owned devices and item-like beacon types:
`ownedDeviceLocation` appears in `searchLocationSources`, and `accessory`,
`durian`, `localFindable`, and `selfBeaconing` appear in `searchTypes`.

The current missing piece is still the coordinate-bearing result. This context
does know about last-online metadata for 10 beacon UUIDs, but the local
`SPLocationFetchResult.locationsByBeaconIdentifier` setter and getter have only
seen empty dictionaries so far. The next productive inspection point is to
correlate these 10 UUIDs against known beacons/devices, then invoke or observe a
fetch path that uses one or more of those UUIDs as explicit
`searchIdentifiers`, instead of relying on the broad zero-identifier context.

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

## Live try: passive callback watch after subscription

Helper build copied into the server for this run:
`2aea4ad4a2524e8b5d320c669cf54c89`.

Route added:

- `POST /api/v1/icloud/findmy/searchparty/locations/callback-watch`

Instrumentation added:

- Wrapped `setLocationUpdateBlock:` result blocks into the active location
  probe.
- Also route `setLatestLocationsUpdatedBlock:`,
  `setDelegatedLocationUpdateBlock:`, and `setDeviceEventUpdateBlock:` through
  the same SearchParty result block wrapper when their block signatures match
  `SPLocationFetchResult` or `SPDeviceEventFetchResult`.
- Added `passive_location_events` to the active probe state. This is separate
  from `completion_results`, so passive callbacks do not decrement
  `pending_completion_count`.
- Existing `receivedUpdatedLocation:` swizzling now stores matching results in
  the active probe-local passive event list.

Probe shape:

1. Build the same single-identifier `SPLocationFetchContext` from the previous
   focused probe.
2. Call only
   `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
   for the focused step.
3. Poll the normal
   `POST /api/v1/icloud/findmy/searchparty/locations` status route and inspect
   `passive_location_events`.

Observed route startup:

- HTTP status: `200`
- focused step: `11`
- callback-watch method availability:
  - `locationFetch.subscribeAndFetchLocationForContext`: present
- route registered in the built server as:
  - `/api/v1/icloud/findmy/searchparty/locations/callback-watch`

Observed after about 80 seconds:

```text
status: timed_out
focused_probe_step: 11
pending_completion_count: 1
completion_results_count: 2
passive_location_event_count: 4

completion 0:
  selector: SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.callbackWatch
  result class: <nil>

completion 1:
  selector: SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0

passive 0:
  phase: receivedUpdatedLocation
  selector: receivedUpdatedLocation:
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

passive 1:
  phase: locationUpdateBlock
  selector: setLocationUpdateBlock:
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

passive 2:
  phase: receivedUpdatedLocation
  selector: receivedUpdatedLocation:
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

passive 3:
  phase: locationUpdateBlock
  selector: setLocationUpdateBlock:
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0
```

Interpretation:

The passive callback path is real and reachable. Find My invokes both
`receivedUpdatedLocation:` and the installed location update block with
`SPLocationFetchResult` objects after the subscription attempt. However, on this
Mac, the captured `SPLocationFetchResult locationsByBeaconIdentifier`
dictionaries are still empty for this single-identifier context.

This narrows the coordinate gap again: the issue is no longer only that we were
watching completion-returning APIs. We are now watching the asynchronous update
channel too, and the update channel is delivering empty location result
objects.

Late-poll note:

A later status poll after another observation window did not return cleanly to
the HTTP caller. The server log showed:

```text
Failed to decode BlueBubblesHelper data!
SyntaxError: Unterminated string in JSON at position 65510
SyntaxError: Unexpected non-whitespace character after JSON at position 3
```

The log also showed that the helper had reached `passive_location_event_count:
6` before the decode failure. The likely cause is that the full probe status
payload, including large context/accessor snapshots, grew too large or was
truncated over the private API socket response. The next instrumentation step
should add a compact status mode or trim repeated large fields for long-running
callback-watch probes before relying on late polling.

## Live try: compact callback-watch status

Helper build copied into the server for this run:
`52751901ea2f3159ad33681a309d049f`.

Route added:

- `POST /api/v1/icloud/findmy/searchparty/locations/compact`

Purpose:

The normal full status route can return very large context, accessor, and object
snapshots. During callback-watch testing, that eventually produced a private API
JSON decode failure. The compact route keeps only the fields needed for this
coordinate search:

- probe status and focused step
- pending completion count
- context identifier/source counts
- callback-watch method availability
- compact completion summaries
- compact passive location update summaries
- non-empty location dictionaries if any appear

Fresh callback-watch validation:

1. Start:

```text
POST /api/v1/icloud/findmy/searchparty/locations/callback-watch

HTTP status: 200
focused_probe_step: 11
pending_completion_count: 3
probe status: started
```

2. Poll compact status after about 80 seconds:

```text
POST /api/v1/icloud/findmy/searchparty/locations/compact

HTTP status: 200
probe status: timed_out
focused_probe_step: 11
pending_completion_count: 1
passive_location_event_count: 4
callback_watch_method_availability:
  locationFetch.subscribeAndFetchLocationForContext: present
```

Compact completion results:

```text
SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.callbackWatch
  result class: <nil>

SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0
```

Compact passive events:

```text
receivedUpdatedLocation:
  source class: SPOwnerSessionLocationFetch
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

setLocationUpdateBlock:
  source class: SPOwnerSession
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

receivedUpdatedLocation:
  source class: SPOwnerSessionLocationFetch
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

setLocationUpdateBlock:
  source class: SPOwnerSession
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0
```

Interpretation:

The compact route fixes the observability problem from the prior late poll. It
does not change the coordinate result: the subscription callback channel still
fires, but the `SPLocationFetchResult` objects delivered through that channel
have empty `locationsByBeaconIdentifier` dictionaries on this Mac.

Next best lead:

Use the compact route for longer observation windows, then add one more focused
probe that uses the full real context instead of the single-identifier narrowed
context while still watching passive callbacks. If full-context passive results
also stay empty, the likely remaining gap is service-side location eligibility
or a different owner-session/device-specific request path, rather than response
transport or callback visibility.

## Live try: full-context passive callback watch

Helper build copied into the server for this run:
`265ac359c99ca78ae3fff3efa24bdeb3`.

Route added:

- `POST /api/v1/icloud/findmy/searchparty/locations/callback-watch-full-context`

Purpose:

The prior callback-watch probe used a narrowed one-identifier
`SPLocationFetchContext`. This probe tests whether the full generated context,
with all collected SearchParty identifiers and all collected location sources,
causes the service to populate `SPLocationFetchResult locationsByBeaconIdentifier`
through the same passive callback channel.

Probe shape:

1. Build the generated full `SPLocationFetchContext`.
2. Preserve:
   - all collected `searchIdentifiers`
   - all collected `searchLocationSources`
   - captured `searchTypes`
   - captured `lastOnlineLocationInfo`
   - `subscribe = true`
   - `reportDeviceEvents = true`
3. Set `_primaryIndexRange` to cover the full generated identifier array.
4. Call:
   - `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
5. Poll:
   - `POST /api/v1/icloud/findmy/searchparty/locations/compact`

Start result:

```text
HTTP status: 200
focused_probe_step: 12
pending_completion_count: 3
probe status: started
```

Compact status after about 80 seconds:

```text
HTTP status: 200
probe status: completed
focused_probe_step: 12
callback_watch_context: full
pending_completion_count: 0
context_search_identifier_count: 53
context_search_location_source_count: 12
passive_location_event_count: 6
locationFetch.subscribeAndFetchLocationForContext: present
```

Completion results:

```text
SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:
  result class: <nil>

SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.fullContextCallbackWatch
  result class: <nil>

SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0
```

Passive callback results:

```text
receivedUpdatedLocation:
  source class: SPOwnerSessionLocationFetch
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

setLocationUpdateBlock:
  source class: SPOwnerSession
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

receivedUpdatedLocation:
  source class: SPOwnerSessionLocationFetch
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

setLocationUpdateBlock:
  source class: SPOwnerSession
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

receivedUpdatedLocation:
  source class: SPOwnerSessionLocationFetch
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

setLocationUpdateBlock:
  source class: SPOwnerSession
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0
```

Interpretation:

Full-context subscription behaves better operationally than the single-identifier
watch because the focused probe completed instead of timing out. It also
delivered six passive `SPLocationFetchResult` objects. However, every passive
result still had an empty `locationsByBeaconIdentifier` dictionary.

This makes the strongest current conclusion:

- The helper can see SearchParty owner sessions.
- The helper can build a full context with 53 identifiers and 12 location
  sources.
- The helper can subscribe successfully enough for SearchParty to call passive
  update methods.
- The callback transport and compact polling route work.
- The actual SearchParty result payloads visible through this owner-session
  location-fetch path are empty on this Mac.

Next lead:

Move away from `SPOwnerSessionLocationFetch` context subscription as the primary
coordinate source and inspect the XPC/service methods that Find My uses for
device rows with known local locations, especially the methods around
`ownedDeviceLocation`, device event updates, delegated location updates, and any
device-specific provider/session classes. The current evidence points away from
"we missed the callback" and toward "this is not the callback path that carries
device/item coordinates on this host."

## Live Try: Device-Event Callback Watch

Commit context:

- helper dylib hash: `acb4fec3d208704428ecbd0b8563318d`
- helper focused step: `13`
- helper action: `debug-findmy-searchparty-locations-device-event-watch`
- server route:
  `POST /api/v1/icloud/findmy/searchparty/locations/device-event-watch`

Why this was tried:

The generated `SPLocationFetchContext` already had `reportDeviceEvents = true`.
The helper also had swizzles for `setDeviceEventUpdateBlock:`,
`setDeviceEventUpdates:`, and `receivedUpdatedDeviceEvents:`. This run made
`receivedUpdatedDeviceEvents:` feed probe-local `passive_location_events` and
then subscribed using the full generated context, so a real device-event result
would show up in the compact status.

Probe shape:

1. Build the generated full `SPLocationFetchContext`.
2. Preserve all generated identifiers and all generated location sources.
3. Preserve `reportDeviceEvents = true`.
4. Call:
   - `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
5. Capture these passive channels:
   - `receivedUpdatedLocation:`
   - `setLocationUpdateBlock:`
   - `receivedUpdatedDeviceEvents:`
   - `setDeviceEventUpdateBlock:`

Start result:

```text
HTTP status: 200
focused_probe_step: 13
probe status: started
context searchIdentifiers count: 53
context searchLocationSources count: 12
context searchLocationSources includes: ownedDeviceLocation
context reportDeviceEvents: true
```

Compact status after about 80 seconds:

```text
HTTP status: 200
probe status: timed_out
focused_probe_step: 13
callback_watch_context: deviceEventsFull
pending_completion_count: 1
context_search_identifier_count: 53
context_search_location_source_count: 12
passive_location_event_count: 4
locationFetch.subscribeAndFetchLocationForContext: present
```

Compact status after a longer tail:

```text
HTTP status: 200
probe status: timed_out
focused_probe_step: 13
callback_watch_context: deviceEventsFull
pending_completion_count: 1
context_search_identifier_count: 53
context_search_location_source_count: 12
passive_location_event_count: 8
last passive event timestamp: 1783449872.077241 / 1783449872.082479
```

Completion results from the longer-tail status:

```text
SPOwnerSession.locationsForBeacons:completion:
  result class: __NSDictionary0

SPOwnerSessionLocationFetch.subscribeAndFetchLocationForContext:completion:.deviceEventCallbackWatch
  result class: <nil>
```

Passive callback results:

```text
receivedUpdatedLocation:
  source class: SPOwnerSessionLocationFetch
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

setLocationUpdateBlock:
  source class: SPOwnerSession
  result class: SPLocationFetchResult
  locationsByBeaconIdentifier count: 0

The same pair repeated four times during the longer-tail watch.
```

Important negative result:

No `receivedUpdatedDeviceEvents:` or `setDeviceEventUpdateBlock:` passive event
appeared during this run, and no `SPDeviceEventFetchResult` was observed in the
compact payload. Setting `reportDeviceEvents = true` on this full location fetch
context is not enough to make the location subscription deliver device-event
payloads on this Mac.

Interpretation:

This reinforces the prior conclusion that the generic
`SPOwnerSessionLocationFetch` subscription path is live but not carrying the
coordinates we need. The next SearchParty lead should inspect the owner XPC
proxy methods and provider objects around device-specific events rather than
continuing to vary the same location-fetch context.

## Live Try: Wider Owner Proxy Selector Capture

Commit context:

- helper dylib hash: `25d3f1194e3be7b40d39f1b221c8068c`
- route used:
  `POST /api/v1/icloud/findmy/searchparty/locations/device-event-watch`
- code change: raised `compactRelatedSearchPartyObject` matched selector limit
  from 12 to 60.

Important safety note:

Before settling on the selector-limit increase, a broader custom
`method_surfaces` probe was tried. That version attempted a richer method
surface capture and caused Find My to disconnect / be force-quit immediately
after the request. The server then timed out the transaction. That approach was
backed out and should not be repeated as-is. The retained approach only expands
the already-used related-object `class_copyMethodList` selector capture.

Result:

The widened related-object selector capture completed successfully and returned
a 200 response. It did not crash Find My.

Owner session XPC proxy selectors now visible:

```text
beaconForIdentifier:completion:
acceptUTForBeaconUUID:
addSafeLocation:completion:
allBeaconsWithCompletion:
allObservationsForBeacon:completion:
assignSafeLocation:to:completion:
beaconForUUID:completion:
beaconGroupForIdentifier:completion:
beaconGroupsForUUIDs:completion:
beaconStoreStatusWithCompletion:
beaconingIdentifierForMACAddress:completion:
beaconsToMaintainPersistentConnection:
beaconsToMaintainWithCompletion:
beaconsToMonitorForSeparation:
delegatedLocationForContext:completion:
disableSeparationMonitoringForBeacons:completion:
enableSeparationMonitoringForBeacons:completion:
fetchFindMyNetworkStatusForMACAddress:completion:
fetchSeparationMonitoringStatus:
fetchUnauthorizedEncryptedPayload:completion:
forceLOIBasedSafeLocationRefresh:
ignoreBeaconByUUID:untilDate:completion:
latestLocationsForIdentifiers:fetchLimit:sources:completion:
locationForContext:completion:
ownerSessionStateWithCompletion:
playUnauthorizedSoundOnBeaconUUID:completion:
removeBeacon:completion:
removeBeaconFromGroup:completion:
removeSafeLocation:completion:
requestLiveLocationForFriend:completion:
requestLiveLocationForUUID:completion:
safeLocationsWithCompletion:
standaloneBeaconsForUUIDs:completion:
stopFetchingUnauthorizedEncryptedPayloadWithCompletion:
tagSeparationStateChanged:beaconUUID:location:completion:
unacceptedBeaconsWithCompletion:
unassignSafeLocation:from:completion:
unknownBeaconsForUUIDs:completion:
updateBeaconObservations:completion:
updateSafeLocation:completion:
waitForBeaconStoreAvailableWithCompletion:
```

Beacon manager XPC proxy selectors now visible:

```text
allBeaconsWithCompletion:
beaconForUUID:completion:
beaconingKeysForUUID:dateInterval:completion:
beaconingStateWithCompletion:
createOwnedDeviceKeyRecordForUUID:completion:
fetchAllKeyMapFileDescriptorsWithCompletion:
fetchFirmwareVersionForBeacon:completion:
fetchUserStatsForBeacon:completion:
firmwareUpdateCandidateBeaconsWithCompletion:
firmwareUpdateStateForBeaconUUID:completion:
getMacBeaconConfigWithCompletion:
initiateFirmwareUpdateForAllEligibleBeaconsWithCompletion:
notificationBeaconForSubscriptionId:completion:
ownedDeviceKeyRecordsForUUID:completion:
poisonBeaconIdentifier:completion:
purgeOwnedDeviceKeyRecordsForUUID:completion:
removeDuplicateBeaconsWithCompletion:
startUpdatingSimpleBeaconsWithContext:completion:
unacceptedBeaconsWithCompletion:
updateBeacon:updates:completion:
```

Interpretation:

`delegatedLocationForContext:completion:` is the next best method to test. It
accepts the same kind of context shape as `locationForContext:completion:` but
is a distinct owner XPC method, and the name suggests it may be closer to a
shared/delegated device or item location path than the generic location-fetch
subscription path.

## Live Try: Delegated Location Context

Commit context:

- helper dylib hash: `10dd4ee4824eb963a176c6364a086f45`
- helper focused step: `14`
- helper action: `debug-findmy-searchparty-locations-delegated-context`
- server route:
  `POST /api/v1/icloud/findmy/searchparty/locations/delegated-context`

Probe shape:

1. Build the same generated full `SPLocationFetchContext`.
2. Preserve all generated identifiers and all generated location sources.
3. Select the first available target:
   - `SPOwnerSession delegatedLocationForContext:completion:`
   - owner session XPC proxy `delegatedLocationForContext:completion:`
4. Invoke the selected target with the generated context and a completion block.
5. Poll compact status.

Start result:

```text
HTTP status: 200
message: Successfully started Find My SearchParty delegated context probe
focused_probe_step: 14
probe status: started
pending_completion_count: 3
```

Runtime result:

The start call returned successfully, but about eight seconds later the Find My
helper disconnected and the server logged:

```text
Private API Helper (com.apple.findmy) disconnected
FindMy Process was force quit
FindMyDylibPlugin Detected DYLIB crash for App FindMy
```

After Find My relaunched and the helper reconnected, compact status returned:

```text
status: not_started
```

That means the in-memory probe state was lost during the Find My process
restart, before a delegated-location completion could be captured.

Interpretation:

`delegatedLocationForContext:completion:` is unsafe with the generated full
`SPLocationFetchContext` used by the current probe. It should be treated as a
crash-producing lead unless we first learn the exact context shape Find My uses
when calling delegated location internally.

Next safer direction:

Inspect passive calls or swizzle around the delegated-location selector instead
of invoking it directly with our generated context. The key missing detail is
the context shape and call timing that Find My expects for delegated location.

## Live Try: Delegated Watch Inspection

Commit context:

- helper dylib hash for the final stable build:
  `f31f06ebf453057e791321c87f97b258`
- helper focused step: `15`
- helper action: `debug-findmy-searchparty-locations-delegated-watch`
- server route:
  `POST /api/v1/icloud/findmy/searchparty/locations/delegated-watch`

What was tried:

1. Added delegated selector hooks for
   `delegatedLocationForContext:completion:` and
   `subscribeDelegatedLocationUpdatesForContext:completion:` using the existing
   context/completion swizzle shape.
2. Tried installing those hooks on `SPOwnerSession`,
   `SPOwnerSessionLocationFetch`, and then the dynamic owner XPC proxy class.
3. Removed XPC proxy swizzling after the route crashed Find My immediately.
4. Removed all delegated selector swizzling after static-class delegated
   swizzling also crashed Find My before probe state could be stored.
5. Removed `startRefreshing` from this route after non-mutating delegated
   signature inspection still crashed before state was stored.
6. Landed a minimal route that only confirms a captured `SPOwnerSession` exists
   and returns before refresh, method-surface enumeration, proxy inspection,
   delegated selector swizzling, or delegated invocation.

Observed crash pattern:

```text
Request to /api/v1/icloud/findmy/searchparty/locations/delegated-watch
Private API Helper (com.apple.findmy) disconnected
FindMy Process was force quit
FindMyDylibPlugin Detected DYLIB crash for App FindMy
compact status after relaunch: {"status":"not_started"}
```

This happened for the fuller delegated-watch attempts before any probe state
could be stored. The crash therefore occurred very early in the shared location
probe setup or delegated inspection path, not in a completion callback.

Stable final result:

```json
{
  "status": "completed",
  "captured_owner_session_count": 2,
  "focused_probe_step": 15,
  "called_start_refreshing": false,
  "pending_completion_count": 0
}
```

Server log for the final route:

```text
Find My SearchParty delegated watch location probe start: ... "status":"completed" ...
Request to /api/v1/icloud/findmy/searchparty/locations/delegated-watch took 9 ms
```

Interpretation:

The safe boundary for this route is currently minimal session-presence
inspection. Direct delegated invocation is unsafe, and delegated selector
swizzling appears unsafe even before a completion result is available. The next
delegated-location investigation should use a smaller purpose-built helper entry
point that stores probe state before each individual operation and enables only
one operation per run, starting with non-XPC, non-swizzling reads.

## Live Try: Delegated Checkpoint Route

Commit context:

- helper dylib hash: `e77808bbc32cbaaf1c646d629da08d05`
- helper actions:
  `debug-findmy-searchparty-locations-delegated-checkpoint-<checkpoint>`
- server route:
  `POST /api/v1/icloud/findmy/searchparty/locations/delegated-checkpoint/:checkpoint`

Purpose:

The previous delegated-watch route still hid too much work inside one request.
This route bypasses the shared location probe setup and performs exactly one
small operation per request. Success returns JSON. Failure is visible as a curl
timeout plus immediate Find My helper disconnect in the server log.

Checkpoint results:

| Checkpoint | Result | Notes |
| --- | --- | --- |
| `session` | safe | Returned `SPOwnerSession`; two captured owner sessions were present. |
| `location-fetch` | safe | Returned `SPOwnerSessionLocationFetch`. |
| `proxy` | unsafe | Timed out; Find My helper disconnected and Find My was force quit. |
| `responds-owner` | safe | `SPOwnerSession` responds to both delegated selectors. |
| `responds-location-fetch` | safe | `SPOwnerSessionLocationFetch` responds to neither delegated selector. |
| `responds-proxy` | unsafe | Timed out; same proxy-read crash pattern. |
| `signature-owner` | safe | Both owner delegated selectors have `args=4 return=v`. |
| `signature-location-fetch` | safe | Both delegated selector signatures are `<nil>` on location fetch. |
| `signature-proxy` | unsafe | Timed out; same proxy-read crash pattern. |

Safe owner-session selector evidence:

```json
{
  "owner_responds": {
    "delegatedLocationForContext:completion:": true,
    "subscribeDelegatedLocationUpdatesForContext:completion:": true
  },
  "owner_signatures": {
    "delegatedLocationForContext:completion:": "args=4 return=v",
    "subscribeDelegatedLocationUpdatesForContext:completion:": "args=4 return=v"
  }
}
```

Safe location-fetch selector evidence:

```json
{
  "location_fetch_class": "SPOwnerSessionLocationFetch",
  "location_fetch_responds": {
    "delegatedLocationForContext:completion:": false,
    "subscribeDelegatedLocationUpdatesForContext:completion:": false
  },
  "location_fetch_signatures": {
    "delegatedLocationForContext:completion:": "<nil>",
    "subscribeDelegatedLocationUpdatesForContext:completion:": "<nil>"
  }
}
```

Unsafe proxy-read pattern:

```text
Request to .../delegated-checkpoint/proxy
Private API Helper (com.apple.findmy) disconnected
FindMy Process was force quit
FindMyDylibPlugin Detected DYLIB crash for App FindMy
```

The same pattern happened for `responds-proxy` and `signature-proxy`, because
both checkpoints first read `proxy` / `_proxy`.

Interpretation:

The next useful target is `SPOwnerSession` itself. The owner session exposes the
delegated-location methods with a normal `context, completion` shape. The XPC
proxy should be avoided for now: merely reading it through the current helper
path is enough to crash Find My. The location-fetch object does not implement
the delegated selectors.

Next safer step:

Add owner-only checkpoints that avoid proxy reads completely and test
non-invoking owner behavior first. Good candidates:

1. Capture whether a cached or prior `SPLocationFetchContext` exists without
   creating a new one.
2. Inspect the cached context summary if present.
3. Build the smallest owner-only delegated invocation checkpoint, but do not run
   it automatically; gate it behind a new explicit route after context shape is
   documented.
