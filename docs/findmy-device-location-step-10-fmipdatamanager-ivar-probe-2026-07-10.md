# Find My device location step 10 - FMIPDataManager ivar probe

## Goal

Get closer to device coordinates without using the crash-prone `FMIPManager.devices` accessor and without swizzling FMIPCore callbacks.

## Reasoning

Previous results:

- `FMIPManager.devices.count` crashed Find My.
- Broad FMIPCore/SiriFindMy callback swizzling crashed Find My.
- Scoped `FMIPDataManager.updateDevicesLocations` swizzling crashed Find My.
- Scoped `FMIPManager.didReceiveDevices` swizzling crashed Find My.
- Bounded provider-runtime inspection worked and showed:
  - `FMIPCore.FMIPManager` is available.
  - `FMIPCore.FMIPDataManager` is available.
  - SiriFindMy provider classes are not available in the Find My process.
  - `FMIPDataManager` exposes promising ivars including `devices`, `crowdSourcedLocations`, `crowdSourcedOriginalLocations`, `deviceConnectedStates`, `safeLocations`, and `safeLocationsMapping`.

The FMIPCore runtime ivar encodings for Swift classes are empty, so reading these fields with Objective-C `object_getIvar` is risky. Some fields are likely Swift value storage such as arrays or dictionaries, and treating those as Objective-C object ivars can crash.

This probe therefore uses Swift `Mirror` against the retained `FMIPManager` and its `dataManager` field. It does not call `FMIPManager.devices`.

## Helper action

Added:

```text
debug-findmy-devices-fmip-datamanager
```

The action:

1. Selects the Devices view.
2. Starts/refreshes `FMIPManager` through the existing Swift bridge.
3. Takes an immediate Swift `Mirror` snapshot of the retained manager's `dataManager`.
4. Waits 5 seconds.
5. Takes a delayed Swift `Mirror` snapshot.
6. Returns only bounded Foundation-safe summaries.

## Fields inspected

From `FMIPDataManager`:

- `devices`
- `crowdSourcedLocations`
- `crowdSourcedOriginalLocations`
- `deviceConnectedStates`
- `safeLocations`
- `safeLocationsMapping`
- `owner`
- `familyMembers`

For each field, the helper records:

- Swift type
- display style
- count when visible through `Mirror` or Foundation bridging
- bounded samples
- sampled child labels
- direct or child `CLLocation` signals if present

## Expected interpretation

- If `crowdSourcedLocations` or `devices` contains location-bearing samples, add a second narrow serializer for those exact value types.
- If these fields are empty but `deviceConnectedStates` or `safeLocations` are populated, inspect how they key back to device identifiers.
- If starting FMIPManager or mirroring `dataManager` crashes, the next step is to capture the app-created manager instance instead of creating our own.
