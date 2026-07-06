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

## 2026-07-06 Update: Devices, Items, and SearchParty

The Android-facing routes now return visible Find My UI rows for all three categories on this machine:

```text
friends 8 200
devices 13 200
items 12 200
```

Devices and Items are currently sourced from the active Find My list UI. The helper switches to the Devices or Items view, finds the active `FindMy.FMTableView`, reads visible cells, and serializes text plus bounded model diagnostics from:

```text
_TtGC6FindMy19FMListTableViewCellVS_21FMDeviceCellViewModel_
_TtGC6FindMy19FMListTableViewCellVS_19FMItemCellViewModel_
```

That is enough to populate the Android API surface, but it is still UI-backed and therefore limited by visible/loaded cells. The next goal is to find a non-UI source for Devices, Items, or Beacons.

For that work, we are using `SearchParty` as the internal name for the `SPOwnerSession` path. `SP` is treated as SearchParty in code comments and docs for this investigation.

### SearchParty Attempt: Active `allBeaconsWithCompletion:`

I tried collecting SearchParty diagnostics by calling `SPOwnerSession allBeaconsWithCompletion:` during the Devices and Items refresh route, even when UI rows were already available. The code built and injected successfully, but the Devices refresh hung until the HTTP client timed out at 120 seconds.

Important details:

- Friends still returned immediately.
- Devices timed out before the helper could send a response.
- The in-helper timeout did not fire, which means the `allBeaconsWithCompletion:` invocation itself appears to block the Find My main thread before control returns.
- I restored the stable route and redeployed the stable dylib after the test.
- Final stable verification returned:

```text
friends 8 200
devices 13 200
items 12 200
```

Current conclusion: direct SearchParty calls should not run in the Android-facing refresh path. SearchParty is still promising, but it needs passive instrumentation or a separate debug path that cannot block the user-facing API.

### What To Inspect Next

There are three simpler paths to pursue next.

1. Find the SearchParty session that Find My is already using.

   Creating a new `SPOwnerSession` is not enough, and calling `allBeaconsWithCompletion:` on it can hang the route. Instead, look for the `SPOwnerSession` object that the Find My app already created for itself. The best starting points are the captured Devices and Items list controllers:

   ```text
   _TtGC6FindMy20FMListViewControllerCS_23FMDevicesListDataSourceCS_14FMNoDeviceViewCS_21FMDevicesTerminalView_
   _TtGC6FindMy20FMListViewControllerCS_21FMItemsListDataSourceCS_12FMNoItemViewCS_18FMItemTerminalView_
   ```

   Inspect only nearby fields with names like `ownerSession`, `session`, `repository`, `provider`, `itemsProvider`, `devicesProvider`, `beacon`, or `location`. Do not recursively walk the whole app graph or use Swift `Mirror`; both have already caused hangs.

2. Listen for SearchParty updates instead of asking for all beacons.

   Calling `allBeaconsWithCompletion:` directly is risky because it can block Find My before our timeout runs. A safer approach is to observe the update hooks and caches that Find My already uses:

   ```objc
   setBeaconsChangedBlock:
   setLatestLocationsUpdatedBlock:
   setLocationUpdateBlock:
   allBeaconsCache
   locationCache
   locationSources
   clientObservedBeacons
   ```

   The idea is to let Find My populate its own beacon/location data, then copy a small summary after it changes. This should be less disruptive than forcing a synchronous fetch during an Android API request.

3. Capture providers when Find My creates them.

   We know these classes are loaded:

   ```text
   FindMy.FMDevicesProvider
   FindMy.FMDevicesActionController
   FindMy.FMItemsListDataSource
   FindMyUICore.ItemsProvider
   FindMyUICore.ItemsLocationsProvider
   FindMyUICore.Repository
   FindMyUICore.SessionLive
   ```

   The missing piece is finding the live instances. Instead of searching for them during an API request, swizzle narrow constructors or setter methods and record object identities when Find My builds the Devices or Items views. That gives us stable object references to inspect later, without doing a broad graph scan on the request path.

Active SearchParty calls should go behind a separate debug-only route if needed. They should not run inside the Android-facing refresh path until we know they cannot block.

### 2026-07-06 Passive Capture Follow-Up

I added event-only passive capture hooks for the provider/session construction path:

```text
SPOwnerSession init
FindMy.FMDevicesProvider init
FindMy.FMDevicesActionController init
FindMy.FMItemsListDataSource init
FindMyUICore.ItemsProvider init
FindMyUICore.ItemsLocationsProvider init
FindMyUICore.Repository init
FindMyUICore.SessionLive init
```

I also added hooks for SearchParty callback setters:

