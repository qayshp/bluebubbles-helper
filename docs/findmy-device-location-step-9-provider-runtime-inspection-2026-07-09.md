# Find My device location step 9 - provider runtime inspection

## Goal

Move away from FMIPCore callback swizzling after both narrow callback hooks crashed Find My.

## Helper action

Added:

```text
debug-findmy-devices-provider-runtime
```

This action:

1. Selects the Devices view.
2. Installs only the normal Find My passive swizzles.
3. Does not install FMIPCore callback swizzles.
4. Does not call `FMIPManager.devices`.
5. Returns runtime diagnostics and object/session graph summaries.

## Runtime targets

The route inspects:

- `SiriFindMy.FMIPCoreFindDeviceSession`
- `_TtC10SiriFindMy23FMIPCoreFindDeviceSession`
- `SiriFindMy.FMIPSyncDeviceProvider`
- `_TtC10SiriFindMy22FMIPSyncDeviceProvider`
- `SiriFindMy.FMIPManagerWrapperImpl`
- `_TtC10SiriFindMy22FMIPManagerWrapperImpl`
- `SiriFindMy.FindDeviceIntentHandler`
- `_TtC10SiriFindMy23FindDeviceIntentHandler`
- `FMIPCore.FMIPManager`
- `_TtC8FMIPCore11FMIPManager`
- `FMIPCore.FMIPDataManager`
- `_TtC8FMIPCore15FMIPDataManager`

Matching terms include:

- `device`
- `location`
- `provider`
- `publisher`
- `subject`
- `sync`
- `manager`
- `session`
- `refresh`
- `receive`
- `update`

## Why this is safer

The previous FMIPCore callback probes crashed Find My before returning diagnostics. This probe is read-only runtime and object graph inspection, so it should let us identify provider methods or retained provider instances before trying any method-specific call or hook.

## Expected next step

If this route returns provider methods or captured instances, inspect:

- `devicesPublisher`
- `devicesSubject`
- provider ivars that retain current devices
- wrapper/session references to an FMIP manager or provider

Only after a concrete method signature is known should we try a method-specific hook or direct invocation.
