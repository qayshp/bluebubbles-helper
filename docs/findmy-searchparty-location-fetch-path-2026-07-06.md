# Find My SearchParty location fetch path, 2026-07-06

This note documents the next internal SearchParty attempt after the earlier beacon and last-online-location probes.

We are intentionally moving away from UI-driven attempts for device and item support. UI selection, list scrolling, and visible-cell inspection are useful for proving that data exists, but they are incomplete for a large Find My account and fragile over VNC. The current direction is to reuse Find My's own SearchParty objects and XPC-backed update path.

## Added instrumentation

In `BlueBubblesHelper.m`, the helper now:

- Retains the most recent live `SPOwnerSessionLocationFetch` object observed from Find My's own `locationForContext:completion:` and `subscribeAndFetchLocationForContext:completion:` calls.
- Retains the most recent live `SPLocationFetchContext` passed to those calls.
- Prefers those captured objects in the explicit `/api/v1/icloud/findmy/searchparty/locations/start` probe instead of only synthesizing a context from `SPOwnerSession`.
- Captures `SPOwnerSessionLocationFetch receivedUpdatedLocation:` and follows `SPLocationFetchResult locationsByBeaconIdentifier`.
- Captures collection summaries for `NSArray` and `NSSet` results so beacon/simple-beacon payloads show counts and element summaries.
- Attempts `SPBeaconManagerSimpleBeaconUpdateInterface startUpdatingSimpleBeaconsWithContext:completion:` if a simple-beacon interface and context are available.

## API check

With the rebuilt dylib loaded through the repo-built BlueBubbles app:

- `GET /api/v1/icloud/findmy/friends` returned 8 records.
- `GET /api/v1/icloud/findmy/devices` returned `null`.
- `GET /api/v1/icloud/findmy/items` returned `null`.

The server still logs the current Sequoia-or-later guard for the public devices/items routes:

- `Cannot fetch FindMy devices on macOS Sequoia or later.`
- `Cannot fetch FindMy items on macOS Sequoia or later.`

## Location fetch evidence

The explicit location probe now starts with:

- `captured_owner_session_count = 2`
- `pending_completion_count = 4`
- `context_search_identifier_count = 53`
- `context_search_location_source_count = 12`
- captured fetch object class: `SPOwnerSessionLocationFetch`
- captured context class: `SPLocationFetchContext`

The retained `SPOwnerSessionLocationFetch` exposed useful fields:

- `_session`: `FMXPCSession`
- `_proxy`: `<nil>`
- `_locationUpdates`: `__NSMallocBlock__`
- `_deviceEventUpdates`: `__NSMallocBlock__`
- `_locationFetchSessionInvalidationBlock`: `<nil>`
- `_retryCount`: `SPRetryCount`
- `_lastContext`: `SPLocationFetchContext`

Related setter captures showed these block signatures:

- `setLocationUpdates:` on `SPOwnerSessionLocationFetch`: `v16@?0@8`
- `setLocationUpdateBlock:` on `SPOwnerSessionLocationFetch`: `v16@?0@8`
- `setLocationUpdateBlock:` on `SPOwnerSession`: `v16@?0@"SPLocationFetchResult"8`
- `setDeviceEventUpdates:` on `SPOwnerSessionLocationFetch`: `v16@?0@"SPDeviceEventFetchResult"8`
- `setDeviceEventUpdateBlock:` on `SPOwnerSessionLocationFetch`: `v16@?0@"SPDeviceEventFetchResult"8`
- `setDeviceEventUpdateBlock:` on `SPOwnerSession`: `v16@?0@"SPDeviceEventFetchResult"8`

The retained `SPLocationFetchContext` exposed useful fields:

- `_cachePolicy`: `foregroundRefresh`
- `_searchIdentifiers`: empty array before the explicit probe fills it
- `_searchTypes`: 6 string entries
- `_searchLocationSources`: 12 string entries
- `_lastOnlineLocationInfo`: 10 keyed entries
- `_bundleIdentifier`: `<nil>`

## Probe results

The probe invoked:

- `SPOwnerSessionLocationFetch locationForContext:completion:`
- `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
- `SPOwnerSession locationsForBeacons:completion:`
- `SPBeaconManagerSimpleBeaconUpdateInterface startUpdatingSimpleBeaconsWithContext:completion:`

Observed completions:

- `SPOwnerSession.locationsForBeacons:completion:` completed with an empty dictionary.
- `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` completed with `nil` because the owner session did not expose `simpleBeaconUpdateInterface` in this run.
- `SPOwnerSessionLocationFetch.locationForContext:completion:` and `subscribeAndFetchLocationForContext:completion:` did not call their completions within the probe timeout, but the passive `receivedUpdatedLocation:` hook fired.

The passive update path showed:

- `receivedUpdatedLocation:` receives `SPLocationFetchResult`.
- `setLocationUpdateBlock:` also receives `SPLocationFetchResult`.
- `SPLocationFetchResult locationsByBeaconIdentifier` is currently an empty `NSDictionary` in both paths.

That means the app is receiving location update result objects, but the public-looking result dictionary we found is not populated for this local run.

## Last-online data remains separate

The retained `SPLocationFetchContext` still contains `_lastOnlineLocationInfo`. That dictionary matches 5 beacons by identifier in the explicit probe. This remains the strongest internal evidence tying SearchParty beacons to Find My state, but the `SPLastOnlineLocationInfo` objects we inspected expose timestamp-style fields rather than coordinates.

Current interpretation:

- `allBeaconsWithCompletion:` is the best source for the complete device/item beacon set.
- `SPLocationFetchContext._lastOnlineLocationInfo` maps some beacon identifiers to last-online metadata.
- `SPLocationFetchResult.locationsByBeaconIdentifier` is the likely live-location map, but it is empty on this Mac for the current call/context.
- The next useful internals step is to inspect `SPLocationFetchResult` ivars and block argument signatures more deeply, especially the `_locationUpdates` and `_deviceEventUpdates` blocks retained by `SPOwnerSessionLocationFetch`, to find whether the populated payload is delivered in another argument or nested result field.
