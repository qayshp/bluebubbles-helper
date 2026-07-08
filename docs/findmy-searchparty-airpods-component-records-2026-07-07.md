# Find My SearchParty AirPods Component Records

Date: 2026-07-07

## Summary

Recent generation AirPods can appear in SearchParty as multiple `SPBeacon`
records for one visible Find My accessory. The records seen locally used simple
component names such as:

- `left`
- `right`
- `single`

The user confirmed this matches a set of recent generation AirPods where Find
My can locate the case, left bud, and right bud.

This is important because one visible Find My item can fan out into multiple
SearchParty beacon records. Code that assumes one display name maps to one
UUID will choose the wrong target for componentized accessories.

## Record Shape

The AirPods component records were serialized as `SPBeacon` owner records:

```json
{
  "name": "left",
  "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "identifier": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
  "class": "SPBeacon",
  "prsId": "owner",
  "deviceClass": "beacon",
  "deviceModel": "beacon",
  "rawDeviceModel": "beacon",
  "modelDisplayName": "Find My Item",
  "locationEnabled": true,
  "locationCapable": true,
  "isConsideredAccessory": true,
  "batteryStatus": "Unknown",
  "lostModeEnabled": false,
  "thisDevice": false,
  "isMac": false,
  "findmy_beacon": {
    "class": "SPBeacon",
    "serialNumber": "HXXXXXXXXXXX",
    "productIdentifier": null,
    "role": "<SPBeaconRole: 0x...>"
  }
}
```

The `serialNumber` field is a strong clue for component matching. Unlike many
generic beacon rows where serial data is missing, these component records had
serial-number-like values for the individual AirPods parts.

## Component Examples

Values below are anonymized, but the formats and relationships are preserved.

| Component name | Per-component UUID | Stable identifier family | Serial number shape |
|---|---|---|---|
| `left` | `AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE` | `HELE:/...~#0` | `HXXXXXXXXXXX` |
| `right` | `BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF` | `HELE:/...~#1` | `HXXXXXXXXXXX` |
| `single` | `CCCCCCCC-DDDD-EEEE-FFFF-000000000000` | `HELE:/...~#0` | `HXXXXXXXXXXX` |

The `left` and `right` examples had `HELE:/...` stable identifiers and a shared
secondary UUID in their candidate lists. That shared UUID should be treated as a
group/product/account-level identity candidate, not as the individual component
beacon UUID.

## Identifier Candidates

For a componentized accessory, the candidates looked like this:

```json
{
  "name": "left",
  "identifier_candidates": [
    "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
    "HELE:/...~#0",
    "GGGGGGGG-HHHH-IIII-JJJJ-KKKKKKKKKKKK"
  ]
}
```

```json
{
  "name": "right",
  "identifier_candidates": [
    "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF",
    "HELE:/...~#1",
    "GGGGGGGG-HHHH-IIII-JJJJ-KKKKKKKKKKKK"
  ]
}
```

The first UUID is the per-component `SPBeacon.identifier`. The `HELE:/...`
value is the stable identifier. The repeated trailing UUID is a shared identity
candidate and should not be assumed to be the component's own beacon UUID.

## How To Recognize These Records

AirPods-style component records can be recognized by the combination of:

- `class` or `findmy_beacon.class` equal to `SPBeacon`,
- `isConsideredAccessory: true`,
- `deviceClass: beacon`,
- `modelDisplayName: Find My Item`,
- component-like `name` values such as `left`, `right`, or `single`,
- serial-number-like `findmy_beacon.serialNumber`,
- `SPBeaconRole` present on `findmy_beacon.role`,
- `HELE:/...` stable identifiers for at least some components,
- shared secondary UUIDs across components.

No single field is enough on its own. The component name is especially weak
because it is generic. The serial number, stable identifier, and candidate UUID
relationships are the useful evidence.

## Location Correlation Guidance

For live-location or last-online probes, treat componentized accessories
differently from single-record items:

1. Group records by shared stable-identifier family and shared secondary UUIDs.
2. Preserve the component `name` (`left`, `right`, `single`) next to each
   requested UUID.
3. Preserve `serialNumber` next to each requested UUID.
4. Prefer the first UUID in `identifier_candidates` as the component beacon
   UUID.
5. Do not collapse multiple component records into one display-name row before
   location correlation.
6. If a result comes back keyed by UUID, map it back to the component record
   before presenting it.

For Android/API output, this likely means an AirPods accessory may need a parent
record with child component locations, or separate records that share a parent
identity. Returning only one flattened `name` can hide which component has the
location.

## Open Questions

- Whether `HELE` maps to a specific Apple internal accessory family name.
- Whether the `single` component always represents the case for AirPods models
  that support case finding.
- Whether the shared trailing UUID is always product/group identity or can vary
  by account/share state.
- Whether `SPBeaconRole` exposes a semantic role accessor that would directly
  identify `left`, `right`, or case instead of relying on the display `name`.
