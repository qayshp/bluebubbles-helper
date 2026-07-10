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

## First runtime result

Installed helper checksum in the server repo:

```text
76a48d9a1f887ddf48852cf92e55bf92
```

The route reached Find My and produced useful diagnostics, but the payload was too large for the BlueBubbles helper socket framing:

- Request started at `2026-07-10 09:41:18`.
- BlueBubbles logged `Failed to decode BlueBubblesHelper data!`.
- Curl timed out after 90 seconds with HTTP `000`.
- Find My did not crash.

Useful data visible before truncation:

- Active data source: `FindMy.FMDevicesListDataSource`.
- Active delegate/list controller: `_TtGC6FindMy20FMListViewControllerCS_23FMDevicesListDataSourceCS_14FMNoDeviceViewCS_21FMDevicesTerminalView_`.
- `FMDevicesListDataSource` Swift ivars:
  - `delegate`
  - `mediator`
  - `tableView`
  - `deviceSubscription`
  - `locationSubscription`
  - `cellsViewModel`
  - `itemAger`
  - `updateQueue`
  - `delayedUpdateWorkItem`
  - `isRemovingCell`
  - `_listTitle`
  - `updatesEnabled`
- Data source KVC attempts for obvious keys such as `devices`, `viewModels`, `cellsViewModel`, `provider`, `fmipManager`, `dataManager`, and `location` returned nil or unreadable.
- Visible cells are still `_TtGC6FindMy19FMListTableViewCellVS_21FMDeviceCellViewModel_`, and their Swift ivars include UI fields such as `titleLabel`, `subtitleLabel`, `distanceLabel`, and `batteryStatusView`.

## Payload-bound follow-up

The probe was reduced to avoid another socket decode failure:

- Runtime ivar/method scans now include only classes whose declaring class name contains `FindMy`.
- Visible cell samples are limited to 3.
- The table view now returns a shallow summary instead of full UIKit metadata.
- Method limits and KVC readable-result limits were reduced.

Next target if this bounded route returns:

- Inspect `cellsViewModel` specifically, likely by reading the Swift ivar memory layout or by invoking table data-source methods for a row and inspecting the returned cell/view-model class metadata.
