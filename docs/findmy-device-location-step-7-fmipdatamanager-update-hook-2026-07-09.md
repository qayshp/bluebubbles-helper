# Find My device location step 7 - FMIPDataManager update hook

## Goal

Narrow the callback watcher after the broad FMIP/SiriFindMy watcher crashed Find My.

## Change

The normal `installFindMySwizzles` path no longer installs the broad FMIP callback watcher. That matters because general Find My probing should not implicitly hook every FMIP/SiriFindMy method that happens to match a broad term like `location` or `device`.

The debug action behind:

```text
POST /api/v1/icloud/findmy/devices/debug/fmip-callbacks
```

now installs only:

```text
FMIPCore.FMIPDataManager / _TtC8FMIPCore15FMIPDataManager / FMIPDataManager
selector contains updateDevicesLocations
```

It still applies the same safety filter:

- method must be Objective-C runtime visible
- 0 to 3 explicit arguments
- each explicit argument must be object or block encoded

## Why this target

`updateDevicesLocations` is the most semantically direct method name found so far for the device-location path. It avoids calling the crash-prone `FMIPManager.devices` accessor directly and should fire only when FMIPCore is applying location updates to known devices.

## Build

Built successfully on 2026-07-09 with:

```text
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace 'FindMy/MacOS-16+/BlueBubblesHelper.xcworkspace' -scheme 'BlueBubblesHelper DyLib' -configuration Release -derivedDataPath 'FindMy/MacOS-16+/build' ENABLE_USER_SCRIPT_SANDBOXING=NO build
```

## Next validation

Install this helper dylib into `bluebubbles-server`, restart/reinject Find My, and call the same debug route. Useful outcomes:

- route returns and `fmip_callbacks.callback_count` increases: inspect callback arguments for `CLLocation`, FMIP location fields, or device objects
- route returns with zero callbacks: move to `FMIPManager.didReceiveDevices` or SiriFindMy `FMIPSyncDeviceProvider`
- Find My crashes again: stop swizzling `updateDevicesLocations` and switch to runtime/provider inspection
