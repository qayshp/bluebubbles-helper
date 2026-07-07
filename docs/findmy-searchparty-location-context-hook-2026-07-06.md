# Find My SearchParty Location Context Hook - 2026-07-06

## Summary

The helper now hooks the SearchParty location fetch methods instead of only observing update blocks:

- `SPOwnerSession subscribeAndFetchLocationForContext:completion:`
- `SPOwnerSession locationForContext:completion:`
- `SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:`
- `SPOwnerSessionLocationFetch locationForContext:completion:`

The hook captures the target class, selector, phase (`before` or `completion`), the `SPLocationFetchContext`, and the `SPLocationFetchResult` when the completion runs. It also records `locationsByBeaconIdentifier` when the result exposes that selector.

This build stayed stable in Find My and BlueBubbles during route tests.

## Build And Test

Built with full Xcode:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcodebuild \
  -workspace FindMy/MacOS-16+/BlueBubblesHelper.xcworkspace \
  -scheme 'BlueBubblesHelper DyLib' \
  -configuration Release \
  ENABLE_USER_SCRIPT_SANDBOXING=NO \
  build
```

Copied the resulting dylib into:

- `packages/server/appResources/private-api/macos11/BlueBubblesFindMyHelper.dylib`
- `packages/server/releases/mac/BlueBubbles.app/Contents/Resources/appResources/private-api/macos11/BlueBubblesFindMyHelper.dylib`

The local built BlueBubbles app was launched from:

```sh
/Users/qayspoonawala/Documents/Codex/2026-06-13/use-the-local-blue-bubbles-installation/bluebubbles-server/packages/server/releases/mac/BlueBubbles.app/Contents/MacOS/BlueBubbles --disable-gpu --relaunch
```

Android-facing Find My API route check:

- `POST /api/v1/icloud/findmy/friends/refresh`: `8`
- `POST /api/v1/icloud/findmy/devices/refresh`: `13`
- `POST /api/v1/icloud/findmy/items/refresh`: `12`
- `POST /api/v1/icloud/findmy/searchparty/locations/start`: `started`
- `POST /api/v1/icloud/findmy/searchparty/locations`: `timed_out`

The helper reported `captured_owner_session_count = 2`.

## Real Find My Context

The real Find My foreground refresh triggered both `SPOwnerSession` and `SPOwnerSessionLocationFetch` calls to:

```objc
subscribeAndFetchLocationForContext:completion:
```

The captured real `SPLocationFetchContext` looked like this at the ivar-summary level:

```json
{
  "_cachePolicy": {
    "class": "__NSCFConstantString",
    "value": "foregroundRefresh"
  },
  "_searchIdentifiers": {
    "class": "Swift.__EmptyArrayStorage",
    "count": 0,
    "element_classes": []
  },
  "_searchPriority": {
    "class": "<nil>"
  },
  "_searchTypes": {
    "class": "Swift.__SwiftDeferredNSArray",
    "count": 6,
    "element_classes": [
      "__NSCFConstantString",
      "__NSCFConstantString",
      "__NSCFConstantString",
      "__NSCFConstantString",
      "__NSCFConstantString",
      "__NSCFConstantString"
    ]
  },
  "_searchLocationSources": {
    "class": "Swift.__SwiftDeferredNSArray",
    "count": 12,
    "element_classes": [
      "__NSCFConstantString"
    ]
  },
  "_lastOnlineLocationInfo": {
    "class": "_TtGCs26_SwiftDeferredNSDictionaryV10Foundation4UUIDCSo24SPLastOnlineLocationInfo_$",
    "count": 10,
    "keys": [
      "<UUID>",
      "<UUID>",
      "<UUID>"
    ]
  },
  "_bundleIdentifier": {
    "class": "__NSCFString",
    "value": "com.apple.findmy"
  }
}
```

Important observation: the real context does **not** use explicit beacon UUIDs in `_searchIdentifiers`. Instead, it has:

- `cachePolicy = foregroundRefresh`
- `searchTypes` populated with 6 string values
- `searchLocationSources` populated with 12 string values
- `lastOnlineLocationInfo` populated with 10 UUID-keyed entries

## Generated Probe Context

The generated probe context created from `allBeaconsWithCompletion:` is different:

```json
{
  "_cachePolicy": {
    "class": "NSConstantIntegerNumber",
    "value": "0"
  },
  "_searchIdentifiers": {
    "class": "__NSFrozenSetM",
    "count": 53,
    "element_classes": [
      "__NSConcreteUUID"
    ]
  },
  "_searchPriority": {
    "class": "<nil>"
  },
  "_searchTypes": {
    "class": "<nil>"
  },
  "_searchLocationSources": {
    "class": "<nil>"
  },
  "_lastOnlineLocationInfo": {
    "class": "<nil>"
  },
  "_bundleIdentifier": {
    "class": "__NSCFConstantString",
    "value": "com.apple.findmy"
  }
}
```

Probe status:

```json
{
  "status": "timed_out",
  "context_search_identifier_count": 53,
  "context_search_location_source_count": 0,
  "completion_results": null,
  "error": null
}
```

## Result Capture

The real subscription completion did run and produced an `SPLocationFetchResult`, but `locationsByBeaconIdentifier` was empty in the captures:

```json
{
  "selector": "locationsByBeaconIdentifier",
  "result_class": "__NSDictionary0",
  "result_count": 0,
  "entries": []
}
```

Observed recent `locationsByBeaconIdentifier` result counts:

```json
[0, 0, 0, 0, 0, 0]
```

## Interpretation

The previous generated probe likely times out because it builds an incomplete `SPLocationFetchContext`. Passing the 53 beacon UUIDs as `_searchIdentifiers` is not enough. Find My's own successful foreground refresh context carries location-source and last-online metadata that the generated context does not currently provide.

The next useful instrumentation step is to capture actual values for:

- `SPLocationFetchContext searchTypes`
- `SPLocationFetchContext searchLocationSources`
- `SPLocationFetchContext lastOnlineLocationInfo`

Then clone or reuse a real foreground-refresh context shape when issuing our own item/device location fetch, instead of constructing one from beacon UUIDs alone.

## Notes

System Events Automation was still denied for this launched BlueBubbles instance:

```text
Not authorized to send Apple events to System Events. (-1743)
```

That did not block the dylib path or these API-route tests, but it does affect UI-driving fallback paths.
