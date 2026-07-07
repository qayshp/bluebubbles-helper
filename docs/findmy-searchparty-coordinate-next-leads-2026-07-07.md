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