```objc
setBeaconsChangedBlock:
setLatestLocationsUpdatedBlock:
setLocationUpdateBlock:
setMaintainedBeaconsChangedBlock:
setMaintainedUnknownBeaconsChangedBlock:
```

The first version tried to inspect nearby KVC fields and ivars as each object was captured. That was still too invasive and caused the Devices refresh to time out. I reduced the capture to event-only metadata: source, selector, class, object pointer, and timestamp. With that reduced version, the Android-facing routes stayed healthy:

```text
friends 8 200
devices 13 200
items 12 200
```

The later restored run did observe passive SearchParty activity from the Apple-created session:

```text
SPOwnerSession init
SPOwnerSession setLocationUpdateBlock:
```

The Android-facing routes stayed healthy after restoring the event-only build:

```text
friends 8 200
devices 13 200
items 12 200
```

No passive provider captures were observed in that run. That suggests one of these is true:

- The target objects were already created before the hooks were installed.
- The Swift classes are not entering Objective-C `init` in a way this hook catches.
- The live Devices/Items path is driven by different provider classes or factory methods.
- Some relevant SearchParty callbacks were set before helper injection or are not set in this UI path.

I also tried the next proposed refinement: doing direct capture work inside the swizzled `FMDevicesListDataSource tableView:cellForRowAtIndexPath:` / `FMItemsListDataSource tableView:cellForRowAtIndexPath:` path. Two versions were tested:

- A field-rich version that captured the returned cell plus direct model/ivar candidates.
- An identity-only version that captured only class names and object pointers for the cell and immediate candidates.

Both versions caused the Devices refresh request to time out at 120 seconds after Friends had already returned successfully. That means direct capture inside `cellForRowAtIndexPath:` is still too invasive for the user-facing route, even without recursive field serialization.

The safe conclusion is to keep `cellForRowAtIndexPath:` swizzles for lightweight route diagnostics only. New capture should happen outside the hot table-cell creation path, or via passive SearchParty/provider setter hooks that only record metadata.

Next refinement: broaden event-only SearchParty setter coverage for methods that are already visible on `SPOwnerSession`, such as `setDeviceEventUpdateBlock:`, `setBeaconAddedBlock:`, `setBeaconRemovedBlock:`, `setOwnerSessionStateUpdatedBlock:`, and `setTagSeparationBeaconsChangedBlock:`. These hooks should continue to record only source, selector, class, object pointer, and timestamp.

### 2026-07-06 Passive SearchParty Setter Expansion

I expanded the event-only `SPOwnerSession` setter hooks to include:

```objc
setBeaconAddedBlock:
setBeaconRemovedBlock:
setClientObservedBeacons:
setDelegatedLocationUpdateBlock:
setDeviceEventUpdateBlock:
setLocationCache:
setLocationSources:
setOwnerSessionStateUpdatedBlock:
setTagSeparationBeaconsChangedBlock:
```

The rebuilt dylib was copied into the repo-built BlueBubbles app and tested through the Android-facing API routes. The routes stayed healthy:

```text
friends count=8 status=200 elapsed=0.0
devices count=13 status=200 elapsed=10.0
items count=12 status=200 elapsed=25.2
```

The new useful signal was `setDeviceEventUpdateBlock:` on the same Apple-created `SPOwnerSession` object that also receives `setLocationUpdateBlock:`:

```text
SPOwnerSession init
SPOwnerSession setLocationUpdateBlock:
SPOwnerSession setDeviceEventUpdateBlock:
```

That makes `setDeviceEventUpdateBlock:` the next best passive SearchParty hook to inspect. It likely receives device-related update events without forcing a synchronous `allBeaconsWithCompletion:` fetch or touching the table-cell creation path.

### 2026-07-06 Passive Setter Block Signatures

I added metadata-only capture for setter values. The helper still passes Apple's original block through unchanged, but it now records the Objective-C block class, pointer, and signature when the setter value is a block.

The rebuilt dylib stayed healthy through the Android-facing routes:

```text
friends count=8 status=200 elapsed=0.1
devices count=13 status=200 elapsed=10.2
items count=12 status=200 elapsed=7.1
```

The useful block signatures are:

```text
setLocationUpdateBlock:     v16@?0@"SPLocationFetchResult"8
setDeviceEventUpdateBlock:  v16@?0@"SPDeviceEventFetchResult"8
```

That gives us the next concrete private classes to inspect:

```text
SPLocationFetchResult
SPDeviceEventFetchResult
```

The next safe step is to inspect those result classes and their ObjC-visible selectors/ivars. If they expose device or beacon arrays, we can wrap the blocks later with matching signatures and copy a bounded summary when Find My naturally delivers an update.

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

## Attempt 8: Visible Cell View-Model Extraction

I continued the `FMDeviceCellViewModel` / `FMItemCellViewModel` path by serializing the visible `FMListTableViewCell` rows instead of returning placeholder row names.

