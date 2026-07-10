# Find My device location step 11 - app-owned FMIP candidates

## Reasoning

Both retained-manager `FMIPDataManager` probes crashed Find My:

- Broad Swift `Mirror` value summaries crashed at the delayed snapshot point.
- Metadata-only Objective-C runtime probing also crashed at the delayed snapshot point.

That makes the retained `FMIPManager` path suspect. The safer provider-runtime route still works because it does not create a new manager, does not call `FMIPManager.devices`, and does not swizzle FMIPCore callbacks.

## Change

Extended the existing provider-runtime route:

```text
debug-findmy-devices-provider-runtime
```

The route now adds:

```text
app_owned_fmip_candidates
```

This field contains compact path/class summaries from:

- the bounded Find My root object graph
- the active Devices/Items table session-object graph

Candidate matching terms:

- `FMIPManager`
- `FMIPDataManager`
- `dataManager`
- `fmipManager`
- `devicesProvider`
- `locationProvider`

## Safety

This does not create or refresh a separate `FMIPManager`. It reuses the object graph diagnostics that already returned successfully in the bounded provider-runtime probe.

The goal is to find whether Find My already retains an app-owned `FMIPManager`, `FMIPDataManager`, or provider wrapper. If a candidate path appears, the next probe should follow only that path and then add one-field-at-a-time inspection.

## Runtime result

Installed helper checksum in the server repo:

```text
d27c53b681b97f5e8de58f411c634874
```

Provider-runtime route result:

- HTTP 200.
- Response size: 10,526 bytes.
- Request duration: 12 seconds.
- No Find My crash.
- `selected_devices_segment`: `true`.
- Active Devices data source: `FindMy.FMDevicesListDataSource`.
- Visible device cells: 13.

Candidate result:

```json
{
  "object_graph": [],
  "session_objects": []
}
```

Interpretation:

- The safe provider-runtime graph still works with the added candidate field.
- The current bounded graph did not expose an app-owned `FMIPManager`, `FMIPDataManager`, `dataManager`, `fmipManager`, `devicesProvider`, or `locationProvider` path.
- The active Devices UI is present, so the next lead is not whether the Devices view exists; it is that the current object traversal is not deep or targeted enough to reach the backing FMIPCore object.

Next step:

- Inspect `FindMy.FMDevicesListDataSource` and its delegate/list controller ivars and methods more directly.
- Include non-object Swift ivar metadata and object ivars even when their class names do not match broad terms.
- Keep the route bounded and avoid calling `FMIPManager.devices`.
