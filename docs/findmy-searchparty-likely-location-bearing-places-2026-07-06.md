# Likely SearchParty location-bearing places, in order

Yes. The most likely location-bearing places, in order:

1. `SPLocationFetchResult.locationsByBeaconIdentifier`
This is still the best candidate. It sounds exactly like the map we need: beacon identifier -> location object/result. We have observed the selector, but it returned an empty dictionary in the current runs.

   Follow-up investigation:

   - `receivedUpdatedLocation:` receives an `SPLocationFetchResult`.
   - `SPOwnerSession.setLocationUpdateBlock:` also receives an `SPLocationFetchResult`.
   - Deep runtime inspection of that object found one relevant ivar:
     - `_locationsByBeaconIdentifier`
     - type: `NSDictionary`
     - value: empty dictionary, count `0`
   - Calling/accessing `locationsByBeaconIdentifier` returns the same empty dictionary.
   - No other useful location/result/cache/beacon dictionary surfaced from the object. The only extra method that appeared in the filtered probe was inherited NSObject noise: `_crComputeDeviceType`.

   Current conclusion: this is structurally correct but currently empty on this Mac. `SPLocationFetchResult` does not appear to be hiding another populated location array or map in the captured update result; the object's relevant storage is exactly `_locationsByBeaconIdentifier`.

2. `SPOwnerSession.locationCache`
This is the next best field. It was present on `SPOwnerSession`, but observed as an empty dictionary. If Find My populates device/item locations asynchronously, this may become useful after the right refresh/update path fires.

   Follow-up investigation:

   - Before the explicit SearchParty location probe, both captured `SPOwnerSession` instances had `locationCache` as `__NSDictionary0`, count `0`, keys `[]`.
   - The explicit location probe called `startRefreshing`, populated one owner session's `allBeacons` / `allBeaconsCache` to 53 `SPBeacon` records, and built a context with 53 identifiers and 12 location sources.
   - After the probe, both captured owner sessions still had `locationCache` as `__NSDictionary0`, count `0`, keys `[]`.
   - Passive setter capture observed `SPOwnerSession setLocationCache:` fire, but the value passed to it was also `__NSDictionary0`.
   - `locationSources` and `clientObservedBeacons` also stayed empty.

   Current conclusion: `locationCache` is a real cache field and setter target, but in this run Find My explicitly set it to an empty dictionary. The cache did not populate even when `allBeacons` populated and `startRefreshing` ran, so it is not currently a source of item/device coordinates on this Mac.

3. `SPOwnerSessionLocationFetch._locationUpdates`
This is a block field, not an array, but it is very promising. The app installs location update blocks that receive `SPLocationFetchResult`. If coordinates are being delivered, they may be inside the result object passed through this path, not exposed by the single `locationsByBeaconIdentifier` accessor we tried.

   Follow-up investigation:

   - `SPOwnerSessionLocationFetch` installed both `setLocationUpdates:` and `setLocationUpdateBlock:` blocks.
   - The block installed on `SPOwnerSessionLocationFetch` had signature `v16@?0@8`, while the corresponding `SPOwnerSession` block had the more specific `v16@?0@"SPLocationFetchResult"8`.
   - The helper observed `receivedUpdatedLocation:` on `SPOwnerSessionLocationFetch` with an `SPLocationFetchResult` argument.
   - Each observed result still led back to `locationsByBeaconIdentifier -> __NSDictionary0`, count `0`.

   Current conclusion: `_locationUpdates` is the live callback path for location updates, but the payload currently carries an empty `SPLocationFetchResult` on this Mac. It confirms the delivery path, not usable coordinates.

4. `SPOwnerSession.setLocationUpdateBlock:`
Also very promising. We captured its block signature as:

```text
v16@?0@"SPLocationFetchResult"8
```

That confirms Find My expects `SPLocationFetchResult` update payloads.

   Follow-up investigation:

   - The typed `SPOwnerSession.setLocationUpdateBlock:` path fired during the latest run.
   - Captured payload class: `SPLocationFetchResult`.
   - Deep diagnostics found `_locationsByBeaconIdentifier` on that result object, but the dictionary was empty.
   - Recent accessor captures repeatedly showed `locationsByBeaconIdentifier -> __NSDictionary0`, count `0`.

   Current conclusion: this is still the cleanest callback surface for item/device location payloads. The problem is not finding the callback; the problem is that Find My is currently delivering empty location-result maps through it.

5. `SPOwnerSessionLocationFetch._deviceEventUpdates`
For devices specifically, this may matter. It receives:

```text
SPDeviceEventFetchResult
```

