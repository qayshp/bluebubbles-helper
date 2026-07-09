# Find My device location step 1 - FMIPDevice field probe - 2026-07-09

## Goal

Try the first recommended Device-location probe:

> Instrument `FMIPDevice` records returned by the existing device refresh path.
> Dump `location`, `crowdSourcedLocation`, `ownedDeviceLocation`,
> `pairedLocation`, `separationLocation`, and `lastOnlineLocationInfo` for every
> device after refresh.

## Implementation

Added a Swift bridge export:

```swift
BlueBubblesFindMyCopyFMIPManagerDevices()
```

The bridge calls the private Swift symbol for:

```text
FMIPCore.FMIPManager.devices
```

and returns the retained manager's current Device array to Objective-C for
serialization.

Added Objective-C serializers:

- `serializeFMIPDevice:`
- `findMyDeviceLocationFieldsForObject:`
- `serializedFMIPManagerDevicesWithDiagnostics:`

The new field probe records:

- field presence for each candidate location key;
- runtime class of each present field;
- a serialized latitude/longitude payload when `serializeLocationObject:` can
  decode one;
- a compact summary when a field exists but is not directly serializable as a
  location.

The device refresh path now:

1. resolves the captured owner session;
2. starts `FMIPCore.FMIPManager` using the existing Swift bridge;
3. snapshots `FMIPManager.devices`;
4. appends serialized FMIP devices to the returned `devices` array;
5. includes `fmip_manager_start` and `fmip_manager_devices` diagnostics.

## Build result

Initial build with the default developer directory failed because `xcodebuild`
was still using Command Line Tools:

```text
xcode-select: error: tool 'xcodebuild' requires Xcode, but active developer directory '/Library/Developer/CommandLineTools' is a command line tools instance
```

Building with full Xcode via `DEVELOPER_DIR` worked, but Xcode 26 user script
sandboxing blocked the CocoaPods manifest script from loading private/system
framework dependencies. The successful command was:

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

Built dylib:

```text
FindMy/MacOS-16+/build/Build/Products/Release/BlueBubblesFindMyHelper.dylib
```

## Next check

Install this dylib into the server app resources, restart the BlueBubbles server,
and call the Android-facing Device refresh API. Inspect the returned
`findmy_device_location_probe` fields and the server log's
`fmip_manager_devices` diagnostics.
