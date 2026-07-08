# Find My location work summary and next steps - 2026-07-08

## Current goal

Get reliable Find My location data into BlueBubbles, especially Device
locations. Item/SearchParty work remains valuable, but this Mac currently does
not show any Item locations in Apple's Find My app, so it is not a good positive
test host for Item coordinates.

## What is already working

### Friends

Friends are working through the `FindMyLocateObjCWrapper` / `FindMyLocateSession`
path.

The Android-facing friends route has returned populated friend records, and the
Android app was confirmed to show friend locations after the earlier route fix.

Relevant API surface:

- `FindMyLocateSession`
- `getFriendsSharingLocationsWithMeWithCompletion:`
- `startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:`
- `cachedLocationForHandle:includeAddress:`
- `FMLLocation`

### SearchParty identity records

The helper can get SearchParty owner records:

- `SPOwnerSession`
- `allBeaconsWithCompletion:`
- `SPBeacon` records
- AirPods component relationships via `stableIdentifier` values such as
  `left`, `right`, and `single`
- Beacon/device identity fields such as UUID, name, model, system version,
  serial number, role, product identifier, and stable identifiers

This is enough to enumerate many Items/Beacons and understand component
relationships, but not enough to return coordinates.

## What is not working yet

### Items on this Mac

The development Mac does not show locations for any Items in Apple's Find My UI.
Other Apple devices on the account do show at least some Item locations.

That means empty Item coordinate results in the helper are currently ambiguous:
the helper may be observing the same broken or incomplete local state as Apple's
app on this Mac.

Known local SearchParty facts:

- Item/beacon identity records exist.
- `SPLocationFetchContext.lastOnlineLocationInfo` can be non-empty.
- `SPLocationFetchContext.searchLocationSources` can be non-empty.
- `SPLocationFetchContext.searchIdentifiers` can become non-empty.
- `SPLocationFetchResult.locationsByBeaconIdentifier` has remained empty.
- No Item `CLLocation`, latitude, longitude, or coordinate-bearing child object
  has surfaced.

### Devices

The official Find My app can show some Device locations on this Mac, so Devices
are the best current coordinate-positive target.

The BlueBubbles Android-facing Devices GET route has returned HTTP 200 with
`data: null`, and the Devices refresh route has been fragile. Broad runtime
probing inside the refresh path caused helper transaction timeouts and Find My
helper restarts.

The failed FMIPCore `CLLocation` attempt tried direct fields/selectors such as:

- `location`
- `clLocation`
- `currentLocation`
- `deviceLocation`
- `displayLocation`
- `lastLocation`
- `latestLocation`
- `crowdSourcedLocation`

That broad probing should not be repeated inside `refresh-findmy-devices`.

## SearchParty findings

### Important SearchParty classes and objects

Confirmed useful objects:

- `SPOwnerSession`
- `SPOwnerSessionLocationFetch`
- `SPBeaconManagerSimpleBeaconUpdateInterface`
- `SPLocationFetchContext`
- `SPLocationFetchResult`
- `SPLastOnlineLocationInfo`
- `SPDeviceEventFetchResult`
- `FMXPCSession`
- `__NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol`

Lower-layer object path:

```text
SPOwnerSessionLocationFetch
  -> FMXPCSession
  -> __NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol
```

Most promising SearchParty XPC method seen:

```text
latestLocationsForIdentifiers:fetchLimit:sources:completion:
```

Other relevant proxy methods:

- `locationForContext:completion:`
- `delegatedLocationForContext:completion:`
- `beaconsToMaintainWithCompletion:`
- `allBeaconsWithCompletion:`

### SearchParty source list

`searchLocationSources` appears to be routing/fetch configuration, not payload
data. Observed source names included:

- `connectionEvent`
- `connectionmaintenance`
- `disconnection`
- `harvesterNetwork`
- `harvesterOnDiskNearOwner`
- `harvesterOnDiskWild`
- `intentLocationUpdate`
- `intentResponse`
- `localReductiveFilter`
- `pairingLocationManager`
- `selfPublish`
- `ownedDeviceLocation`

The `ownedDeviceLocation` source is probably relevant to Devices, but this has
not yet produced coordinates through SearchParty probes.

### SearchParty key material problem

System `searchpartyd` logs showed a large volume of keyMap/subsequence messages
on this Mac, especially:

```text
Did not find subsequence File URL for <private>
```

The preserved log is:

```text
/Users/qayspoonawala/Codex/2026-07-08/findmy-searchparty-tmp-preserve/private/tmp/searchparty-keymap-15m-20260707-231756.log
```

This supports the current view that Item/SearchParty location materialization may
be locally broken on this Mac.

## FMIPCore / FindMyiPhone findings

Device locations should now be pursued through FindMyiPhone / FMIPCore rather
than SearchParty first.

The framework directories are mostly dyld-cache stubs. The executable bodies
live in:

```text
/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64
```

Current string-inspection artifacts:

```text
/Users/qayspoonawala/Codex/2026-07-08/fmipcore-device-location-inspection
```

Most relevant dyld-cache images:

