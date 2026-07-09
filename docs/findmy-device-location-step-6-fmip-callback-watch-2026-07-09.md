# Find My device location step 6 - FMIP callback watch

## Goal

Move away from direct `FMIPManager.devices` reads. The count-only direct accessor still crashed Find My, so this probe watches the FMIPCore/SiriFindMy update path without pulling the device array.

## Helper action

Added:

```text
debug-findmy-devices-fmip-callbacks
```

The action:

1. Installs the normal Find My swizzles.
2. Installs a narrow FMIP/SiriFindMy callback watcher.
3. Selects the Devices view.
4. Starts `FMIPManager` through the existing Swift bridge.
5. Waits 8 seconds.
6. Returns callback diagnostics, runtime method summaries, swizzle diagnostics, passive captures, and active visible-device-list diagnostics.

## Callback watcher behavior

The watcher only swizzles methods that are already visible through Objective-C runtime metadata. It does not swizzle Swift-value signatures.

It requires:

- 0 to 3 explicit arguments.
- Every explicit argument to be object/block typed in the method encoding.
- A selector name matching one of the callback/provider terms:
  - `didReceiveDevices`
  - `updateDevicesLocations`
  - `updateDevices`
  - `didRefresh`
  - `refreshClientRequest`
  - `initClientRequest`
  - `devicesPublisher`
  - `devicesSubject`
  - `syncDevice`
  - `findDevice`
  - `location`

The target classes include:

- `FMIPCore.FMIPManager`
- `FMIPCore.FMIPDataManager`
- `FMIPCore.FMIPRefreshingController`
- `FMIPCore.FMIPLocationController`
- `SiriFindMy.FMIPCoreFindDeviceSession`
- `SiriFindMy.FMIPSyncDeviceProvider`
- `SiriFindMy.FMIPManagerWrapperImpl`

## Expected result

If the route returns and `fmip_callbacks.callback_count` grows, we can inspect callback arguments and only then serialize exact known location fields. If it returns with no callbacks, the next step is SiriFindMy provider/runtime probing. If it crashes, the watcher is still too broad and should be reduced to runtime diagnostics only plus one selector at a time.
