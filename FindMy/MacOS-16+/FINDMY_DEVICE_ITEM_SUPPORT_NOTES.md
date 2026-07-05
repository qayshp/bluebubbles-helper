# Find My Device and Item Support Notes

Date: 2026-07-05

Repos:

- Helper: `bluebubbles-helper-findmy-docs`, branch `codex/findmy-dylib-frameworks`
- Server: `bluebubbles-server`, branch `codex/attachment-findmy-dylib`

Local environment:

- macOS 15.7.7
- Xcode 26.3 from `/Applications/Xcode.app`
- Helper target: `BlueBubblesHelper DyLib`
- Runtime target: `/System/Applications/FindMy.app`
- Server route tested: `POST /api/v1/icloud/findmy/devices/refresh`

## Current Status

Friend locations are working through `FindMyLocateObjCWrapper` and the private API helper route. Device and item locations are not yet returned by the BlueBubbles API. The current device refresh route returns HTTP 200 with an empty `data` array.

The latest local route test used the freshly built helper dylib copied into the repo-built BlueBubbles bundle. It returned:

```json
{
  "status": 200,
  "message": "Successfully refreshed Find My device locations!",
  "data": []
}
```

The server logs included the helper diagnostics. Those diagnostics showed that the Swift bridge loaded, FMIPCore symbols are present, and the swizzles installed.

The most important newer finding is that Find My URL schemes can reliably activate Devices and Items without Apple Events, Accessibility, or `System Events`:

```sh
open 'findmy://devices'
open 'findmy://items'
open 'findmy://people'
```

After those URLs are opened, the helper swizzles see live Devices and Items table data sources. The API still returns `data: []` because serialization of the backing view models has not been implemented yet.

## Why the Old Cache Path Is Not Enough

The older BlueBubbles device path expected locally readable Find My cache data. On this macOS build, the modern device and item cache files are not directly usable JSON/plist device records. They contain encrypted payloads such as `encryptedData` and `signature`, so reading those files from the server process is not enough to return device/item locations.

That is why the current work moved toward running inside Find My via the helper dylib.

## Runtime Classes Found

The injected helper can see these useful runtime classes:

- `FMIPCore.FMIPManager`
- `FindMy.FMDevicesProvider`
- `FindMy.FMDevicesListDataSource`
- `FindMy.FMItemsListDataSource`
- `FindMyUICore.Repository`
- `FindMyUICore.SessionLive`
- `SPOwnerSession`

These are not ObjC classes, which is expected because they are Swift value types:

- `FMIPCore.FMIPDevice`
- `FMIPCore.FMIPItem`

The visible Find My UI object graph during route testing was still People-centric:

- `FindMy.FMApplication`
- `FindMy.FMAppDelegate`
- `FindMy.FMMainViewController`
- `FindMy.FMInitialSideBarController`
- `FindMy.FMMapViewController`
- `FindMy.FMPeopleListDataSource`
- `FindMy.FMTableView`

## Attempt 1: Direct Swift Imports

I tried compiling Swift probes against the private frameworks with full Xcode and private framework search paths.

These imports failed with `no such module`:

```swift
import FMIPCore
import FindMyCore
import FindMyUICore
import FindMy
import FindMyDevice
import FindMyLocate
```

The frameworks exist and have symbols, but they do not expose importable `.swiftmodule` files for our helper target. That blocks normal Swift source like:

```swift
import FMIPCore

let manager = FMIPManager(configuration: .default, ownerSession: ownerSession)
```

## Attempt 2: Mixed Swift/ObjC Dylib

I added Swift to the dylib target and built a mixed Swift/ObjC helper. This works. The helper now has:

- `FindMySwiftBridge.swift`
- `BlueBubblesHelper DyLib-Bridging-Header.h`
- Xcode project changes to compile Swift into `BlueBubblesFindMyHelper.dylib`

The Swift bridge can run inside Find My and return an NSDictionary to ObjC. This confirms Swift runtime code in the helper is viable.

## Attempt 3: Swift ABI Symbol Probe

Since direct imports failed, I used `dlsym` and `@_silgen_name` for known FMIPCore symbols.