Changes tried:

- Stable UI fallback IDs now use section and row, for example `device:0:0` and `item:0:0`, instead of embedding cell pointer descriptions.
- Text extraction now walks common UIKit/accessibility surfaces only:
  - `subviews`
  - `contentView`
  - `accessibilityElements`
  - `arrangedSubviews`
- The helper probes only bounded direct candidate fields from the visible cell:
  - `viewModel`
  - `cellViewModel`
  - `model`
  - `device`
  - `item`
  - `beacon`
  - `representedObject`
  - `contentConfiguration`
  - `configuration`
- It also inspects only immediate object ivars on the cell for names/classes containing terms like `FMDevice`, `FMItem`, `CellViewModel`, `FMIP`, `SPBeacon`, `Device`, `Item`, `Beacon`, and `Location`.

Verified Android-facing refresh results on this machine:

```text
POST /api/v1/icloud/findmy/devices/refresh -> 9 rows
POST /api/v1/icloud/findmy/items/refresh   -> 9 rows
```

Representative device rows now include visible text:

```text
device:0:0 -> This Mac / With You
device:0:1 -> Home - Now / Home, Now / 0 mi
device:0:2 -> Home - Now or Home - 2 min. ago / Home, Now / 0 mi
device:0:3..8 -> No location found
```

Representative item rows currently show:

```text
item:0:0..8 -> No location found
```

The visible cell classes are still:

```text
_TtGC6FindMy19FMListTableViewCellVS_21FMDeviceCellViewModel_
_TtGC6FindMy19FMListTableViewCellVS_19FMItemCellViewModel_
```

The specialized cell classes only exposed standard cell selectors in the ObjC runtime:

```text
.cxx_destruct
initWithCoder:
initWithStyle:reuseIdentifier:
prepareForReuse
setSelected:animated:
traitCollectionDidChange:
```

No useful backing `FMIPDevice`, `FMIPItem`, `SPBeacon`, location, or stable identifier fields were exposed through direct KVC, direct selectors, or immediate relevant ivars in this pass.

I also tried manually enumerating all sections/rows by calling the active data source methods:

```objc
tableView:numberOfRowsInSection:
tableView:cellForRowAtIndexPath:
```

That path is not safe. It re-entered the swizzled Swift data-source method and crashed Find My with `EXC_BAD_INSTRUCTION`. The triggered stack included:

```text
BBFindMyTableViewNumberOfRows
-[BlueBubblesHelper findMyNumberOfRowsForTableView:dataSource:section:]
-[BlueBubblesHelper findMyListRowsForDataSourceTerm:type:]
```

I removed the manual data-source enumeration and kept the safer visible-cell extraction. After that rollback, device and item refresh completed again with no new crash report from the final safe build.

Current conclusion: visible UI extraction is useful as a fallback and proves the Devices/Items tabs are populated, but it still does not provide true device/item identity or coordinates. The next meaningful path is to capture Apple-created provider/manager objects or bridge Swift private structs inside Swift.

## Current Blockers

1. `FMIPCore` and related frameworks cannot be imported normally from Swift.
2. `FMIPDevice` and `FMIPItem` are Swift structs, not ObjC objects, so ObjC runtime serialization will not work.
3. The direct `@_silgen_name` FMIPManager lifecycle call hangs when run synchronously from the helper route.
4. `SPOwnerSession allBeaconsWithCompletion:` returns zero beacons from a newly created session on this machine.
5. Devices/Items data sources are not activated by the private API request alone, but can be activated reliably with `findmy://devices` and `findmy://items`.
6. The custom Find My segmented control does not expose a standard selected-index setter.
7. Apple Events through `System Events` are too fragile for this workflow because TCC can deny or re-deny Codex automation access.
8. Visible cell view-model classes do not expose useful backing model fields through ObjC selectors/KVC on this macOS build.
9. Manually invoking Devices/Items data-source row methods is unsafe and can crash Find My.

## Next Options

The strongest next paths are:

1. Find and reuse the existing FMIPManager or provider instance from the live Find My object graph instead of constructing a new one.
2. Build a deeper Swift ABI bridge that calls `FMIPManager.devices/items` and serializes inside Swift, with declarations for enough private structs to read fields safely.
3. Use `findmy://devices` and `findmy://items` to force Apple-initialized Devices/Items UI state before the helper refresh runs.
4. Hook provider update callbacks or data-source initialization earlier, then capture the actual Devices/Items provider instance once Find My creates it.
5. Keep visible-cell label extraction as a UI fallback, but do not rely on it for real identity/location data.
6. Continue inspecting `SPOwnerSession` contexts and blocks to discover why `allBeaconsWithCompletion:` returns zero in a fresh session.
