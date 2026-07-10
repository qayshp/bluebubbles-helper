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

## Runtime result

Installed helper checksum in the server repo:

```text
3d23119a7bdb365ac6ea013b7f757de3
```

Server route:

```text
POST /api/v1/icloud/findmy/devices/debug/fmip-datamanager
```

Observed result:

- Request started at `2026-07-10 01:10:06`.
- The Find My helper socket ended at `2026-07-10 01:10:11`, about when the delayed `FMIPDataManager` snapshot should have run.
- BlueBubbles marked the Find My process as force quit and relaunched it.
- Curl timed out after 90 seconds with HTTP `000` and no response body.

Interpretation:

- The route reached Find My and selected the Devices path, but the helper crashed before it could send diagnostics.
- The crash timing implicates the Swift `Mirror` snapshot over the retained manager's `dataManager` or over one of the selected `FMIPDataManager` ivar values.
- This does not rule out `FMIPDataManager` as the source of device locations. It only rules out this broad Swift `Mirror` value-summary shape as safe.

Next step:

- Replace the value-summary snapshot with a narrower Objective-C runtime metadata probe.
- Keep the retained manager path, but report only class names, ivar names, and whether `dataManager` can be reached.
- Do not summarize `devices`, `crowdSourcedLocations`, or other `FMIPDataManager` values until the metadata-only probe proves the object can be touched without crashing.

## Metadata-only follow-up

Implemented a narrower snapshot mode:

```text
objc_runtime_ivar_metadata_retained_fmip_manager_data_manager
```

This build still starts and retains `FMIPManager`, but the snapshot now avoids broad Swift value traversal:

- It does not use Swift `Mirror` to summarize `FMIPDataManager` field values.
- It does not call `FMIPManager.devices`.
- It uses Objective-C runtime metadata to list manager ivars and data-manager ivars.
- It uses `object_getIvar(manager, dataManager)` only for the single `dataManager` reference.
- It reports target field metadata for `devices`, `crowdSourcedLocations`, `crowdSourcedOriginalLocations`, `deviceConnectedStates`, `safeLocations`, `safeLocationsMapping`, `owner`, and `familyMembers`.

Build result:

- `xcodebuild` completed successfully on `2026-07-10`.

Expected interpretation:

- If this route returns, `FMIPManager.dataManager` is reachable and the next step is one-field-at-a-time reads, starting with metadata or count-only access to `crowdSourcedLocations` before `devices`.
- If it still crashes, even `object_getIvar(manager, dataManager)` is too risky for the retained manager path, and the next step should be locating an app-owned manager/data-manager object through the Find My object graph rather than creating our own `FMIPManager`.
