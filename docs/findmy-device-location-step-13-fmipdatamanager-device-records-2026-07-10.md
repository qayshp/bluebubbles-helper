# Find My Device Location Step 13: App-Owned FMIPDataManager Device Records

Date: 2026-07-10

## Summary

The useful device-location path is the app-owned Find My object graph, not a newly-created `FMIPManager` and not UI cell scraping:

`FMDevicesListDataSource -> mediator -> devicesProvider -> fmipManager -> dataManager -> devices`

The `devices` value is a `Swift.Array<FMIPCore.FMIPDevice>`. Each element can contain an optional `location` field. When present, the path to coordinates is:

`FMIPDevice.location -> FMIPCore.FMIPLocation.location -> CLLocation`

## New helper action

Added helper action:

`debug-findmy-devices-datamanager-devices`

Added C bridge export:

`BlueBubblesFindMyCopyDevicesDataManagerDevicesSummary`

The action returns a compact payload only. This is intentionally separate from the broader provider-model diagnostics because that route can exceed the helper IPC/chunking limits and produce JSON decode failures.

## Payload path

The compact device records are returned at:

`diagnostics.devices_data_manager.devices_data_manager_devices.devices_compact.devices`

Parent count fields:

```json
{
  "device_count": 37,
  "devices_returned": 37
}
```

Each device record currently preserves these field formats when present:

```json
{
  "index": 0,
  "type": "FMIPCore.FMIPDevice",
  "identifier": "opaque-string",
  "name": "Example Device",
  "displayName": "MacBook Pro",
  "model": "Mac14_6-silver",
  "rawDeviceModel": "Mac14_6-silver",
  "systemVersion": "26.x",
  "batteryLevel": 0.75,
  "batteryStatus": {
    "type": "FMIPCore.FMIPBatteryStatus",
    "display_style": "enum"
  },
  "deviceConnectedState": {
    "type": "FMIPCore.FMIPDeviceConnectedStateType",
    "display_style": "enum"
  },
  "discoveryIdentifier": "UUID-string",
  "baIdentifier": "UUID-string",
  "beaconType": {
    "type": "FMIPCore.FMIPBeaconType",
    "display_style": "enum"
  },
  "category": "MacBookPro",
  "address": {
    "type": "FMIPCore.FMIPAddress",
    "label": "Example Address",
    "mapItemFormattedAddress": "Example Address",
    "mediumAddressModern": "Example Address",
    "largeAddressModern": "Example Address",
    "locality": "Example City",
    "administrativeArea": "Example State",
    "countryCode": "US"
  },
  "locationPresent": true,
  "location": {
    "type": "FMIPCore.FMIPLocation",
    "location": {
      "class": "CLLocation",
      "latitude": 0,
      "longitude": 0,
      "horizontal_accuracy": 35,
      "vertical_accuracy": 0,
      "timestamp": "2026-07-10 17:48:23 +0000"
    },
    "floor": {
      "type": "Swift.Double",
      "display_style": "<nil>",
      "value": 0
    },
    "isInaccurate": {
      "type": "Swift.Bool",
      "display_style": "<nil>",
      "value": false
    },
    "isLocationFinished": {
      "type": "Swift.Bool",
      "display_style": "<nil>",
      "value": false
    },
    "isOld": {
      "type": "Swift.Bool",
      "display_style": "<nil>",
      "value": false
    },
    "locationType": {
      "type": "FMIPCore.FMIPLocationType",
      "display_style": "enum"
    }
  },
  "crowdSourcedLocationPresent": false,
  "historicalLocationsPresent": false,
  "safeLocationsCount": 0
}
```

## Test evidence

Current local test against the new compact route:

`POST /api/v1/icloud/findmy/devices/debug/datamanager-devices`

Result:

- HTTP 200
- Response time: about 5.7 seconds
- Response size: about 42 KB
- `device_count`: 37
- `devices_returned`: 37
- Devices with non-null `FMIPDevice.location`: 12

The previous broad provider-model route returned useful data, but the payload was too large and the server attempted to parse split JSON chunks. The compact route avoids that failure by returning only traversal metadata, counts, and device records.

## Notes

- This path does not create or retain a new `FMIPManager`.
- This path does not call the unsafe `FMIPManager.devices` accessor on a locally-created manager.
- This path is independent of visible UI cells and does not depend on scrolling the Find My list.
- Offline devices remain in the array with `locationPresent: false`.