Confirmed present:

```swift
FMIPManagerConfiguration.default
FMIPManager.init(configuration:ownerSession:)
FMIPManager.initialize
FMIPManager.startRefreshing
FMIPManager.refresh
FMIPManager.devices
FMIPManager.items
```

The current bridge declares these methods:

```swift
@_silgen_name("$s8FMIPCore24FMIPManagerConfigurationC7defaultACvgZ")
private func FMIPManagerConfigurationDefault() -> AnyObject

@_silgen_name("$s8FMIPCore11FMIPManagerC13configuration12ownerSessionAcA0B13ConfigurationC_So07SPOwnerE0CtcfC")
private func FMIPManagerCreate(_ configuration: AnyObject, _ ownerSession: AnyObject) -> AnyObject

@_silgen_name("$s8FMIPCore11FMIPManagerC10initializeyyF")
private func FMIPManagerInitialize(_ manager: AnyObject)

@_silgen_name("$s8FMIPCore11FMIPManagerC15startRefreshingyyF")
private func FMIPManagerStartRefreshing(_ manager: AnyObject)

@_silgen_name("$s8FMIPCore11FMIPManagerC7refreshyyF")
private func FMIPManagerRefresh(_ manager: AnyObject)
```

This compiled, but calling it directly from the device refresh request path hung the request. Find My did not crash, but the HTTP route did not complete. I removed the active call from the request path and left the probe callable but unused.

Current conclusion: Swift ABI access is promising for a future bridge, but the FMIPManager lifecycle needs to be driven off the right Find My app state or queue. Calling `initialize/startRefreshing/refresh` synchronously from the route is not safe.

## Attempt 4: SPOwnerSession

I loaded `/System/Library/PrivateFrameworks/SPOwner.framework`, created `SPOwnerSession`, and called `startRefreshing`. The class is ObjC-visible and exposes useful methods.

Potentially useful methods seen:

```objc
- init
- startRefreshing
- allBeacons
- allBeaconsWithCompletion:
- allBeaconsCache
- allObservationsForBeacon:completion:
- beaconForIdentifier:completion:
- beaconForUUID:completion:
- locationForContext:completion:
- locationsForBeacons:completion:
- requestLiveLocationForUUID:completion:
- subscribeAndFetchLocationForContext:completion:
- latestLocationsUpdatedBlock
- setLatestLocationsUpdatedBlock:
- setLocationUpdateBlock:
- setBeaconsChangedBlock:
```

The route invokes `allBeaconsWithCompletion:` when available and serializes returned beacons as Find My items. On this machine, that completed cleanly but returned `owner_beacon_count: 0`.

Current conclusion: `SPOwnerSession` may be the right lower-level path for items, but a plain new session is not enough here. It may need the Find My app's existing owner session, account context, or the right subscription context before beacons populate.

## Attempt 5: Find My UI Object Graph

I added a bounded object graph scan from app/window roots inside Find My. It finds the active app, main view controller, side bar controller, map controller, table view, and People datasource.

What it showed:

- Find My is loaded and the helper is injected into `com.apple.findmy`.
- The visible table is backed by `FindMy.FMPeopleListDataSource`.
- Devices and Items datasource classes are loaded, but no active Devices/Items datasource instance was found while the route ran.

I also tried selecting the Devices segment by finding segmented controls and sending a normal `setSelectedSegmentIndex:` style selector. That did not work because `FindMy.FMSegmentedControl` is custom and only exposes:

```objc
- initWithCoder:
- initWithFrame:
- initWithItems:
- touchesEnded:withEvent:
```

Current conclusion: the current route cannot just "click" the Devices/Items tab through a standard `UISegmentedControl` API.

## Attempt 6: Passive Swizzling

I added passive swizzles for table/data-source observation:

- `FindMy.FMPeopleListDataSource tableView:numberOfRowsInSection:`
- `FindMy.FMPeopleListDataSource tableView:cellForRowAtIndexPath:`
- `FindMy.FMDevicesListDataSource tableView:numberOfRowsInSection:`
- `FindMy.FMDevicesListDataSource tableView:cellForRowAtIndexPath:`
- `FindMy.FMItemsListDataSource tableView:numberOfRowsInSection:`
- `FindMy.FMItemsListDataSource tableView:cellForRowAtIndexPath:`
- `FindMy.FMTableView setDataSource:`

