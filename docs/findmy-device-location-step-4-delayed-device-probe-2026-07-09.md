# Find My Device Location Step 4 - Delayed Device Probe

## Goal

The normal device refresh route can hang when the immediate UI and FMIP snapshots are empty because it falls through to `SPOwnerSession.allBeaconsWithCompletion:`. That fallback is useful for SearchParty research, but it is the wrong shape for a bounded FMIPCore device-location diagnostic.

## Change

Added a helper action:

- `debug-findmy-devices-delayed`

The action:

1. Installs Find My swizzles.
2. Selects the Devices segment.
3. Starts FMIPManager through the existing Swift bridge when an owner session is available.
4. Captures an immediate `FMIPManager.devices` snapshot.
5. Waits 3 seconds.
6. Captures a delayed `FMIPManager.devices` snapshot.
7. Returns the delayed devices and compact diagnostics without calling `allBeaconsWithCompletion:`.

## Diagnostics Returned

The compact diagnostics now include:

- `delay_seconds`
- `fmip_manager_start`
- `initial_fmip_manager_devices`
- `delayed_fmip_manager_devices`
- `initial_serialized_device_count`
- `delayed_serialized_device_count`
- `swizzle`
- `passive_captures`
- `active_devices_list`

## Crash Hardening

The first live route test reached the delayed snapshot point, then the Find My helper disconnected and Find My relaunched. That timing strongly indicated a crash during FMIP device serialization once `FMIPManager.devices` was populated.

`serializedFMIPManagerDevicesWithDiagnostics:` now catches exceptions per device and reports:

- `serialization_error_count`
- `serialization_errors`

This keeps one unsafe accessor or KVC path from killing the Find My process, while preserving enough class/description/error information to choose the next specific field probe.

## Hardened Test Result

The same delayed route still timed out after the per-device Objective-C exception hardening. The helper disconnected again almost exactly when the delayed snapshot should have read populated `FMIPManager.devices`.

That means the crash likely happens before Objective-C per-device serialization can catch anything. The strongest candidate is the Swift bridge boundary:

- The mangled accessor is `FMIPManager.devices -> [FMIPDevice]`.
- `FMIPDevice` appears to be a Swift value type, not a normal Objective-C object.
- The first bridge declaration treated the accessor as returning `[AnyObject]` and then passed raw device values through an `NSDictionary` into Objective-C.

## Metadata-Only Bridge Attempt

The next attempt keeps the delayed route but changes the Swift bridge to:

- Declare `FMIPManager.devices` as returning `[Any]`.
- Avoid returning raw device values to Objective-C.
- Return only safe Swift-side metadata:
  - `device_count`
  - `device_classes`
  - first 10 `device_summaries`
  - Mirror child labels for those first values

If this survives with a non-zero `device_count`, then the extraction path should stay in Swift and add fields one at a time from the Mirror labels or known `FMIPDevice` accessors. If it still crashes, the problem is likely the `FMIPManager.devices` accessor itself or the manager state/timing, not the Objective-C serializer.

## Metadata-Only Test Result

The metadata-only bridge still crashed at the delayed snapshot point:

- Route request started at `2026-07-09 02:06:19`.
- The Find My helper socket ended at `2026-07-09 02:06:22`.
- The server reported the Find My process as force quit and relaunched it.
- The curl request timed out after 30 seconds with no response body.

Because this version did not return raw devices to Objective-C, the remaining unsafe operations are inside Swift:

- Calling the private `FMIPManager.devices` accessor once the manager has populated devices.
- Mapping the returned values for `type(of:)`.
- Building descriptions or Mirror summaries from the returned values.

The next narrower probe should be count-only: call `FMIPManager.devices` and return only `devices.count`, without touching element types, descriptions, Mirror, or Objective-C serialization.

## Count-Only Bridge Attempt

The next helper changes the Swift snapshot to `snapshot_mode: count_only`.

It still calls the private `FMIPManager.devices` accessor, but after that it only returns:

- `fmip_manager_present`
- `manager_class`
- `device_count`
- `snapshot_mode`

It intentionally leaves `device_classes`, `device_summaries`, and `devices` empty. If this survives, then the crash came from inspecting `FMIPDevice` elements. If it still crashes, the crash is probably caused by calling the `FMIPManager.devices` accessor itself after refresh, or by our Swift declaration not matching the real ABI closely enough.

## Why This Helps

If FMIPCore device coordinates are populated asynchronously after `FMIPManagerRefresh`, this route should show a difference between the immediate and delayed snapshots or capture `setLocation:` / related setter events. If both snapshots stay empty, the next target is the FMIPCore callback path around `FMIPManager: didReceiveDevices` and `FMIPDataManager: updateDevicesLocations`.
