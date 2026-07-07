# Remaining SearchParty location data candidates

This note tracks the remaining places where Find My item/device location data may still be available after confirming that `SPBeacon` inventory works but currently observed location result dictionaries are empty.

1. `SPOwnerSessionLocationFetch` internal state before it emits `SPLocationFetchResult`

   We know `receivedUpdatedLocation:` and `setLocationUpdateBlock:` receive `SPLocationFetchResult`, but the result's `_locationsByBeaconIdentifier` is empty. The useful data may exist briefly in the fetch object before the result is constructed, or in another ivar on the fetch/session object that is not exposed by the result.

2. `SPDeviceEventFetchResult.beaconEventByBeaconIdentifier`

   This is the best device-specific path. We saw blocks get installed with signature `v16@?0@"SPDeviceEventFetchResult"8`, but we have not yet captured a delivered result. A non-empty device event payload may include device state/location or a key that joins to another location object.

3. SearchParty daemon/session objects below `SPOwnerSession`

   `SPOwnerSession` is likely a facade. The actual location fetch may happen in lower SearchParty framework objects: fetch sessions, managers, providers, or XPC-backed service clients. Inspect objects retained by `SPOwnerSession` and `SPOwnerSessionLocationFetch`, especially ivars/selectors containing `session`, `fetch`, `manager`, `provider`, `location`, `cache`, `client`, `service`, or `connection`.

4. `CLLocation` / `_cachedLocation` owners

   Dyld/string evidence showed `CLLocation`, `cachedLocation`, and `_cachedLocation` somewhere in the Find My/SearchParty stack. The next useful step is to identify which runtime class owns those fields. That class is likely closer to the actual coordinate-bearing model than `SPBeacon`.

5. `lastOnlineLocationInfo`, as a join clue

   `lastOnlineLocationInfo` does not contain coordinates in the captured objects, only timestamps. It does prove SearchParty has a UUID-keyed dictionary that joins back to beacons. The coordinate dictionary may use the same UUIDs in a sibling cache/result object.

## Working hypothesis

The next useful investigation is recursive runtime inspection from the captured `SPOwnerSessionLocationFetch` and `SPOwnerSession` objects, looking for objects whose class names or fields mention `CLLocation`, `cachedLocation`, `locationResult`, `deviceEvent`, `beaconEvent`, or `locationStore`.