Device location might be coupled to device event updates rather than the item/beacon location result path.

   Follow-up investigation:

   - The helper observed `setDeviceEventUpdates:` and `setDeviceEventUpdateBlock:` on `SPOwnerSessionLocationFetch`.
   - The helper also observed `setDeviceEventUpdateBlock:` on `SPOwnerSession`.
   - All of those blocks had signature `v16@?0@"SPDeviceEventFetchResult"8`.
   - After running the Android-facing friend/device/item refresh routes and the SearchParty location probe, no `beaconEventByBeaconIdentifier` accessor snapshots appeared.
   - The route did not capture a delivered `SPDeviceEventFetchResult` payload, only the block installations.

   Current conclusion: `_deviceEventUpdates` is real and device-specific, but this run did not produce a device-event result. It remains a good next hook, but we still need a trigger that makes Find My invoke the block with a non-empty `SPDeviceEventFetchResult`.

6. `SPBeacon.locationProviders`
This is probably not location data itself. It looked more like metadata telling SearchParty where/how to search for a beacon. Still useful because we copied it into `searchLocationSources`.

   Follow-up investigation:

   - The explicit location probe reads `locationProviders` from each `SPBeacon` as a fallback way to build `SPLocationFetchContext.searchLocationSources`.
   - In the latest run, the probe found a retained real `SPLocationFetchContext`, so it reused that context's existing `searchLocationSources` instead of relying only on per-beacon fallback providers.
   - The resulting context had 12 search location sources.
   - No coordinate-like value came from `locationProviders`; it functioned as request/source metadata.

   Current conclusion: `locationProviders` helps construct a plausible location fetch context, but it is not itself a location-bearing field.

7. `SPLocationFetchContext.searchLocationSources`
Probably not locations. It is a 12-string source/filter array used to request locations. Important for making the fetch work, but unlikely to contain coordinates.

   Follow-up investigation:

   - The retained real `SPLocationFetchContext` had `_searchLocationSources` as `Swift.__SwiftDeferredNSArray`, count `12`.
   - The generated probe context copied those 12 sources forward.
   - The same context also had `_searchTypes` as `Swift.__SwiftDeferredNSArray`, count `6`.
   - Using those real context values let the explicit probe build a stronger request with 53 beacon identifiers and 12 search location sources.
   - The fetch still timed out with only empty/nil completion results.

   Current conclusion: `searchLocationSources` is important request configuration. It does not contain coordinates, and copying it into the request was not enough to make `SPLocationFetchResult` populate.

8. `SPLocationFetchContext.lastOnlineLocationInfo`
We inspected this pretty deeply. It mapped beacon IDs to `SPLastOnlineLocationInfo`, but the fields we saw were timestamp-shaped only: `_timestamp`, `_updatedOn`, `timestamp`. No coordinate/CLLocation/lat/long surfaced.

   Follow-up investigation:

   - The retained real `SPLocationFetchContext` had `_lastOnlineLocationInfo` as a UUID-keyed Swift deferred dictionary, count `10`.
   - The explicit probe matched 5 of those last-online entries back to loaded `SPBeacon` records by identifier candidates.
   - Each inspected `SPLastOnlineLocationInfo` exposed timestamp-style fields/accessors only:
     - `_timestamp`
     - `_updatedOn`
     - `timestamp`
   - No `CLLocation`, latitude, longitude, horizontal accuracy, address, or coordinate-bearing child object surfaced.

   Current conclusion: `lastOnlineLocationInfo` is useful for joining some beacons to last-seen timestamps, but it is not the coordinate source.

9. `SPBeacon` / `allBeacons`
This is inventory/identity, not location. It has names, IDs, model/role-ish metadata, battery-ish metadata, etc., but not coordinates in the samples.

   Follow-up investigation:

   - `SPOwnerSession allBeaconsWithCompletion:` returned a populated `__NSSetI` of 53 `SPBeacon` records.
   - After the explicit probe and Android-facing refreshes, two captured owner sessions had `allBeacons` and `allBeaconsCache` populated with the same 53-record `SPBeacon` set.
   - The same sessions still had empty `locationCache`, empty `locationSources`, empty `clientObservedBeacons`, and empty `batteryStatusCache`.
   - The `SPBeacon` records are enough to identify devices/items, including Apple devices and item-style beacons, but not enough to locate them.

   Current conclusion: `SPBeacon` / `allBeacons` is the best complete inventory source we have. It needs to be joined with a separate populated location result, most likely by beacon UUID or stable identifier.

After this pass, the clearest next target is not another UI path or the raw beacon inventory. It is finding the trigger or owning object that produces a non-empty `SPLocationFetchResult.locationsByBeaconIdentifier` or `SPDeviceEventFetchResult.beaconEventByBeaconIdentifier`. The result/callback classes are identified; the missing piece is the upstream SearchParty state that makes those result dictionaries populate.
