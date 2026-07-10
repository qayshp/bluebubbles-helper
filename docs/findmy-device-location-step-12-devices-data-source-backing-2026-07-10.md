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

## Bounded route result

Installed helper checksum in the server repo:

```text
053b5c560b014f963799f56de55d5a03
```

The bounded Objective-C metadata route returned successfully:

- HTTP 200.
- Runtime about 8 seconds.
- Payload size about 21 KB.
- Find My did not crash.
- Active data source remained `FindMy.FMDevicesListDataSource`.
- Active table view remained `FindMy.FMTableView`.
- Visible device cell count was 13.

Confirmed data-source Swift ivar layout:

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

Important limitation:

- Objective-C runtime ivars are present, but most Swift ivar encodings are empty.
- KVC still cannot read `devices`, `viewModels`, `cellsViewModel`, `provider`, `fmipManager`, `dataManager`, or `location`.
- `object_getIvar` is not appropriate for these Swift fields because the metadata does not mark them as Objective-C object ivars.

## Swift mirror follow-up

Added a separate helper action:

```text
debug-findmy-devices-data-source-mirror
```

This route calls Swift `Mirror` on app-owned active UI objects only:

- `FindMy.FMDevicesListDataSource`
- its delegate/list controller
- up to 3 visible `FMDeviceCellViewModel` table cells

Safety boundary:

- It does not create or retain `FMIPManager`.
- It does not call `FMIPManager.devices`.
- It does not touch `FMIPManager.dataManager`.
- It does not install FMIPCore callback swizzles.
- It returns only shallow labels, type names, display styles, scalar values, collection counts, and tiny child samples.

Installed helper checksum for this route:

```text
024cb2d3385a0fe6b17e194cee6be007
```

Build notes:

- Full Xcode was used through `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `ENABLE_USER_SCRIPT_SANDBOXING=NO` was required because the CocoaPods manifest script failed under Xcode's script sandbox while loading system/private framework dependencies.

Runtime result:

- Route: `POST /api/v1/icloud/findmy/devices/debug/data-source-mirror`
- HTTP 200.
- Runtime about 7 seconds.
- Payload size about 22.7 KB.
- Find My did not crash.

Most useful fields from the active `FMDevicesListDataSource` mirror:

- `delegate`: `Swift.Optional<FindMy.FMListDataSourceDelegate>`, containing the active `FMListViewController`.
- `mediator`: `FindMy.FMMediator`.
- `tableView`: `FindMy.FMTableView`.
- `deviceSubscription`: `Swift.Optional<FindMy.FMDevicesSubscription>`, containing `FindMy.FMDevicesSubscription`.
- `locationSubscription`: `Swift.Optional<FindMy.FMLocationSubscription>`, containing `FindMy.FMLocationSubscription`.
- `cellsViewModel`: `Swift.Array<Swift.Array<FindMy.FMDeviceCellViewModel>>`, collection count 4.
- `itemAger`: `FindMy.FMItemAger`.
- `_listTitle`: `Devices`.
- `updatesEnabled`: `true`.

`cellsViewModel` section counts from the shallow mirror:

```text
21
1
11
4
```

This is the first non-crashing path that exposes the full Devices list backing model count, not only visible cells.

The `FMMediator` child sample is also important:

- `conditionProvider`: `FindMy.FMConditionProvider`
- `devicesProvider`: `FindMy.FMDevicesProvider`
- `etaProvider`: `FindMy.FMETAProvider`
- `locationProvider`: `FindMy.FMLocationProvider`
- `peopleProvider`: `FindMy.FMPeopleProvider`
- `selectionController`: `FindMy.FMSelectionController`
- `productAssetProvider`: `FindMy.FMProductAssetProvider`
- `isRefreshing`: `true`

Next target:

- Add a focused mirror/extractor for `cellsViewModel` that samples section/row `FMDeviceCellViewModel` values and reports their child fields.
- Add a focused mirror/extractor for `FMMediator.devicesProvider`, `FMMediator.locationProvider`, and the two subscriptions.
- Continue avoiding direct `FMIPManager` access.
