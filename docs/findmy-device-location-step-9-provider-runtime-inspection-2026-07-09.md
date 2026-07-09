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

## First runtime result

Installed helper md5 in `bluebubbles-server`:

```text
a76211d6b7eff967b56647c6831f12e6
```

Route call on 2026-07-09:

```text
POST /api/v1/icloud/findmy/devices/debug/provider-runtime
```

Result:

- HTTP 200.
- Find My did not crash.
- `selected_devices_segment` was `true`.
- `active_devices_list.visible_cell_count` was `13`.
- The route response was over-compacted and omitted the intended `runtime`, `object_graph`, `session_objects`, and `probe_mode` fields.

Interpretation:

- Non-swizzling provider inspection is stable.
- The helper needs to return full diagnostics for this route instead of `compactFindMyRefreshDiagnostics`.

## Full diagnostics result

Installed helper md5 in `bluebubbles-server`:

```text
2e14aefbe35c29b9248ba44d84e839d7
```

Result:

- The helper sent the full diagnostics payload.
- The server failed to decode it because the JSON was too large for the helper socket framing and arrived split around 64 KB chunks.
- The HTTP request timed out because the transaction never decoded.

Useful information visible in the server log before truncation:

- `SiriFindMy.FMIPCoreFindDeviceSession` was not runtime-available.
- `SiriFindMy.FMIPSyncDeviceProvider` was not runtime-available.
- `SiriFindMy.FMIPManagerWrapperImpl` was not runtime-available.
- `FMIPCore.FMIPManager` was runtime-available and exposed ivars including:
  - `delegate`
  - `siriDelegate`
  - `refreshingController`
  - `locationController`
  - `ownerSession`
  - `dataManager`
  - `snapshotDevicesResponseReceived`
  - `isUpdatingSingleDevices`
- `FMIPCore.FMIPDataManager` was runtime-available and exposed ivars including:
  - `devices`
  - `owner`
  - `familyMembers`
  - `crowdSourcedOriginalLocations`
  - `crowdSourcedLocations`
  - `deviceConnectedStates`
  - `safeLocations`
  - `safeLocationsMapping`
  - `items`
  - `itemGroups`

Interpretation:

- Provider inspection is still the right low-risk path, but the route must return bounded summaries.
- The most promising non-UI next target is `FMIPDataManager` ivar inspection, especially `devices` and `crowdSourcedLocations`, from a retained `FMIPManager.dataManager` instance rather than the Swift `FMIPManager.devices` accessor.
