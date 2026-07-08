# Find My SearchParty non-empty signal probe - 2026-07-07

## Goal

The previous coordinate probes often produced `nil`, empty arrays, or empty dictionaries before we reached any latitude/longitude-bearing object. This pass adds a broader signal detector so the helper can report useful SearchParty state even when coordinates are absent.

The detector records:

- non-empty dictionaries, arrays, and sets;
- nested non-empty results from known SearchParty selectors;
- coordinate-looking objects or dictionaries when present.

## Helper instrumentation

`BlueBubblesHelper.m` now includes `searchPartySignalSnapshotForValue:path:`. It is intentionally conservative:

- it recurses through `NSDictionary`, `NSArray`, and `NSSet`;
- it does not use the generic child helper for arbitrary objects, because that helper can return the object itself and would create false positives;
- for arbitrary objects, it probes selected SearchParty-style accessors such as `locationsByBeaconIdentifier`, `lastOnlineLocationInfo`, `searchLocationSources`, `locationCache`, `deviceEvents`, `items`, `devices`, and `beacons`;
- it caps recursion depth and result counts so debug routes remain bounded.

Signal snapshots are attached to SearchParty location probe results under a `signal` field.

## Build and runtime check

Built with full Xcode by overriding `DEVELOPER_DIR`, leaving global `xcode-select` unchanged:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace FindMy/MacOS-16+/BlueBubblesHelper.xcworkspace \
  -scheme 'BlueBubblesHelper DyLib' \
  -configuration Release \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/BlueBubblesHelper-codex-signal \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

`ENABLE_USER_SCRIPT_SANDBOXING=NO` was needed because the CocoaPods manifest script hit Xcode's user-script sandbox before helper compilation.

The rebuilt dylib was copied into the BlueBubbles server resource path and the dev Electron server was relaunched. The Find My helper connected successfully.

## Observed non-empty SearchParty state

Calling:

```sh
curl -X POST 'http://localhost:1234/api/v1/icloud/findmy/searchparty/locations/last-online-identifiers?password=...'
```

produced a `captured_location_context_summary.signal` object:

```json
{
  "non_empty_path_count": 2,
  "non_empty_paths": [
    {
      "path": "SPLocationFetchContext.lastOnlineLocationInfo",
      "class": "_TtGCs26_SwiftDeferredNSDictionaryV10Foundation4UUIDCSo24SPLastOnlineLocationInfo_$",
      "count": 10
    },
    {
      "path": "SPLocationFetchContext.searchLocationSources",
      "class": "Swift.__SwiftDeferredNSArray",
      "count": 12
    }
  ],
  "root_class": "SPLocationFetchContext"
}
```

That confirms this route has live SearchParty state even when no coordinates are returned.

The same context also reported:

- `lastOnlineLocationInfo_count`: `10`
- `searchLocationSources_count`: `12`
- `searchIdentifiers_count`: `0`
- `searchTypes_count`: `6`
- `cachePolicy`: `foregroundRefresh`
- `subscribe`: `true`

The visible source names included:

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

## Android-facing API check

After the rebuild:

- `/api/v1/icloud/findmy/friends` returned status `200` with 8 records.
- `/api/v1/icloud/findmy/devices` returned status `200` with `data: null`.
- `/api/v1/icloud/findmy/items` returned status `200` with `data: null`.

The server log still reports:

```text
Cannot fetch FindMy devices on macOS Sequoia or later.
Cannot fetch FindMy items on macOS Sequoia or later.
```

So this instrumentation improves SearchParty visibility, but it does not yet wire devices/items into the Android-facing routes.

## Current interpretation

`SPLocationFetchContext.lastOnlineLocationInfo` remains the best currently observed non-empty SearchParty object for recent item/device state. It contains timestamps keyed by beacon/device UUIDs, but the `SPLastOnlineLocationInfo` entries inspected here still expose timestamps rather than coordinates.

The next useful probe is to keep using this non-empty context as an anchor and inspect the XPC completion paths that should eventually populate `SPLocationFetchResult`, especially results from:

- `latestLocationsForIdentifiers:fetchLimit:sources:completion:`
- `locationForContext:completion:`
- `delegatedLocationForContext:completion:`
