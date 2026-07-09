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

## Why This Helps

If FMIPCore device coordinates are populated asynchronously after `FMIPManagerRefresh`, this route should show a difference between the immediate and delayed snapshots or capture `setLocation:` / related setter events. If both snapshots stay empty, the next target is the FMIPCore callback path around `FMIPManager: didReceiveDevices` and `FMIPDataManager: updateDevicesLocations`.
