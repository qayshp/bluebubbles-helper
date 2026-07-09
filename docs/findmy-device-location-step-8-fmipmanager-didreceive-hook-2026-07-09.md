# Find My device location step 8 - FMIPManager didReceiveDevices hook

## Goal

Try the second FMIPCore callback lead after the broad callback watcher and the scoped `FMIPDataManager.updateDevicesLocations` hook both crashed Find My.

## Change

The debug route:

```text
POST /api/v1/icloud/findmy/devices/debug/fmip-callbacks
```

now installs only:

```text
FMIPCore.FMIPManager / _TtC8FMIPCore11FMIPManager / FMIPManager
selector contains didReceiveDevices
```

The helper still avoids `FMIPManager.devices` and uses the same generic object-argument trampoline filter.

## Why this target

`didReceiveDevices` is likely upstream of any device list or location mutation. If the selector is ObjC-visible and receives an object argument containing devices or location updates, it could provide a safer observation point than pulling the `devices` accessor.

## Expected interpretation

- Route returns with callbacks: inspect callback argument summaries for device arrays, `CLLocation`, or FMIP location fields.
- Route returns with zero callbacks: move to SiriFindMy provider inspection.
- Find My crashes: the generic swizzle approach is likely too risky for FMIPCore Swift methods; switch to non-swizzling runtime/provider inspection.

## Runtime result

Installed helper md5 in `bluebubbles-server`:

```text
ad90e7d2cd4fed4c56edbc1d692781c1
```

Route call on 2026-07-09:

```text
POST /api/v1/icloud/findmy/devices/debug/fmip-callbacks
```

Result:

- The request timed out after 45 seconds with no response body.
- The server logged the request at `2026-07-09 09:25:32`.
- The Find My private helper socket ended at `2026-07-09 09:25:35`.
- The server marked Find My as force quit and relaunched it.
- The helper reconnected afterward.

Interpretation:

- `FMIPManager.didReceiveDevices` is also unsafe with the current generic swizzle trampoline.
- Combined with the `FMIPDataManager.updateDevicesLocations` result, callback swizzling of FMIPCore Swift methods should pause.
- The next step should be non-swizzling inspection of SiriFindMy providers, especially `FMIPSyncDeviceProvider`, `devicesPublisher`, and related stored objects.
