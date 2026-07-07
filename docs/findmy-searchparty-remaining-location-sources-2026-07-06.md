# Remaining SearchParty location data candidates

This note tracks the remaining places where Find My item/device location data may still be available after confirming that `SPBeacon` inventory works but currently observed location result dictionaries are empty.

1. `SPOwnerSessionLocationFetch` internal state before it emits `SPLocationFetchResult`

   We know `receivedUpdatedLocation:` and `setLocationUpdateBlock:` receive `SPLocationFetchResult`, but the result's `_locationsByBeaconIdentifier` is empty. The useful data may exist briefly in the fetch object before the result is constructed, or in another ivar on the fetch/session object that is not exposed by the result.

   Follow-up investigation:

   - The live `SPOwnerSessionLocationFetch` object exposes these relevant methods:
     - `locationForContext:completion:`
     - `subscribeAndFetchLocationForContext:completion:`
     - `receivedUpdatedLocation:`
     - `receivedUpdatedDeviceEvents:`
     - `locationUpdates`
     - `deviceEventUpdates`
     - `session`
     - `proxy`
   - Its relevant ivars are:
     - `_session`: typed as `FMXPCSession`
     - `_proxy`: typed as `<SPOwnerSessionXPCProtocol>`
     - `_locationUpdates`: block
     - `_deviceEventUpdates`: block
     - `_retryCount`: `SPRetryCount`
     - `_lastContext`: `SPLocationFetchContext`
   - In the successful probe before expanding diagnostics, `_session` was populated as `FMXPCSession`, `_lastContext` was populated as `SPLocationFetchContext`, and both update blocks were installed.
   - The emitted `SPLocationFetchResult` still had `_locationsByBeaconIdentifier` as `__NSDictionary0`, count `0`.

   Current conclusion: this object is still the most useful internal object. It does not itself expose coordinates in the current summary, but it points to the lower XPC session/proxy layer that likely owns the actual fetch.

2. `SPDeviceEventFetchResult.beaconEventByBeaconIdentifier`

   This is the best device-specific path. We saw blocks get installed with signature `v16@?0@"SPDeviceEventFetchResult"8`, but we have not yet captured a delivered result. A non-empty device event payload may include device state/location or a key that joins to another location object.

   Follow-up investigation:

   - The Android-facing route pass returned:
     - friends: `8`
     - devices: `13`
     - items: `0`
   - During that pass, Find My installed device-event blocks on both `SPOwnerSessionLocationFetch` and `SPOwnerSession`.
   - The block signature remained `v16@?0@"SPDeviceEventFetchResult"8`.
   - No `beaconEventByBeaconIdentifier` accessor snapshot appeared.
   - No delivered `SPDeviceEventFetchResult` payload was captured.

   Current conclusion: the device-event result class is real, but normal refresh and the explicit location probe did not trigger it. We need either a more specific device-event trigger or a lower-level hook on `receivedUpdatedDeviceEvents:`.

3. SearchParty daemon/session objects below `SPOwnerSession`

   `SPOwnerSession` is likely a facade. The actual location fetch may happen in lower SearchParty framework objects: fetch sessions, managers, providers, or XPC-backed service clients. Inspect objects retained by `SPOwnerSession` and `SPOwnerSessionLocationFetch`, especially ivars/selectors containing `session`, `fetch`, `manager`, `provider`, `location`, `cache`, `client`, `service`, or `connection`.

   Follow-up investigation:

   - The retained `SPOwnerSessionLocationFetch` points at an `FMXPCSession` through `_session`.
   - The retained `SPBeaconManagerSimpleBeaconUpdateInterface` also points at `FMXPCSession` through `_session`.
   - The simple-beacon interface exposes:
     - `_simpleBeacons`: `NSArray`
     - `_session`: `FMXPCSession`
     - `_proxy`: `<SPBeaconManagerXPCProtocol>`
     - `_collectionDifferenceBlock`
     - `_serialQueue`
     - `_context`: `SPSimpleBeaconContext`
   - The explicit simple-beacon completion either returned nil/empty or did not produce coordinate-bearing data.
   - I added class-level diagnostics for `FMXPCSession`, `SPBeaconManagerSimpleBeaconUpdateInterface`, `SPSimpleBeaconContext`, `FindMyLocateSession`, and `FMFSession`. The helper built successfully with Xcode 26.3 after disabling Xcode user script sandboxing for the CocoaPods manifest phase.
   - Returning the broad expanded class diagnostics through the existing location probe made the client call hang, likely because the payload became too large. The server stayed healthy afterward.

   Current conclusion: the lower object path is `SPOwnerSessionLocationFetch -> FMXPCSession/proxy` and `SPBeaconManagerSimpleBeaconUpdateInterface -> FMXPCSession/proxy`. The next instrumentation should return a deliberately tiny allowlist for `FMXPCSession` and proxy-related selectors instead of dumping full method lists.

