# Find My device location step 5 - FMIPCore extraction inspection

## Why this step

The delayed `FMIPManager.devices` probe crashed even after reducing the snapshot to count-only. That means device extraction should stop pulling the `devices` property directly through the handwritten `_silgen_name` bridge.

## Crash conclusion from step 4

The following all crashed at the delayed snapshot point after refresh:

- Raw Swift `FMIPDevice` array returned through Objective-C.
- Swift metadata-only snapshot with type, description, and Mirror summaries.
- Swift count-only snapshot that only evaluated `FMIPManager.devices.count`.

This rules out Objective-C KVC serialization and raw Objective-C bridging as the only crash source. The remaining likely issue is either the `FMIPManager.devices` accessor itself in this injected context, or the handwritten ABI declaration for a Swift array of `FMIPDevice` values.

## Extraction artifacts used

The useful preserved dyld extraction is:

```text
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract
```

The important files are:

```text
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/inspection/FMIPCore.strings.txt
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/inspection/FMIPCore.strings.demangled.txt
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/inspection/FMIPCore.nm.demangled.txt
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/inspection/SiriFindMy.strings.demangled.txt
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/inspection/SiriFindMy.nm.demangled.txt
```

The live framework directory is only a dyld-cache stub for code. The actual FMIPCore image is in the shared cache. The x86_64 and arm64e cache maps both include:

```text
/System/Library/PrivateFrameworks/FMIPCore.framework/Versions/A/FMIPCore
```

## FMIPCore evidence

`swift-demangle` confirms the direct accessor we tried:

```text
FMIPCore.FMIPManager.devices.getter : [FMIPCore.FMIPDevice]
```

FMIPCore strings show a better push/callback path than directly reading that property:

```text
FMIPManager: didReceiveDevices
%{public}s: received %ld devices
%{public}s: received %ld devices incl. %ld locations asked
%{public}s: received %ld devices but no location asked
FMIPManager: updating locating devices lastOnlineLocationInfo: %ld
FMIPDataManager: updateDevicesLocations device %s location: %{bool}d, crowdsourcedLocation: %{bool}d
FMIPDataManager: updateDevicesLocations %ld type %s
FMIPManager: appending realtime location to devices %{private}s
FMIPManager: using realtime location for "%s". Location: %s
FMIPManager: trimming realtime location for "%s" because of coarse location %s
FMIPManager: devices changed after realtime location %@
```

The extracted strings also show location-bearing device fields:

```text
FMIPDevice:
    -- id: %s,
    -- name: %s,
    -- baId: %s
    -- isAccessory: %{bool}d
    -- onlineLocation: %s
    -- offlineLocation: %s
    -- bestLocation: %s
    -- itemGroup: %s
    -- itemGroupItemsId: %s
    -- shouldDisplaySeparatedLocation: %{bool}d
    -- beaconType: %s
    -- deviceConnectedType: %s
    -- deviceAssociatedWithBeacon: %s
```

Useful FMIPCore classes/protocol names present in extracted strings:

- `FMIPManagerDelegate`
- `FMIPDataManagerDelegate`
- `FMIPLocationControllerDelegate`
- `FMIPRefreshingControllerDelegate`
- `FMIPDataManager`
- `FMIPLocationController`
- `FMIPRefreshingController`
- `FMIPDevice`
- `FMIPLocation`

`ktool` did not recover clean Swift method declarations for these classes; it logged many ObjC metadata load errors. The strings and demangled symbol/type metadata are more useful than the generated headers for FMIPCore.

## SiriFindMy evidence

SiriFindMy has a higher-level device layer that may avoid direct `FMIPManager.devices` pulls:

```text
SiriFindMy.FMIPCoreFindDeviceSession
SiriFindMy.FMIPSyncDeviceProvider
SiriFindMy.FMIPManagerWrapper
SiriFindMy.FMIPManagerWrapperImpl
SiriFindMy.FindmyDevice
SiriFindMy.FindmyDevice.Builder
devicesPublisher
devicesSubject
Intialized devices (count: %ld, with location: %ld)
Refreshed devices (count: %ld with location: %ld)
SyncDeviceProvider: found %ld devices
Fetching devices from syncDevice endpoint
Timed out waiting for device to have a geocoded location
No device location available, skipping user location.
Can't speak deviceLocation. (featureEnabled: %{BOOL}d, deviceIsNil: %{BOOL}d, locationIsNil: %{BOOL}d)
```

That suggests SiriFindMy may already have a normalized list of devices, including a location-present count, without requiring direct FMIPCore device-array extraction.

## Recommendation

Do not keep calling `FMIPManager.devices` directly from the helper.

Next candidate paths, in order:

1. Add a narrow runtime hook around FMIPCore update/callback flow:
   - `FMIPManager: didReceiveDevices`
   - `FMIPDataManager: updateDevicesLocations`
   - `FMIPManager` realtime-location update flow

2. Inspect/runtime-probe SiriFindMy providers:
   - `SiriFindMy.FMIPCoreFindDeviceSession`
   - `SiriFindMy.FMIPSyncDeviceProvider`
   - `SiriFindMy.FMIPManagerWrapperImpl`
   - `devicesPublisher` / `devicesSubject`

3. Only after a callback or provider yields concrete device objects, serialize exact known location fields:
   - `onlineLocation`
   - `offlineLocation`
   - `bestLocation`
   - `location`
   - `crowdSourcedLocation`
   - `lastOnlineLocationInfo`

The immediate next implementation should be a dedicated debug action that installs targeted hooks and records callback argument summaries. It should not call `FMIPManager.devices`, and it should not run inside the Android-facing refresh route.
