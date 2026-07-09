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
