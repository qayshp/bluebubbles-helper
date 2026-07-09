# Find My device location runtime recommendation - 2026-07-09

## Context

The local Find My app shows locations for some Devices, while Items still show no
locations on this Mac. SearchParty Item work is therefore parked for now, and
Device coordinates should be pursued through FindMyiPhone / FMIPCore and the
higher-level FindMyCore/SiriFindMy wrappers.

The arm64e dyld shared cache was successfully extracted with
`/usr/lib/dsc_extractor.bundle` into:

```text
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/dsc-output-arm
```

Derived inspection artifacts are in:

```text
/Users/qayspoonawala/Codex/2026-07-09/device-location-dyld-extract/inspection
```

The x86_64 cache extraction failed validation on the split companion cache, but
that does not indicate the frameworks or symbols are absent.

## Static findings that changed the plan

`FMIPCore` has explicit strings for the device refresh/location path:

- `FMIPManager: didReceiveDevices`
- `%{public}s: received %ld devices`
- `%{public}s: received %ld devices incl. %ld locations asked`
- `%{public}s: received %ld devices but no location asked`
- `FMIPDataManager: updateDevicesLocations device %s location: %{bool}d, crowdsourcedLocation: %{bool}d`
- `FMIPManager: appending realtime location to devices %{private}s`
- `FMIPManager: using realtime location for "%s". Location: %s`
- `FMIPManager: trimming realtime location for "%s" because of coarse location %s`
- `FMIPManager: devices changed after realtime location %@`

`FMIPCore` also exposes location-bearing field and selector names:

- `location`
- `crowdSourcedLocation`
- `ownedDeviceLocation`
- `pairedLocation`
- `separationLocation`
- `lastOnlineLocationInfo`
- `locationsByBeaconIdentifier`
- `setLastOnlineLocationInfo:`
- `setLocation:`

`FindMyCore` exposes a higher-level cached/device location surface:

- `DeviceLocationEntity`
- `DeviceLocationEntityQuery`
- `PublishedLocation`
- `clLocation`
- `fetchLocation`
- `locationForContext:completion:`

`SiriFindMy` remains useful for device discovery and refresh orchestration:

- `FMIPCoreFindDeviceSession`
- `FMIPSyncDeviceProvider`
- `CachingSyncDeviceProvider`
- `FindmyDevice`
- `FMIPManagerWrapperImpl`

## Recommended ordered probes

1. Instrument `FMIPDevice` records returned by the existing device refresh path.
   Dump `location`, `crowdSourcedLocation`, `ownedDeviceLocation`,
   `pairedLocation`, `separationLocation`, and `lastOnlineLocationInfo` for every
   device after refresh.

2. If direct field reads are incomplete, instrument the FMIPCore update path.
   The best target is the path behind
   `FMIPDataManager: updateDevicesLocations device ... location ...
   crowdsourcedLocation ...`, followed by the `FMIPManager: didReceiveDevices`
   flow.

3. Inspect or call the higher-level `FindMyCore.DeviceLocationEntityQuery`
   surface. It may expose `PublishedLocation.clLocation` through the same
   App Intents/cached-location layer used by system surfaces.

4. Keep `SiriFindMy` as the orchestration route, not the first coordinate source.
   Its `FMIPCoreFindDeviceSession` and `FMIPSyncDeviceProvider` names are useful
   for finding devices and triggering refreshes, but static evidence now points
   to FMIPCore/FindMyCore as better coordinate owners.

## Current working assumption

Device coordinates probably enter the local model as one of:

- a live/realtime `FMIPLocation`;
- a crowdsourced `FMIPLocation`;
- an owned-device/self-published location;
- a paired/separation location for multipart accessories;
- a `FindMyCore.PublishedLocation` wrapping a `CLLocation`.

The next runtime work should stay narrow. Avoid broad KVC sweeps inside the
Android-facing refresh route because an earlier broad probe caused refresh
timeouts. Prefer a dedicated debug route or a debug-only helper command that
serializes these exact fields.
