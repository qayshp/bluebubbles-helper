# Find My SearchParty Location Probe - 2026-07-06

## Summary

Follow-up instrumentation tried to obtain item/device locations from the SearchParty location layer after the `SPBeacon` inventory set was working.

The key result: Find My is producing `SPLocationFetchResult` objects, but `locationsByBeaconIdentifier` is empty in the observed runs.

## Routes Used

Server debug routes:

```text
POST /api/v1/icloud/findmy/searchparty/locations/start
POST /api/v1/icloud/findmy/searchparty/locations
```

Helper actions:

```text
debug-findmy-searchparty-locations-start
debug-findmy-searchparty-locations
```

## Confirmed Runtime Types

`SPOwnerSession` exposes:

```text
locationsForBeacons:completion:
locationFetch
locationForContext:completion:
subscribeAndFetchLocationForContext:completion:
requestLiveLocationForUUID:completion:
```

`SPOwnerSessionLocationFetch` exposes:

```text
locationForContext:completion:
subscribeAndFetchLocationForContext:completion:
locationUpdates
setLocationUpdates:
setLocationUpdateBlock:
setSession:
setProxy:
```

`SPLocationFetchContext` exposes:

```text
bundleIdentifier
cachePolicy
lastOnlineLocationInfo
primaryIndexRange
reportDeviceEvents
searchIdentifiers
searchLocationSources
searchPriority
searchTypes
subscribe
```

`SPLocationFetchResult` exposes:

```text
locationsByBeaconIdentifier
```

## Attempts

### `locationsForBeacons:completion:`

The probe first fetched the working beacon set with:

```objc
SPOwnerSession allBeaconsWithCompletion:
```

That returned:

```text
result_class: __NSSetI
beacon_count: 53
element class: SPBeacon
```

Passing that set into:

```objc
SPOwnerSession locationsForBeacons:completion:
```

timed out. No completion result was received within the probe window.

### Generated `SPLocationFetchContext`

The next probe built an `SPLocationFetchContext` with:

```text
bundleIdentifier: com.apple.findmy
cachePolicy: 0
subscribe: true
reportDeviceEvents: false
searchIdentifiers: 53 beacon UUIDs
searchLocationSources: empty
```

It then called:

```objc
SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:
```

That also timed out. The generated context was probably incomplete because `searchLocationSources` and `searchTypes` were not populated.

### `startRefreshing`

The probe calls `startRefreshing` on the captured `SPOwnerSession` before fetching. This did not change the timeout behavior.

## Passive Update Capture

The lower-risk approach was to wrap Find My's own location update blocks and observe the results without changing the result before passing it to Find My.

Wrapped setters:

```text
SPOwnerSession setLocationUpdateBlock:
SPOwnerSessionLocationFetch setLocationUpdates:
SPOwnerSessionLocationFetch setLocationUpdateBlock:
```

The wrapper captures:

```objc
SPLocationFetchResult
SPLocationFetchResult locationsByBeaconIdentifier
```

This worked safely. Devices and Items routes still returned:

```text
devices: 13
items: 12
```

The captured update results were still empty:

```text
source_class: SPLocationFetchResult
selector: locationsByBeaconIdentifier
result_class: __NSDictionary0
result_count: 0
```

This means Find My is receiving location result objects, but those observed result objects do not contain item/device locations.

## Risky Path Removed

A broader attempt to swizzle `SPLocationFetchContext` and `SPBeacon` accessors made the Find My helper fail to stay running. That path was removed.

The retained approach is narrower:

- capture `SPOwnerSessionLocationFetch` setters
- wrap only location update blocks
- keep `SPLocationFetchContext` as diagnostics, not swizzled accessors

## Current Interpretation

The inventory path is solved:

```text
SPOwnerSession allBeaconsWithCompletion: -> NSSet<SPBeacon>
```

The location path is identified but not populated:

```text
SPLocationFetchResult locationsByBeaconIdentifier -> empty dictionary
```

The missing input is likely a real Find My-created `SPLocationFetchContext`, especially populated values for:

```text
searchLocationSources
searchTypes
searchPriority
cachePolicy
```

The generated context with only beacon UUIDs is not enough.

## Next Useful Step

Capture a real non-empty `SPLocationFetchContext` from Find My's own flow.

The most promising hooks are still:

```text
SPOwnerSessionLocationFetch setLastContext:
SPOwnerSessionLocationFetch subscribeAndFetchLocationForContext:completion:
SPOwnerSessionLocationFetch locationForContext:completion:
```

If `setLastContext:` remains absent or nil, the next target is to hook the call site for `subscribeAndFetchLocationForContext:completion:` itself and summarize the context argument before the original method is invoked.
