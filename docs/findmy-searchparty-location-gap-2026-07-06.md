# Find My SearchParty Location Gap - 2026-07-06

## Summary

`SPOwnerSession allBeaconsWithCompletion:` successfully returns the item/device inventory as a populated `NSSet` of `SPBeacon` objects, but those beacon records do not include live location data.

The observed beacon record shape includes:

- user-visible item name
- beacon UUID
- stable identifier
- serial number
- `SPBeaconRole`
- item/device classification
- coarse battery fields

The observed beacon record shape does not include:

- latitude
- longitude
- horizontal accuracy
- vertical accuracy
- timestamp
- address
- `CLLocation`
- any nested location result object

## Interpretation

The SearchParty data appears split into at least two layers:

1. Inventory layer: `SPBeacon`
2. Location layer: likely `SPLocationFetchResult`

The successful beacon probe proves that the inventory layer is available through:

```objc
SPOwnerSession allBeaconsWithCompletion:
```

The location layer has not been populated by that call. This is why the async beacon set can identify `SPBeacon` records but cannot yet return where those beacons are.

## Evidence

The passive `SPOwnerSession` snapshot showed empty or nil location-adjacent state:

```text
allBeacons: nil
allBeaconsCache: nil
locationCache: dictionary count 0
locationSources: set count 0
clientObservedBeacons: set count 0
```

The async inventory fetch returned populated beacon data:

```text
allBeaconsWithCompletion: result_class __NSSetI
beacon_count: 53
serialized_count: 53
element class: SPBeacon
```

The callback and result types seen during swizzling indicate a separate location path:

```text
setLocationUpdateBlock:
block signature: v16@?0@"SPLocationFetchResult"8
SPLocationFetchResult locationsByBeaconIdentifier
```

`SPLocationFetchResult locationsByBeaconIdentifier` was observed, but returned empty dictionaries during the current test run.

## Practical Consequence

The current SearchParty beacon probe can answer:

- what items/devices exist
- what their beacon identifiers look like
- what serial and stable identifiers they have
- which records are likely owner-owned items

It cannot yet answer:

- current item/device coordinates
- last location timestamp
- location accuracy
- stale/live location status

Any production item/device route built from only `SPBeacon` would be identity-complete but location-empty.

## Next Target

The next step is to trigger or locate the SearchParty location fetch/update path that populates `SPLocationFetchResult locationsByBeaconIdentifier`.

The likely join strategy is:

1. Fetch inventory with `allBeaconsWithCompletion:`.
2. Fetch locations through a SearchParty location method or callback path.
3. Read `SPLocationFetchResult locationsByBeaconIdentifier`.
4. Join location records back to `SPBeacon` records by beacon UUID or stable identifier.

The next instrumentation should inspect:

- methods on `SPOwnerSession` that include `Location`, `Locations`, `Fetch`, `Refresh`, or `BeaconIdentifier`
- argument and completion block signatures for those methods
- `SPLocationFetchResult` fields beyond `locationsByBeaconIdentifier`
- any non-empty location dictionary after Find My has loaded the Items or Devices views

## Working Hypothesis

`SPBeacon` is the stable inventory model. `SPLocationFetchResult` is the location result model. `allBeaconsWithCompletion:` gets the former, not the latter.

The missing piece is not an absent identifier; it is an untriggered or uncaptured location fetch path.

## Host-Specific Update - 2026-07-07

The development Mac used for this work does not show locations for any Items in the Find My app, while other Macs on the same Apple ID and iPhone do show at least some Item locations.

That means empty Item location results on this host may reflect true local Find My/SearchParty state rather than only an instrumentation gap. The helper can see Item identity and freshness state, but the local app itself is not materializing Item coordinates.

See `findmy-local-item-location-gap-2026-07-07.md` for the focused note.
