# Find My device location step 12 - Devices data-source backing inspection

## Reasoning

The previous safe provider-runtime route confirmed:

- The Devices view can be selected.
- `FindMy.FMDevicesListDataSource` is active.
- 13 device cells are visible.
- `FMIPCore.FMIPManager` and `FMIPCore.FMIPDataManager` exist in runtime metadata.
- The bounded app-owned FMIP candidate scan found no direct `FMIPManager`, `FMIPDataManager`, `fmipManager`, `dataManager`, `devicesProvider`, or `locationProvider` path.

The retained/new `FMIPManager` route is unsafe, so this probe stays on the app-owned UI/data-source side.

## Helper action

Added:

```text
debug-findmy-devices-data-source
```

This action selects Devices and inspects:

- active `FindMy.FMDevicesListDataSource`
- its table delegate/list controller
- its `FindMy.FMTableView`
- up to 6 visible device cells

## Safety boundaries

This probe does not:

- create `FMIPManager`
- call `FMIPManager.devices`
- touch `FMIPManager.dataManager`
- swizzle FMIPCore callbacks

It records bounded metadata and summaries:

- runtime ivar names, encodings, offsets, and declaring classes
- methods matching device/location/model/viewModel/data/source/provider/manager/session/snapshot terms
- bounded KVC summaries for candidate structural keys
- object-ivar value summaries only for Objective-C object ivars (`@` encodings)

## Expected interpretation

- If the data source exposes readable device arrays, view models, snapshots, or provider objects, follow that path next and inspect one object type at a time.
- If only visible cell view models contain useful fields, extract the view model schema and look for backing identifiers or location fields.
- If the route crashes, remove KVC reads and keep only runtime metadata for the data source/list controller/cell classes.
