# Find My device location step 3 - FindMyCore query discovery - 2026-07-09

## Goal

Try the third recommended Device-location probe:

> Inspect or call the higher-level `FindMyCore.DeviceLocationEntityQuery`
> surface. It may expose `PublishedLocation.clLocation` through the same App
> Intents/cached-location layer used by system surfaces.

## Implementation

The helper now explicitly checks runtime availability for:

- `FindMyCore.DeviceLocationEntity`
- `FindMyCore.DeviceLocationEntityQuery`
- `FindMyCore.PublishedLocation`
- `FindMyCore.Location`

The Swift bridge adds these class names to `BlueBubblesFindMySwiftProbe()`.

The Objective-C device refresh diagnostics add:

```text
findmycore_location_runtime
```

This uses `compactRuntimeDiagnosticsForClassNames:matchingTerms:methodLimit:ivarLimit:`
with terms:

- `location`
- `fetch`
- `query`
- `device`
- `clLocation`
- `published`

## Why this is discovery first

Static inspection found strong `FindMyCore` clues:

- `DeviceLocationEntity`
- `DeviceLocationEntityQuery`
- `PublishedLocation`
- `clLocation`
- `fetchLocation`
- `locationForContext:completion:`

However, these are Swift/AppIntents-heavy types. Without a public or ObjC-visible
initializer/method signature, directly calling them blindly is more likely to
crash or hang than the FMIPCore device-field probes. This step records whether
the types are present in the injected Find My process and what method/ivar names
are visible at runtime.

## Build result

Built with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -workspace 'FindMy/MacOS-16+/BlueBubblesHelper.xcworkspace' \
  -scheme 'BlueBubblesHelper DyLib' \
  -configuration Release \
  -derivedDataPath 'FindMy/MacOS-16+/build' \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

Result:

```text
** BUILD SUCCEEDED **
```

## Next check

Run the helper through the server and inspect `findmycore_location_runtime`.

If `DeviceLocationEntityQuery` is available and exposes a zero-argument init plus
location/fetch methods, the next step is a dedicated debug route that calls only
that query path. If it is absent or has no usable ObjC-visible methods, continue
with FMIPManager/FMIPDevice field and setter evidence.