4. `CLLocation` / `_cachedLocation` owners

   Dyld/string evidence showed `CLLocation`, `cachedLocation`, and `_cachedLocation` somewhere in the Find My/SearchParty stack. The next useful step is to identify which runtime class owns those fields. That class is likely closer to the actual coordinate-bearing model than `SPBeacon`.

   Follow-up investigation:

   - Static evidence in the dyld-cache strings points strongly at the older people/location stack:
     - `FindMyLocateSession cachedLocationForHandle:`
     - `FindMyLocateSession cachedLocationForHandle:includeAddress:`
     - `FMFSession cachedLocationForHandle:`
     - `FMFSession cachedLocationForHandleByHandle`
     - `FMLLocation`
   - The same string set contains generic ObjC properties like `T@"CLLocation",&,N,V_cachedLocation`, but the named Find My hits are handle/person oriented.
   - I added `FindMyLocateSession` and `FMFSession` to runtime class diagnostics, but the broad diagnostics response needs to be trimmed before it is useful through the route.

   Current conclusion: `cachedLocation` is probably still relevant for People/FMF/FindMyLocate, but the current item/device SearchParty path is not obviously using those classes. For item/device work, this is now a secondary path unless we find `FMLHandle`-like handles for beacons/devices.

5. `lastOnlineLocationInfo`, as a join clue

   `lastOnlineLocationInfo` does not contain coordinates in the captured objects, only timestamps. It does prove SearchParty has a UUID-keyed dictionary that joins back to beacons. The coordinate dictionary may use the same UUIDs in a sibling cache/result object.

   Follow-up investigation:

   - The retained real `SPLocationFetchContext` still had `_lastOnlineLocationInfo` as a UUID-keyed dictionary, count `10`.
   - The explicit generated context copied that dictionary forward while adding 53 beacon identifiers and 12 search location sources.
   - The helper matched 5 last-online entries back to `SPBeacon` records.
   - The matched `SPLastOnlineLocationInfo` objects exposed `_timestamp`, `_updatedOn`, and `timestamp`.
   - No `CLLocation`, latitude, longitude, accuracy, address, or coordinate-bearing child object surfaced.

   Current conclusion: this remains useful as a join map and recency signal only. It is not hiding coordinates in the inspected object surface.

## Working hypothesis

The next useful investigation is recursive runtime inspection from the captured `SPOwnerSessionLocationFetch` and `SPOwnerSession` objects, looking for objects whose class names or fields mention `CLLocation`, `cachedLocation`, `locationResult`, `deviceEvent`, `beaconEvent`, or `locationStore`.

## Next narrow step

Replace the broad class-diagnostics payload with a small lower-layer probe that only reports:

- `FMXPCSession` ivars and selectors matching `proxy`, `session`, `connection`, `service`, `location`, `beacon`, `device`, and `event`
- the concrete runtime class of `_proxy` when it is non-nil
- whether `receivedUpdatedDeviceEvents:` is ever called, with a bounded summary of its argument
- whether `FindMyLocateSession` or `FMFSession` runtime classes are available, without dumping their full method lists
