# Find My SearchParty Internal Location Results - 2026-07-06

## Direction

This work is moving away from UI-driven attempts for Devices and Items.

The UI path can reveal useful class names and visible cell models, but it is not a good retrieval strategy because:

- only visible rows are reliably loaded
- scrolling becomes part of correctness
- VNC and window visibility make screenshots unreliable
- UI automation adds System Events and Accessibility fragility unrelated to SearchParty data access

The preferred path is now SearchParty internals:

- `SPOwnerSession`
- `SPBeacon`
- `SPOwnerSessionLocationFetch`
- `SPLocationFetchContext`
- `SPLocationFetchResult`

## Instrumentation Added

The helper now expands the SearchParty location probe to:

- map `SPLocationFetchContext.lastOnlineLocationInfo` entries back to `SPBeacon` identifiers
- inspect `SPLastOnlineLocationInfo` object accessors and ivars for scalar and object values
- record multiple completion results in one probe run
- call direct internal fetch paths:
  - `SPOwnerSessionLocationFetch locationForContext:completion:`
  - `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
  - `SPOwnerSession locationsForBeacons:completion:`
- summarize `SPBeaconManagerSimpleBeaconUpdateInterface.simpleBeacons` when present

The helper intentionally does not switch Find My tabs as part of the SearchParty location probe.

## Route Test

The built BlueBubbles app was launched from the repo app bundle and queried through the Android-facing HTTP surface.

Observed counts:

```text
GET /api/v1/icloud/findmy/friends -> 8 records
GET /api/v1/icloud/findmy/devices -> null
GET /api/v1/icloud/findmy/items -> null
```

SearchParty diagnostics:

```text
captured_owner_session_count: 2
allBeaconsWithCompletion result: __NSSetI
beacon count: 53
context_search_identifier_count: 53
context_search_location_source_count: 12
```

## Last Online Mapping

The real Find My `SPLocationFetchContext` contains:

```text
lastOnlineLocationInfo class:
_TtGCs26_SwiftDeferredNSDictionaryV10Foundation4UUIDCSo24SPLastOnlineLocationInfo_$

lastOnlineLocationInfo count:
10
```

The helper successfully maps entries in that UUID-keyed dictionary back to `SPBeacon` records.

Matched beacons included:

```text
DJ’s MacBook Air
DJ’s iPhone
Qays’s iPhone
DJ’s Apple Watch
qhp-mbp-14-6
```

For `qhp-mbp-14-6`:

```json
{
  "name": "qhp-mbp-14-6",
  "matched_key": "243A7F6E-B4ED-481F-A2E0-54EF9AD6EDB6",
  "identifier_candidates": [
    "243A7F6E-B4ED-481F-A2E0-54EF9AD6EDB6",
    "L:/00006021-001249190E43C01E",
    "226270E0-7B0E-4B41-824D-A8298AB17559"
  ],
  "last_online_class": "SPLastOnlineLocationInfo"
}
```

The decoded `SPLastOnlineLocationInfo` values for `qhp-mbp-14-6` were:

```json
{
  "timestamp": "2026-07-07 03:36:08 +0000",
  "_timestamp": "2026-07-07 03:36:08 +0000",
  "_updatedOn": "2026-07-07 03:36:44 +0000"
}
```

For `Qays’s iPhone`, the same object shape appeared:

```json
{
  "timestamp": "2026-07-07 03:36:12 +0000",
  "_timestamp": "2026-07-07 03:36:12 +0000",
  "_updatedOn": "2026-07-07 03:36:44 +0000"
}
```

## Important Result

`SPLastOnlineLocationInfo` does not appear to be a coordinate container on this machine.

Observed `SPLastOnlineLocationInfo` records exposed:

- `_timestamp`
- `_updatedOn`
- `timestamp`

They did not expose:

- `CLLocation`
- `coordinate`
- `latitude`
- `longitude`
- accuracy
- address
- nested location object

This means `lastOnlineLocationInfo` is currently useful for joining beacon identifiers to last-seen timestamps, but not for coordinates.

## Direct Fetch Attempts

The probe invoked:

```objc
SPOwnerSessionLocationFetch locationForContext:completion:
SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:
SPOwnerSession locationsForBeacons:completion:
```

Observed result:

```text
SPOwnerSession locationsForBeacons:completion: -> __NSDictionary0
result_count: 0
```

The context-based calls remained pending until the probe timed out.

Passive captures continued to show:

```text
SPLocationFetchResult locationsByBeaconIdentifier -> __NSDictionary0
result_count: 0
```

## Simple Beacon Interface

`SPOwnerSession simpleBeaconUpdateInterface` returns:

```text
SPBeaconManagerSimpleBeaconUpdateInterface
```

It exposes:

```text
simpleBeacons
startUpdatingSimpleBeaconsWithContext:completion:
stopUpdatingSimpleBeaconsWithCompletion:
receivedSimpleBeaconUpdates:
receivedSimpleBeaconRemovals:
```

One earlier run showed `_simpleBeacons` populated with 53 `SPInternalSimpleBeacon` objects. A later run showed `_simpleBeacons` as an empty array, so this state is timing/context dependent.

This remains a promising internal target, but the current probe did not extract coordinate data from it.

## Current Interpretation

The state is now split like this:

```text
Inventory:
SPOwnerSession allBeaconsWithCompletion: -> 53 SPBeacon records

Last-seen timestamps:
SPLocationFetchContext lastOnlineLocationInfo -> 10 SPLastOnlineLocationInfo records

Coordinate results:
SPLocationFetchResult locationsByBeaconIdentifier -> observed but empty
```

The missing data is still the coordinate-bearing SearchParty result. It has not been found in `SPBeacon` or `SPLastOnlineLocationInfo`.

## Next Best Step

The next internal path should focus on the already-installed SearchParty update blocks and XPC delivery path rather than the UI.

Recommended next instrumentation:

- wrap `SPOwnerSessionLocationFetch setLocationUpdates:`
- wrap `SPOwnerSessionLocationFetch setLocationUpdateBlock:`
- wrap `SPOwnerSession setLocationUpdateBlock:`
- capture every `SPLocationFetchResult` before Find My receives it
- inspect `SPOwnerSessionLocationFetch receivedUpdatedLocation:` argument objects
- inspect `SPBeaconManagerSimpleBeaconUpdateInterface startUpdatingSimpleBeaconsWithContext:completion:` and its context object

The working hypothesis is that Find My is receiving or building location state through one of these update paths, but the currently observed refresh result has an empty `locationsByBeaconIdentifier`.
