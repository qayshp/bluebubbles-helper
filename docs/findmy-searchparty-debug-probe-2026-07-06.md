# Find My SearchParty Debug Probe - 2026-07-06

## Purpose

Track 2 added debug-only SearchParty probes that are separate from the Android-facing refresh routes. The goal is to inspect live `SPOwnerSession` state without replacing Find My blocks or changing the working People/Devices/Items API behavior.

## Helper Event

The helper now handles the passive snapshot event:

- `debug-findmy-searchparty`

The event runs on the main thread, installs the passive Find My swizzles, and returns:

- compact swizzle diagnostics
- passive setter/accessor captures
- captured object count
- captured `SPOwnerSession` summaries

The helper also handles the active async beacon probe events:

- `debug-findmy-searchparty-beacons-start`
- `debug-findmy-searchparty-beacons`

The start event captures a live `SPOwnerSession`, calls `allBeaconsWithCompletion:`, and immediately returns a probe status. The status event polls the latest saved probe result after the async completion runs.

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

## How To Get The Beacon Set

1. Install the Find My swizzles on the main thread.
2. Read captured owner sessions from `capturedSearchPartyOwnerSessions`.
3. Pick a captured `SPOwnerSession` that responds to `allBeaconsWithCompletion:`.
4. Invoke `allBeaconsWithCompletion:` using `NSInvocation` and a retained completion block.
5. In the completion block, handle both array and set return values. On this machine the completion result was an `__NSSetI`, not an `NSArray`.
6. Convert the set to an array with `[(NSSet *)beaconsResult allObjects]` before serializing.

The relevant conversion is:

```objc
NSArray *beacons = @[];
if ([beaconsResult isKindOfClass:[NSArray class]]) {
    beacons = beaconsResult;
} else if ([beaconsResult isKindOfClass:[NSSet class]]) {
    beacons = [(NSSet *)beaconsResult allObjects];
}
```

The synchronous `allBeacons` getter was still nil in the passive snapshot. The useful data came from the async `allBeaconsWithCompletion:` callback.

## Test Results

Tested against the rebuilt app on this machine at approximately 2026-07-06 15:10 Pacific.

- Friends refresh returned 8 records.
- Devices refresh returned 13 records.
- Items refresh returned 12 records.
- SearchParty debug returned HTTP 200 in about 0.2 seconds.
- SearchParty debug captured 2 `SPOwnerSession` objects.
- SearchParty beacon probe completed successfully.
- The beacon probe completion result class was `__NSSetI`.
- The beacon probe returned 53 `SPBeacon` records and serialized 53 records.
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

## Beacon Examples

The async beacon set included named item and device records such as:

- `Qays’s Subaru Keys (apple)`
- `Belltown Court Keys (donut)`
- `Qays's Ridge Wallet`
- `Qays’s iPhone`
- `qhp-mbp-14-6`
- `Qays’s Toyota Keys (banana)`
- `Pink Wallet`
- `DJ's wallet (flower)`
- `Qays’s House Keys`
- `Qays's Purple MagSafe Wallet`

Some Apple devices appear in this API as `SPBeacon` records too. The set is not limited to AirTag-style items.

## Current Interpretation

The passive session snapshot does not expose populated item/device/beacon data outside the visible Find My UI cells because the synchronous caches are empty or nil. The async `allBeaconsWithCompletion:` method does expose a populated `NSSet` of `SPBeacon` objects.

Devices and items are still served to Android from UI table/list extraction. The SearchParty beacon probe is a debug route and should be treated as the next source to map into a production items/devices provider after the `SPBeacon` fields are classified.