The swizzles install and preserve the original IMPs. They only record events and then call through.

Initial observed result:

- The People datasource fired repeatedly.
- It showed section 2 with 7 People rows and People cell view models.
- No Devices datasource events fired.
- No Items datasource events fired.

Representative classes captured:

```text
FindMy.FMPeopleListDataSource
FindMy.FMTableView
_TtGC6FindMy19FMListTableViewCellVS_17FMMeCellViewModel_
_TtGC6FindMy19FMListTableViewCellVS_21FMPeopleCellViewModel_
```

Updated observed result after URL-scheme activation:

- `FindMy.FMDevicesListDataSource` fired.
- `FindMy.FMItemsListDataSource` fired.
- Devices cells used `FMDeviceCellViewModel`.
- Items cells used `FMItemCellViewModel`.

The Devices table events included row counts like:

```text
section 0: 21 rows
section 1: 1 row
section 2: 11 rows
section 3: 4 rows
```

The Items table events included row counts like:

```text
section 0: 11 rows
section 1: 14 rows
```

Representative device and item cell classes:

```text
_TtGC6FindMy19FMListTableViewCellVS_21FMDeviceCellViewModel_
_TtGC6FindMy19FMListTableViewCellVS_19FMItemCellViewModel_
```

Current conclusion: swizzling is useful for observation, and URL-scheme activation provides the reliable way to make Find My instantiate the Devices and Items UI paths. It does not by itself return device/item locations; the next step is to inspect and serialize the backing `FMDeviceCellViewModel` / `FMItemCellViewModel` objects or their provider models.

## Attempt 7: Apple Events, Accessibility, and URL Schemes

I tried to drive Find My tabs by keyboard shortcuts:

```text
People:  Command-1
Devices: Command-2
Items:   Command-3
```

The Apple Events / `System Events` path was fragile because macOS TCC repeatedly denied `com.openai.codex` access to `com.apple.systemevents` with error `-1743`, even after resets and permission changes. Accessibility-style CoreGraphics key posting worked sometimes from an external helper process, but was not reliable enough as a primary integration mechanism.

Direct AppleScript commands to Find My are not a good path either. `showPeople`, `showDevices`, and `showItems` appear in the Find My binary as internal selectors, but they are not AppleScript commands. `sdef` could not retrieve a scripting dictionary for `/System/Applications/FindMy.app`, and Apple Events to `com.apple.findmy` were also TCC-gated.

The reliable path found locally is URL-scheme activation.

Find My registers these URL schemes in its `Info.plist`:

```text
grenada
findmyfriends
fmf1
findmy
fmip1
```

Useful broad tab activation URLs:

```sh
open 'findmy://people'
open 'findmy://devices'
open 'findmy://items'
```

Useful deep-link templates found in the binary:

```text
findmy://bypass/device?id=
findmy://bypass/item?id=
findmy://bypass/item?id=&op=localnotifywhenfound
fmip1://device/device?sn=
```

`bypass` appears to mean "open directly into a device/item flow and bypass normal landing or welcome UI." Nearby strings include:

```text
bypassWelcomeScreen
FMUTContentViewController: Not showing UT welcome since it's bypassed
```

`grenada` is registered as a URL scheme, but no clear local string explains it. It appears to be an Apple-internal or legacy Find My scheme name. The practical schemes for this work are `findmy` and `fmip1`.

Verified swizzle events after opening URL schemes:

```text
FindMy.FMDevicesListDataSource
  tableView:numberOfRowsInSection:
    section 0 -> 21
    section 1 -> 1
    section 2 -> 11
    section 3 -> 4
  tableView:cellForRowAtIndexPath:
    _TtGC6FindMy19FMListTableViewCellVS_21FMDeviceCellViewModel_

FindMy.FMItemsListDataSource
  tableView:numberOfRowsInSection:
    section 0 -> 11
    section 1 -> 14
  tableView:cellForRowAtIndexPath:
    _TtGC6FindMy19FMListTableViewCellVS_19FMItemCellViewModel_
```

