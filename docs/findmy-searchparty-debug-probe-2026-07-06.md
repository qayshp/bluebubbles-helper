# Find My SearchParty Debug Probe - 2026-07-06

## Purpose

Track 2 added a debug-only SearchParty probe that is separate from the Android-facing refresh routes. The goal is to inspect live `SPOwnerSession` state without replacing blocks, calling async beacon fetch methods, or changing the working People/Devices/Items API behavior.

## Helper Event

The helper now handles:

- `debug-findmy-searchparty`

The event runs on the main thread, installs the passive Find My swizzles, and returns:

- compact swizzle diagnostics
- passive setter/accessor captures
- captured object count
- captured `SPOwnerSession` summaries

The route intentionally does not call `allBeaconsWithCompletion:`. Earlier attempts to use active SearchParty calls or callback replacement caused Devices route timeouts.

## Captured Session Accessors

For each captured `SPOwnerSession`, the probe checks these zero-argument object accessors when available:

- `allBeacons`
- `allBeaconsCache`
- `locationCache`
- `locationSources`
- `clientObservedBeacons`
- `batteryStatusCache`
- `ownerSessionState`
- `beaconsChangedBlock`
- `locationUpdateBlock`
- `deviceEventUpdateBlock`
- `latestLocationsUpdatedBlock`
- `maintainedBeaconsChangedBlock`
- `maintainedUnknownBeaconsChangedBlock`
- `tagSeparationBeaconsChangedBlock`

Only object-returning accessors are invoked. Primitive-returning selectors are skipped to avoid unsafe `performSelector:` behavior inside Find My.

## Test Results

Tested against the rebuilt app on this machine at approximately 2026-07-06 15:10 Pacific.

- Friends refresh returned 8 records.
- Devices refresh returned 13 records.
- Items refresh returned 12 records.
- SearchParty debug returned HTTP 200 in about 0.2 seconds.
- SearchParty debug captured 2 `SPOwnerSession` objects.
- No `Failed to decode BlueBubblesHelper data` error was seen for the debug route.
- No transaction timeout was seen for the debug route.

## SearchParty Finding

The captured sessions exposed useful accessors, but their current caches were empty:

- `locationCache`: dictionary count 0
- `batteryStatusCache`: dictionary count 0
- `clientObservedBeacons`: set count 0
- `locationSources`: set count 0
- `allBeacons`: nil
- `allBeaconsCache`: nil

Passive callback evidence is still present:

- `setLocationUpdateBlock:` receives a block with signature `v16@?0@"SPLocationFetchResult"8`
- `setDeviceEventUpdateBlock:` receives a block with signature `v16@?0@"SPDeviceEventFetchResult"8`
- `SPLocationFetchResult locationsByBeaconIdentifier` was observed, but returned empty dictionaries in this run.

## Current Interpretation

The safe passive session snapshot does not yet expose populated item/device/beacon data outside the visible Find My UI cells. Devices and items are currently still coming from UI table/list extraction, not from populated SearchParty owner-session caches.

The next useful step is to find where Find My's `FMDeviceCellViewModel` and `FMItemCellViewModel` receive their backing models, or to locate the upstream provider/session object that has populated arrays before the UI cells are created.
