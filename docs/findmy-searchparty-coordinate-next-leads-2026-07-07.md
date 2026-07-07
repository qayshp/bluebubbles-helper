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
