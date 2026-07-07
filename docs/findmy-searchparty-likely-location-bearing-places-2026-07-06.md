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

3. `SPOwnerSessionLocationFetch._locationUpdates`
This is a block field, not an array, but it is very promising. The app installs location update blocks that receive `SPLocationFetchResult`. If coordinates are being delivered, they may be inside the result object passed through this path, not exposed by the single `locationsByBeaconIdentifier` accessor we tried.

4. `SPOwnerSession.setLocationUpdateBlock:`
Also very promising. We captured its block signature as:

```text
v16@?0@"SPLocationFetchResult"8
```

That confirms Find My expects `SPLocationFetchResult` update payloads.

5. `SPOwnerSessionLocationFetch._deviceEventUpdates`
For devices specifically, this may matter. It receives:

```text
SPDeviceEventFetchResult
```

Device location might be coupled to device event updates rather than the item/beacon location result path.

6. `SPBeacon.locationProviders`
This is probably not location data itself. It looked more like metadata telling SearchParty where/how to search for a beacon. Still useful because we copied it into `searchLocationSources`.

7. `SPLocationFetchContext.searchLocationSources`
Probably not locations. It is a 12-string source/filter array used to request locations. Important for making the fetch work, but unlikely to contain coordinates.

8. `SPLocationFetchContext.lastOnlineLocationInfo`
We inspected this pretty deeply. It mapped beacon IDs to `SPLastOnlineLocationInfo`, but the fields we saw were timestamp-shaped only: `_timestamp`, `_updatedOn`, `timestamp`. No coordinate/CLLocation/lat/long surfaced.

9. `SPBeacon` / `allBeacons`
This is inventory/identity, not location. It has names, IDs, model/role-ish metadata, battery-ish metadata, etc., but not coordinates in the samples.

The next thing I’d inspect is the full ivar/method surface of `SPLocationFetchResult` and `SPDeviceEventFetchResult`, especially any fields named like `locations`, `locationCache`, `cachedLocation`, `locationInfo`, `results`, `devices`, `beacons`, or `events`. The dyld strings also showed `cachedLocation` / `_cachedLocation` and `CLLocation` references somewhere in Find My-related code, so finding which runtime class owns those fields is probably the next useful jump.