## Potentially Useful Swift Methods and Symbols

These FMIPCore manager methods are the most likely direct route if we can create a manager safely and bridge Swift value arrays:

```text
FMIPManagerConfiguration.default
FMIPManager.init(configuration:ownerSession:)
FMIPManager.initialize
FMIPManager.startRefreshing()
FMIPManager.startRefreshing(subsystems:)
FMIPManager.refresh()
FMIPManager.refresh(subsystems:)
FMIPManager.devices -> [FMIPDevice]
FMIPManager.items -> [FMIPItem]
FMIPManager.itemGroups -> [FMIPItemGroup]
```

Useful `FMIPDevice` accessors found in exports:

```text
FMIPDevice.identifier -> String
FMIPDevice.name -> String
FMIPDevice.displayName -> String
FMIPDevice.modelDisplayName -> String
FMIPDevice.hasLocation -> Bool
FMIPDevice.location -> FMIPLocation?
FMIPDevice.bestLocation -> FMIPLocation?
FMIPDevice.crowdSourcedLocation -> FMIPLocation?
FMIPDevice.batteryLevel -> Double
FMIPDevice.batteryStatus -> FMIPBatteryStatus
FMIPDevice.ownerIdentifier -> String
FMIPDevice.address -> FMIPAddress?
FMIPDevice.isAppleAudioAccessory -> Bool
FMIPDevice.isConsideredAccessory -> Bool
FMIPDevice.itemGroup -> FMIPItemGroup?
```

Useful `FMIPLocation` accessors found in exports:

```text
FMIPLocation.location -> CLLocation
FMIPLocation.locationType -> FMIPLocationType
FMIPLocation.isOld -> Bool
FMIPLocation.isInaccurate -> Bool
FMIPLocation.isLocationFinished -> Bool
FMIPLocation.debugDescription -> String
```

Potential item-side symbols seen while scanning exports:

```text
FMIPManager.items -> [FMIPItem]
FMIPManager.itemGroups -> [FMIPItemGroup]
FMIPItemGroup.items -> [FMIPItem]
FMIPItemRole.identifier -> Int
FMIPItemRole.name -> String
FMIPItemRole.emoji -> String
FMIPItemType.rawValue -> Int
FMIPItemType.accessory
FMIPItemType.durian
FMIPItemType.selfBeaconing
```

The hard part is not symbol presence. The hard part is safely calling methods whose return values are Swift generic arrays of private Swift structs without importable type metadata in our source.

## Current Blockers

1. `FMIPCore` and related frameworks cannot be imported normally from Swift.
2. `FMIPDevice` and `FMIPItem` are Swift structs, not ObjC objects, so ObjC runtime serialization will not work.
3. The direct `@_silgen_name` FMIPManager lifecycle call hangs when run synchronously from the helper route.
4. `SPOwnerSession allBeaconsWithCompletion:` returns zero beacons from a newly created session on this machine.
5. Devices/Items data sources are not activated by the private API request alone, but can be activated reliably with `findmy://devices` and `findmy://items`.
6. The custom Find My segmented control does not expose a standard selected-index setter.
7. Apple Events through `System Events` are too fragile for this workflow because TCC can deny or re-deny Codex automation access.

## Next Options

The strongest next paths are:

1. Find and reuse the existing FMIPManager or provider instance from the live Find My object graph instead of constructing a new one.
2. Build a deeper Swift ABI bridge that calls `FMIPManager.devices/items` and serializes inside Swift, with declarations for enough private structs to read fields safely.
3. Use `findmy://devices` and `findmy://items` to force Apple-initialized Devices/Items UI state before the helper refresh runs.
4. Hook provider update callbacks or data-source initialization earlier, then capture the actual Devices/Items provider instance once Find My creates it.
5. Inspect and serialize `FMDeviceCellViewModel` and `FMItemCellViewModel` backing fields.
6. Continue inspecting `SPOwnerSession` contexts and blocks to discover why `allBeaconsWithCompletion:` returns zero in a fresh session.
