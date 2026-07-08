# Find My SearchParty Beacon Identity Notes

Date: 2026-07-07

## Summary

The SearchParty beacon list is broader than the visible Find My UI. A broad
scan for UUID-like `id` or `identifier` values on objects with a `name` field
mostly returns `SPBeacon`-backed owner records, but those records should not be
treated as a one-to-one list of currently visible Find My Items or Devices.

Some entries in this set do not appear in the visible Find My app. Some names
also appear more than once with different UUIDs. This means display name alone
is not a safe key for location fetches or UI correlation.

## Object Shape Seen

Most records serialized into the API-facing probe shape looked like this:

```json
{
  "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "identifier": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "name": "Example Device Name",
  "prsId": "owner",
  "deviceClass": "beacon",
  "deviceModel": "beacon",
  "rawDeviceModel": "beacon",
  "modelDisplayName": "Find My Item",
  "isConsideredAccessory": true,
  "locationEnabled": true,
  "locationCapable": true,
  "findmy_beacon": {
    "class": "SPBeacon",
    "serialNumber": null,
    "productIdentifier": null,
    "role": null
  }
}
```

This object shape is useful because it proves the record comes from
SearchParty, but it is not enough by itself to prove that the record is a
currently visible Find My row.

## More Useful Identity Fields

Direct `SPBeacon` inspection exposed more useful identity fields for at least
one duplicated device name. Values below are anonymized, but the field formats
are preserved.

```json
{
  "_name": "example-device-name",
  "_identifier": "__NSConcreteUUID",
  "_stableIdentifier": "l:/00000000-0000000000000000",
  "_model": "Mac00,0",
  "_systemVersion": "25F84",
  "_type": "selfBeaconing",
  "_batteryLevel": 0,
  "_accepted": true,
  "_pairingDate": "2026-06-21 07:05:53 +0000",
  "_separationState": "SPTagSeparationStateNone",
  "_beaconSeparationState": 0,
  "_connected": false,
  "_connectionAllowed": false,
  "_safeLocations": {
    "class": "__NSSingleObjectSetI",
    "count": 1,
    "element_classes": ["SPSafeLocation"]
  },
  "_shares": {
    "class": "__NSSetI",
    "count": 4,
    "element_classes": ["SPBeaconShare"]
  }
}
```

The most useful fields were:

| Field | Why it matters |
|---|---|
| `_model` | Identifies the hardware model family, such as a Mac model identifier. |
| `_systemVersion` | Helps distinguish active device records on the current OS generation. |
| `_type` | Indicates the SearchParty role, for example `selfBeaconing`. |
| `_stableIdentifier` | Provides a non-display-name identifier that may be closer to the Find My/device identity than the transient UUID alone. |
| `_safeLocations` | Confirms geofence/safe-location metadata exists, but it is not live location. |
| `SPLocationFetchContext.lastOnlineLocationInfo` | Stronger signal that a UUID participates in recent/last-online location plumbing. |

## Duplicate Name Lesson

One device display name appeared under multiple `SPBeacon` UUIDs. Only one of
those UUIDs had richer evidence from the probes:

```json
{
  "name": "example-device-name",
  "uuid": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "identifier_candidates": [
    "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
    "L:/00000000-0000000000000000",
    "FFFFFFFF-GGGG-HHHH-IIII-JJJJJJJJJJJJ"
  ],
  "spbeacon_fields": {
    "stableIdentifier": "l:/00000000-0000000000000000",
    "model": "Mac00,0",
    "systemVersion": "25F84",
    "type": "selfBeaconing"
  },
  "lastOnlineLocationInfo": {
    "class": "SPLastOnlineLocationInfo",
    "timestamp_format": "2026-07-07 23:02:16 +0000",
    "updatedOn_format": "2026-07-07 23:03:34 +0000"
  }
}
```

This suggests the better ranking for choosing a location target is:

1. Prefer UUIDs present in `SPLocationFetchContext.lastOnlineLocationInfo`.
2. Prefer UUIDs with direct `SPBeacon` ivars such as `_stableIdentifier`,
   `_model`, `_systemVersion`, and `_type`.
3. Treat UUIDs only seen in broad serialized beacon lists as lower confidence.
4. Ignore probe-generated placeholder arguments such as generated search
   identifiers.

## Implication For Location Work

The broad SearchParty beacon set is valuable for discovery, but location fetch
work should not blindly use every UUID in that set. The next probes should carry
forward identity metadata next to each requested UUID so that live-location
results can be correlated against:

- display name,
- UUID,
- stable identifier,
- model,
- system version,
- beacon type,
- whether the UUID appeared in `lastOnlineLocationInfo`.

That should make it easier to avoid choosing the wrong duplicate display-name
record when testing specific devices or items.
