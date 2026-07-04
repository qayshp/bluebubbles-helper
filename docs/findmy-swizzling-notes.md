# Find My Swizzling Notes

## Why the copied swizzle code was removed

The original Find My dylib was cloned from the Messages helper, so it inherited `ZKSwizzle` and several method hooks that were designed for Messages and older FMF behavior.

That approach made sense in the Messages helper because the dylib needed passive observation inside Apple's process. For example, the copied code hooked `FMFSessionDataManager setLocations:` so it could notice when Apple's old FMF location cache changed and emit `new-findmy-location` socket events.

The cleaned Find My helper is currently request-driven instead:

1. The server sends `refresh-findmy-friends`.
2. The helper resolves `FindMyLocateSession`.
3. The helper calls `getFriendsSharingLocationsWithMeWithCompletion:`.
4. The helper refreshes each handle with `startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:`.
5. The helper reads cached `FMLLocation` objects and replies to the transaction.

Because the helper now asks Find My for current data when requested, it does not need broad runtime method interception for the basic refresh path. Removing swizzling also removes copied Messages-specific hooks, old FMF hooks, and the extra `ZKSwizzle` machinery from the Find My target.

## When swizzling may become useful again

Swizzling may be useful if the Find My helper needs live push-style behavior instead of explicit refresh requests.

Potential benefits:

- Emit `new-findmy-location` as soon as Find My receives an update.
- Reduce polling and request latency.
- Mirror Find My cache updates into BlueBubbles immediately.
- Inspect callback block signatures and object shapes during runtime.
- Capture internal refresh failures, permission issues, or entitlement errors.
- Emit active location-sharing device changes.
- Observe friendship/share-state changes.

The tradeoff is fragility. These are private framework methods, so selector names, callback signatures, object lifetimes, and call timing can change between macOS versions.

## Candidate methods

Highest-value `FindMyLocateSession` candidates:

- `setLocationUpdateCallback:`
- `locationUpdateCallback`
- `startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:`
- `startRefreshingLocationForHandles:priority:isFromGroup:completion:`
- `cachedLocationForHandle:includeAddress:`
- `getFriendsSharingLocationsWithMeWithCompletion:`
- `startUpdatingFriendsWithInitialUpdates:completion:`
- `stopUpdatingFriendsWithCompletion:`
- `setFriendshipUpdateCallback:`
- `friendshipUpdateCallback`
- `startMonitoringActiveLocationSharingDeviceChangeWithCompletion:`
- `getActiveLocationSharingDeviceWithCompletion:`

Lower-priority sharing/friendship candidates:

- `canShareLocationWithHandle:isFromGroup:completion:`
- `friendshipStateWithHandle:isFromGroup:completion:`
- `sendFriendshipInviteToHandle:isFromGroup:completion:`
- `sendFriendshipOfferToHandles:expiration:isFromGroup:completion:`
- `stopSharingLocationWith:isFromGroup:completion:`

If swizzling is reintroduced, start narrowly with callback wrapping around `setLocationUpdateCallback:` and diagnostic logging around the two `startRefreshingLocation...` selectors. That provides live/update visibility without hooking every cache read.
