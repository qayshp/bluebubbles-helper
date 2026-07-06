# Find My Devices and Items API Check - 2026-07-05

## Environment

- Server repo: `bluebubbles-server`
- Server branch: `codex/attachment-findmy-dylib`
- Helper repo: `bluebubbles-helper`
- Helper branch: `codex/findmy-dylib-frameworks`
- Server app tested: built `dist/mac/BlueBubbles.app`
- Server port: `1234`
- Private API config:
  - `enable_private_api=1`
  - `private_api_mode=process-dylib`

## TCC Permissions

The Settings app showed Accessibility and Automation enabled. CLI checks matched that state:

```text
kTCCServiceAppleEvents|2|com.apple.systemevents
kTCCServiceAccessibility|2
```

`auth_value=2` means authorized.

## Android-Facing API Results

These routes were called through the same HTTP surface the Android app uses:

```text
GET  /api/v1/icloud/findmy/friends          -> 8 records
GET  /api/v1/icloud/findmy/devices          -> 0 records, data was null
GET  /api/v1/icloud/findmy/items            -> 0 records, data was null
POST /api/v1/icloud/findmy/friends/refresh  -> 8 records
POST /api/v1/icloud/findmy/devices/refresh  -> 0 records, empty array
POST /api/v1/icloud/findmy/items/refresh    -> 0 records, empty array
```

Refresh timings from the BlueBubbles log:

```text
/devices/refresh took 34936 ms
/items/refresh took 14569 ms
```

## Log and Crash Check

No authorization errors appeared during the current test window. No new Find My crash reports were created after the patched helper dylib was installed.

Older crashes at `22:21:26` and `22:22:24` were both from the prior unsafe table-view probing path:

```text
BBFindMyTableViewNumberOfRows
findMyListRowsForDataSourceTerm:type:
handleFindMyDevicesRefreshWithTransaction: or handleFindMyItemsRefreshWithTransaction:
```

That path was removed by switching the list fallback to inspect visible cells instead of calling Find My table-view data-source methods.

## Current Instrumentation Findings

The helper now reaches the expected loaded Find My views:

```text
Devices: _TtGC6FindMy20FMListViewControllerCS_23FMDevicesListDataSourceCS_14FMNoDeviceViewCS_21FMDevicesTerminalView_
Items:   _TtGC6FindMy20FMListViewControllerCS_21FMItemsListDataSourceCS_12FMNoItemViewCS_18FMItemTerminalView_
```

Other observed state:

```text
FMDevicesProvider.available=false
FMItemsListDataSource.available=false
FindMy.FMItemDetailDataSource.available=true
SPOwnerSession.available=true
owner_beacon_count=0
owner_beacon_timeout=true for item refresh
```

The view-switching problem appears solved for this run. The remaining issue is data extraction from the loaded Devices and Items views.

## Next Step

Extend dylib instrumentation to dump active list controller and data source internals for the two Swift generic controller classes above:

- visible cell count and visible cell classes
- active table view data source class and delegate class
- child view controller ivars
- list controller ivars
- data source ivars
- any arrays, dictionaries, sets, diffable snapshots, or view-model collections reachable from those objects
- object summaries for classes containing `Device`, `Item`, `Beacon`, `Location`, `DataSource`, or `ViewModel`

The goal is to identify where Find My stores the loaded device and item model objects so the helper can serialize real records instead of returning empty arrays.
