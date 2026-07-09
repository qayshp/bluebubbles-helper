# Find My device location step 2 - FMIPCore update-path probe - 2026-07-09

## Goal

Try the second recommended Device-location probe:

> If direct field reads are incomplete, instrument the FMIPCore update path. The
> best target is the path behind `FMIPDataManager: updateDevicesLocations device
> ... location ... crowdsourcedLocation ...`, followed by the `FMIPManager:
> didReceiveDevices` flow.

## Implementation

The static strings identify the update flow, but the Swift-native
`FMIPDataManager.updateDevicesLocations` implementation is not directly exposed
as an Objective-C selector in the extracted metadata. Instead of broad method
probing, the helper now swizzles the narrow ObjC-visible setters that should be
hit when that update path writes location state onto device models.

Target class names:

- `FMIPCore.FMIPDevice`
- `FMIPDevice`

Target selectors:

- `setLocation:`
- `setCrowdSourcedLocation:`
- `setOwnedDeviceLocation:`
- `setPairedLocation:`
- `setSeparationLocation:`
- `setLastOnlineLocationInfo:`

The replacement calls the original setter first, then records a
`fmip_device_location_setter` event containing:

- selector name;
- target class and description;
- value class and description;
- serialized location from the setter value when possible;
- full `findMyDeviceLocationFieldsForObject:` output from the target after the
  setter.

These events appear under the existing `findMySwizzleDiagnostics` payload, so
the Android-facing refresh route can surface them through normal device refresh
diagnostics without adding a separate route.

## Build result

Built with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -workspace 'FindMy/MacOS-16+/BlueBubblesHelper.xcworkspace' \
  -scheme 'BlueBubblesHelper DyLib' \
  -configuration Release \
  -derivedDataPath 'FindMy/MacOS-16+/build' \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

## How to read this probe

If `fmip_device_location_setter` events appear, the update path is writing
location state onto `FMIPDevice`, and the next task is to map which field carries
the best Android-facing coordinate.

If no events appear but `FMIPManager.devices` still contains location-bearing
fields after refresh, then the locations may be initialized during decode rather
than later setter writes.

If no events appear and direct field reads remain empty, the next step should be
the higher-level `FindMyCore.DeviceLocationEntityQuery` route.
