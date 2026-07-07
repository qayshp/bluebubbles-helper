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
   - 2026-07-07 update: I added direct hooks for `SPOwnerSessionLocationFetch receivedUpdatedDeviceEvents:` and wrapped both `setDeviceEventUpdates:` and `setDeviceEventUpdateBlock:` when the block signature mentions `SPDeviceEventFetchResult`.
   - I then changed the explicit generated `SPLocationFetchContext` from `reportDeviceEvents = NO` to `reportDeviceEvents = YES` and reran `/api/v1/icloud/findmy/searchparty/locations/start` followed by `/api/v1/icloud/findmy/searchparty/locations`.
   - The report-device-events probe returned:
     - `context_report_device_events`: `true`
     - `search_identifier_count`: `53`
     - `search_location_source_count`: `12`
     - `last_online_location_info_count`: `10`
     - `completion_count`: `2`
     - `pending_completion_count`: `2`
   - The two completions were:
     - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` -> `nil`
     - `SPOwnerSession.locationsForBeacons:completion:` -> empty `NSDictionary`, count `0`
   - No passive snapshot or completion delivered `SPDeviceEventFetchResult`, and no `beaconEventByBeaconIdentifier` dictionary was observed.

   Current conclusion: the device-event result class is real, and the helper is now positioned to capture it if delivered. Normal refresh, the explicit location probe, and an explicit `reportDeviceEvents = YES` context did not trigger a delivered event result on this Mac.

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
   - 2026-07-07 update: I replaced the broad diagnostics with `lower_layer_class_diagnostics`, a bounded selector/ivar report filtered to XPC, proxy, session, location, beacon, device, event, cache, and fetch terms.
   - The bounded probe returned normally through the HTTP route. It showed:
     - `FMXPCSession` exists and has `_identifier`, `__proxy`, `_serialQueue`, `_serviceDescription`, and `_connection`.
     - `FMXPCSession` exposes `proxy`, `_proxy`, `syncProxyWithErrorHandler:`, `connection`, `serviceDescription`, and `destroyXPCConnection`.
     - `SPOwnerSessionLocationFetch` has `_session: FMXPCSession`, `_proxy: <SPOwnerSessionXPCProtocol>`, `_locationUpdates`, `_deviceEventUpdates`, `_lastContext`, and exposes `receivedUpdatedDeviceEvents:`.
     - `SPBeaconManagerSimpleBeaconUpdateInterface` has `_session: FMXPCSession`, `_proxy: <SPBeaconManagerXPCProtocol>`, `_simpleBeacons`, `_context: SPSimpleBeaconContext`, and exposes `receivedSimpleBeaconUpdates:` plus `startUpdatingSimpleBeaconsWithContext:completion:`.
     - `SPLocationFetchResult` only exposes `_locationsByBeaconIdentifier`, and it remained empty in this run.
     - `SPDeviceEventFetchResult` only exposes `_beaconEventByBeaconIdentifier`, but no instance was delivered in this run.
     - `SPSimpleBeaconContext` exposes `deviceManagerContext` and `fmipItemContextForBeaconUUIDs:` as class methods.
   - I also compacted the active probe and passive SearchParty captures after the first lower-layer attempt exceeded the helper socket payload limit at about 65 KB and caused a JSON decode failure.
   - 2026-07-07 follow-up: I added compact related-object summaries for live `proxy`, `_proxy`, `session`, `connection`, `serviceDescription`, `locationFetch`, `simpleBeaconUpdateInterface`, and `context` objects.
   - The live `SPOwnerSessionLocationFetch.proxy` class is `__NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol`.
   - That proxy exposes several useful SearchParty XPC methods, including:
     - `latestLocationsForIdentifiers:fetchLimit:sources:completion:`
     - `locationForContext:completion:`
     - `delegatedLocationForContext:completion:`
     - `fetchFindMyNetworkStatusForMACAddress:completion:`
     - `beaconsToMaintainWithCompletion:`
     - `allBeaconsWithCompletion:`
   - I invoked `latestLocationsForIdentifiers:fetchLimit:sources:completion:` through the live proxy with:
     - `latest_locations_identifier_count`: `53`
     - `latest_locations_source_count`: `12`
     - `fetchLimit`: `53`
   - That invocation did not call its completion within 25 seconds on this Mac. The probe remained `timed_out` with three pending completions. The two observed completions were still:
     - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` -> `nil`
     - `SPOwnerSession.locationsForBeacons:completion:` -> empty `NSDictionary`, count `0`

   Current conclusion: the lower object path is confirmed as `SPOwnerSessionLocationFetch -> FMXPCSession -> __NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol`. The proxy method `latestLocationsForIdentifiers:fetchLimit:sources:completion:` is the most promising coordinate-bearing candidate found so far, but the naive invocation with all beacon identifiers and all sources did not complete. Next attempts should narrow the identifier/source set or mirror the exact argument classes used by Find My.

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

## 2026-07-07 status

The current lead order remains:

1. Inspect live `_proxy` objects under `SPOwnerSessionLocationFetch` and `SPBeaconManagerSimpleBeaconUpdateInterface`.
2. Look for a specific proxy method that returns location or event payloads for beacon UUIDs.
3. If the proxy path still only returns empty location/event dictionaries, pivot to the older `FMFSession`/`FindMyLocateSession` cached-location stack only for device records that can be joined to a handle-like identifier.

Coordinates have not surfaced yet in SearchParty results on this Mac. The best new fact is that `FMXPCSession` is only a wrapper; the live proxy object is probably the next layer that knows which XPC method returns `SPLocationFetchResult` or `SPDeviceEventFetchResult`.

## Next proxy-specific step

The next best attempt is to retry `latestLocationsForIdentifiers:fetchLimit:sources:completion:` with a smaller, more Find-My-like payload:

- one known-good device/beacon identifier at a time
- the real source collection object copied from `SPLocationFetchContext.searchLocationSources`, not a normalized array when avoidable
- a small `fetchLimit` such as `1`

If that still does not complete, inspect the proxy method `locationForContext:completion:` directly at the XPC proxy layer and compare it with the `SPOwnerSessionLocationFetch locationForContext:completion:` wrapper.
