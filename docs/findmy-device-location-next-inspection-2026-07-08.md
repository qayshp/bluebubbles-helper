# Find My Device location next inspection targets - 2026-07-08

## Recommended direction

For Devices, move away from SearchParty and UI row scraping. Inspect
FindMyiPhone / FMIPCore directly.

## Targets, in order

1. `SiriFindMy`

   Dyld cache path:

   ```text
   /System/Library/PrivateFrameworks/SiriFindMy.framework/Versions/A/SiriFindMy
   ```

   Why: it has higher-level wrappers:

   - `SiriFindMy.FMIPCoreFindDeviceSession`
   - `SiriFindMy.FMIPSyncDeviceProvider`
   - `SiriFindMy.CachingSyncDeviceProvider`
   - `SiriFindMy.FindmyDevice`

   These may expose device records more cleanly than raw FMIPCore.

2. `FMIPCore`

   Dyld cache path:

   ```text
   /System/Library/PrivateFrameworks/FMIPCore.framework/Versions/A/FMIPCore
   ```

   Key classes:

   - `FMIPLocationController`
   - `FMIPRefreshingController`
   - `FMIPManager`
   - `FMIPDataManager`
   - `FMIPRefreshClientResponse`

   This is likely where live/recent device coordinates flow.

3. `FindMyCore` / `FindMyServerInteraction`

   Dyld cache paths:

   ```text
   /System/Library/PrivateFrameworks/FindMyCore.framework/Versions/A/FindMyCore
   /System/Library/PrivateFrameworks/FindMyServerInteraction.framework/Versions/A/FindMyServerInteraction
   ```

   Why: likely request/response and server model plumbing.

## Captured inspection artifacts

Current string-inspection artifacts were captured at:

```text
/Users/qayspoonawala/Codex/2026-07-08/fmipcore-device-location-inspection
```

## Constraint

The framework symlinks are broken on disk because the executable bodies live in
the dyld shared cache. Real decompilation requires extracting from:

```text
/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64
```

## Next practical step

Get a dyld shared cache extractor working, extract `SiriFindMy`, `FMIPCore`,
`FindMyCore`, and `FindMyServerInteraction`, then inspect symbols/types around
`FMIPCoreFindDeviceSession` and `FMIPLocationController`.
