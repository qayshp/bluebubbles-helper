# FindMyiPhone / FMIPCore CLLocation attempt - 2026-07-08

## Goal

Investigate whether the FindMyiPhone / FMIPCore device path can expose a real
`CLLocation` for Find My Devices, now that Items/SearchParty are not useful on
this Mac because the official Find My app does not show any Item locations here.

## Runtime attempt

The helper dylib was modified locally to probe the existing Devices refresh path
for direct location-bearing selectors and fields. The attempted fields included:

- `location`
- `clLocation`
- `currentLocation`
- `deviceLocation`
- `displayLocation`
- `lastLocation`
- `latestLocation`
- `crowdSourcedLocation`

The probe tried to serialize any returned `CLLocation`-like object through the
existing `serializeLocationObject:` helper, which reads `coordinate`,
`horizontalAccuracy`, and `timestamp` when available.

## Result

The broad runtime probe was not stable enough to keep in the Android-facing
refresh path.

Observed behavior:

- `POST /api/v1/icloud/findmy/devices/refresh` timed out.
- The Find My helper socket disconnected roughly 8 seconds into the refresh.
- BlueBubbles treated the disconnected helper as a dylib crash and force-relaunched
  Find My.
- No JSON payload containing a device `CLLocation` was returned.
- No fresh crash report appeared in `~/Library/Logs/DiagnosticReports`, so the
  failure looked like a helper action hang/timeout rather than a native crash
  with an `.ips` report.

The experimental source changes were reverted after the test. The main lesson is
that broad KVC/selector probing inside the Android refresh route is too risky:
some Find My / Swift objects can block, side-effect, or otherwise fail to return
within the Private API transaction timeout.

## Restored state

After reverting the experimental helper source, the dylib was rebuilt and copied
back into the BlueBubbles server resource locations:

- `packages/server/appResources/private-api/macos11/BlueBubblesFindMyHelper.dylib`
- `packages/server/dist/appResources/private-api/macos11/BlueBubblesFindMyHelper.dylib`

The server process was left running. A cached Devices GET request returned HTTP
200 with `data: null`; the Devices refresh route was still timing out after the
repeated Find My restarts, so further probing should avoid the production refresh
route until the helper connection is stable again.

## Static FMIPCore clues

FMIPCore is present on this host as a private framework entry, but the normal
framework directory contains resources and symlinks while the executable body is
served from the dyld shared cache.

The dyld shared cache map includes:

```text
/System/Library/PrivateFrameworks/FMIPCore.framework/Versions/A/FMIPCore
```

Useful FMIPCore class names seen in cache strings:

- `FMIPManager`
- `FMIPManagerConfiguration`
- `FMIPDataManager`
- `FMIPRefreshingController`
- `FMIPLocationController`
- `FMIPDeviceActionsController`
- `FMIPDeviceImageCacheOperation`
- `FMIPDeviceAction`
- `FMIPItemActionsController`
- `FMIPItemAction`
- `FMIPBeaconRefreshingController`
- `FMLocationShifter`
- `FMLocationShiftingRequest`
- `FMIPSafeLocationRefreshingController`

These are better targets than broad row/view-model probing.

## Recommended next step

Do not run the next FMIPCore location probe inside
`refresh-findmy-devices`.

Instead, add a dedicated debug event that:

1. Starts or locates `FMIPManager`.
2. Hooks or inspects `FMIPLocationController` and `FMIPRefreshingController`.
3. Captures callback arguments and result objects from FMIP location refresh
   methods.
4. Serializes only values that are already known to be `CLLocation` or
   `CLLocation` wrappers.

That keeps the Android route stable while narrowing the instrumentation to the
FMIPCore classes most likely to own live/recent device coordinates.