```text
/System/Library/PrivateFrameworks/SiriFindMy.framework/Versions/A/SiriFindMy
/System/Library/PrivateFrameworks/FMIPCore.framework/Versions/A/FMIPCore
/System/Library/PrivateFrameworks/FindMyCore.framework/Versions/A/FindMyCore
/System/Library/PrivateFrameworks/FindMyServerInteraction.framework/Versions/A/FindMyServerInteraction
```

### Why SiriFindMy is the first target

`SiriFindMy` exposes higher-level wrappers that may be easier to inspect or call
than raw FMIPCore:

- `SiriFindMy.FMIPCoreFindDeviceSession`
- `SiriFindMy.FMIPSyncDeviceProvider`
- `SiriFindMy.CachingSyncDeviceProvider`
- `SiriFindMy.FindmyDevice`
- `SiriFindMy.FMIPManagerWrapperImpl`

These names sound like exactly the bridge between an intent/session layer and
FMIPCore device records.

### Why FMIPCore is the second target

FMIPCore contains the lower-level device and refresh controllers:

- `FMIPManager`
- `FMIPManagerConfiguration`
- `FMIPDataManager`
- `FMIPRefreshingController`
- `FMIPLocationController`
- `FMIPRefreshClientResponse`
- `FMIPDeviceActionsController`
- `FMIPDeviceAction`
- `FMLocationShifter`
- `FMLocationShiftingRequest`

`FMIPLocationController` and `FMIPRefreshingController` are the best raw
FMIPCore hook/inspection targets.

## Tooling lessons

From prior docs and memory:

- Start with dyld cache maps and cache-wide strings.
- Keep text evidence in the repo or in `$HOME/Codex/...`, not only `/tmp`.
- Do not treat extraction/class-dump failure as proof that an API is absent.
- `class-dump` is weak for these Swift-heavy private frameworks.
- `ktool` can help with dependencies and structure when extraction succeeds, but
  it did not recover rich Swift declarations in prior attempts.
- `DyldExtractor` and Apple's `dsc_extractor.bundle` have both been useful but
  fragile, depending on OS/cache/tool versions.
- Avoid zsh variables named `path`; they can break `PATH`.

## Suggested next steps

### 1. Get dyld extraction working again

Extract these images from the x86_64 dyld shared cache:

```text
SiriFindMy
FMIPCore
FindMyCore
FindMyServerInteraction
```

Use whatever works locally:

- `dyld_shared_cache_util`, if available
- `/usr/lib/dsc_extractor.bundle`, if usable on this host
- DyldExtractor
- ktool or other Mach-O tools
- strings/demangling as fallback

Preserve command outputs and extracted symbol/type evidence under the repo or
`$HOME/Codex/...`.

### 2. Inspect SiriFindMy before raw FMIPCore

Look for method names, Swift symbols, initializers, properties, and callback
types around:

- `FMIPCoreFindDeviceSession`
- `FMIPSyncDeviceProvider`
- `CachingSyncDeviceProvider`
- `FindmyDevice`
- `FindmyDevice.Builder`
- `FMIPManagerWrapperImpl`

The goal is to find an already-normalized Device model or provider API that
returns records with coordinates or `CLLocation`.

### 3. Inspect FMIPCore location/refresh classes

If SiriFindMy is insufficient, inspect:

- `FMIPLocationController`
- `FMIPRefreshingController`
- `FMIPManager`
- `FMIPDataManager`
- `FMIPRefreshClientResponse`

Look for:

- `CLLocation`
- latitude/longitude fields
- device arrays
- refresh result objects
- completion block signatures
- publisher/async sequence names
- cache/update methods

### 4. Add a dedicated debug route, not Android refresh probing

Do not put broad runtime introspection back into:

```text
refresh-findmy-devices
```

Instead, add a separate debug action that:

1. Loads or locates the target class.
2. Captures a very small bounded method/ivar surface.
3. Invokes one candidate method at a time.
4. Times out quickly.
5. Returns compact JSON.

This avoids breaking the Android-facing route while still allowing deeper
runtime exploration.

### 5. Runtime hook only specific candidate methods

Once decompilation/string inspection identifies a likely method, hook that exact
method or callback. Good candidate classes are:

- `SiriFindMy.FMIPCoreFindDeviceSession`
- `SiriFindMy.FMIPSyncDeviceProvider`
- `FMIPCore.FMIPLocationController`
- `FMIPCore.FMIPRefreshingController`

Avoid broad KVC on arbitrary Swift objects.

### 6. Keep Items/SearchParty parked until this Mac shows Item locations

Items should not be the main coordinate target on this Mac until Apple's Find My
app itself shows Item locations locally.

If Item work resumes, the best SearchParty lead remains:

```text
latestLocationsForIdentifiers:fetchLimit:sources:completion:
```

But it should be retried with one identifier and carefully preserved source
objects, not with all identifiers/sources at once.

## Bottom line

For the next session, pursue Devices through `SiriFindMy` first, then FMIPCore.
SearchParty has taught us a lot about Item/beacon identity and lower-layer XPC
shape, but it has not produced coordinates on this Mac. The best chance for real
Device coordinates is to inspect and narrowly hook the FindMyiPhone/FMIPCore
device refresh stack that Apple's own Find My UI is already using successfully
for some devices.
