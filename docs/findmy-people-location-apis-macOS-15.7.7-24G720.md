# Find My People-Location APIs on macOS 15.7.7 build 24G720

Date: 2026-07-04
Host: macOS 15.7.7 build 24G720

## Summary

Yes: the Find My people-location API names seen in `docs/findmy-framework-inspection-macOS-26.5.2-25F84.md` also exist in the macOS 15.7.7 build 24G720 dyld cache.

The strongest evidence is:

- `FindMyLocateObjCWrapper.framework` is present in both local dyld cache maps.
- All requested Objective-C-facing class names appear in cache strings on both x86_64 and arm64e.
- All requested selectors appear in cache strings on both x86_64 and arm64e.
- The macOS 15 string hits include Objective-C method forms such as `-[FindMyLocateSession cachedLocationForHandle:includeAddress:]`.

Important limitation: extraction/class-dump did not produce reliable image-local headers for the five requested frameworks on this host. That is a tool failure, not evidence that the APIs are absent.

Raw outputs are preserved in:

```text
docs/findmy-framework-inspection-macOS-15.7.7-24G720-raw/
```

## Target Framework Presence

The x86_64 dyld cache map contains all five requested images:

```text
/System/Library/PrivateFrameworks/FindMyDevice.framework/Versions/A/FindMyDevice
/System/Library/PrivateFrameworks/FindMyCore.framework/Versions/A/FindMyCore
/System/Library/PrivateFrameworks/FindMyLocate.framework/Versions/A/FindMyLocate
/System/Library/PrivateFrameworks/FindMyLocateObjCWrapper.framework/Versions/A/FindMyLocateObjCWrapper
/System/Library/PrivateFrameworks/FindMyMessaging.framework/Versions/A/FindMyMessaging
```

The arm64e dyld cache map contains the same five images.

The local framework paths under `/System/Library/PrivateFrameworks` are dyld-cache stubs rather than standalone Mach-O binaries, so direct `ktool`, `otool`, `nm`, and `class-dump` against those paths did not inspect the real image contents.

## Requested Classes

All requested class/string names were found in both local dyld cache architectures and in the macOS 26.5.2 comparison report.

| Name | macOS 15 x86_64 | macOS 15 arm64e | macOS 26.5.2 report |
| --- | --- | --- | --- |
| `FMLDevice` | yes | yes | yes |
| `FMLFriend` | yes | yes | yes |
| `FMLHandle` | yes | yes | yes |
| `FMLLocation` | yes | yes | yes |
| `FMLPlaceMark` | yes | yes | yes |
| `FindMyLocateSession` | yes | yes | yes |

## Requested Selectors

All requested selectors were found in both local dyld cache architectures and in the macOS 26.5.2 comparison report.

| Selector | macOS 15 x86_64 | macOS 15 arm64e | macOS 26.5.2 report |
| --- | --- | --- | --- |
| `cachedFriendsSharingLocationWithMe` | yes | yes | yes |
| `cachedFriendsSharingLocationsWithMe` | yes | yes | yes |
| `cachedLocationForHandle:includeAddress:` | yes | yes | yes |
| `cachedLocationFor:includeAddress:` | yes | yes | yes |
| `startRefreshingLocationForHandles:priority:isFromGroup:completion:` | yes | yes | yes |
| `startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:` | yes | yes | yes |
| `stopRefreshingLocationForHandles:priority:isFromGroup:completion:` | yes | yes | yes |
| `getActiveLocationSharingDeviceWithCompletion:` | yes | yes | yes |
| `setActiveLocationSharingDevice:completion:` | yes | yes | yes |
| `canShareLocationWithHandle:isFromGroup:completion:` | yes | yes | yes |
| `friendshipStateWithHandle:isFromGroup:completion:` | yes | yes | yes |

Representative macOS 15.7.7 strings include:

```text
-[FindMyLocateSession cachedFriendsSharingLocationsWithMe]
-[FindMyLocateSession cachedLocationForHandle:includeAddress:]
-[FindMyLocateSession canShareLocationWithHandle:isFromGroup:completion:]
-[FindMyLocateSession friendshipStateWithHandle:isFromGroup:completion:]
-[FindMyLocateSession getActiveLocationSharingDeviceWithCompletion:]
-[FindMyLocateSession setActiveLocationSharingDevice:completion:]
-[FindMyLocateSession startRefreshingLocationForHandles:priority:isFromGroup:completion:]
-[FindMyLocateSession startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:]
-[FindMyLocateSession stopRefreshingLocationForHandles:priority:isFromGroup:completion:]
```

Close equivalents and adjacent selectors found on macOS 15.7.7 include:

```text
-[FindMyLocateSession cachedCanShareLocationWithHandle:isFromGroup:]
-[FindMyLocateSession cachedLocationForHandle:]
-[FindMyLocateSession getFriendsFollowingMyLocationWithCompletion:]
-[FindMyLocateSession getFriendsSharingLocationsWithMeWithCompletion:]
-[FindMyLocateSession sendFriendshipInviteToHandle:isFromGroup:completion:]
-[FindMyLocateSession sendFriendshipOfferToHandles:expiration:isFromGroup:completion:]
-[FindMyLocateSession startMonitoringActiveLocationSharingDeviceChangeWithCompletion:]
-[FindMyLocateSession startUpdatingFriendsWithInitialUpdates:completion:]
-[FindMyLocateSession stopSharingLocationWith:isFromGroup:completion:]
-[FindMyLocateSession stopUpdatingFriendsWithCompletion:]
```

## Tool Results

Successful evidence:

- Dyld cache maps confirmed the requested images exist:
  - `docs/findmy-framework-inspection-macOS-15.7.7-24G720-raw/dyld-map/target-frameworks-x86_64.txt`
  - `docs/findmy-framework-inspection-macOS-15.7.7-24G720-raw/dyld-map/target-frameworks-arm64e.txt`
- Cache-wide string scans found the requested API names:
  - `docs/findmy-framework-inspection-macOS-15.7.7-24G720-raw/strings/dyld-cache-x86_64-target-api-strings.txt`
  - `docs/findmy-framework-inspection-macOS-15.7.7-24G720-raw/strings/dyld-cache-arm64e-target-api-strings.txt`
- The exact presence matrix is preserved at:
  - `docs/findmy-framework-inspection-macOS-15.7.7-24G720-raw/comparison/name-presence-matrix.csv`

Failed or limited tools:

- `dyld_shared_cache_util` was not installed.
- `/usr/lib/dsc_extractor.bundle` exists, but it is a Mach-O bundle on this host, not a standalone executable.
- `DyldExtractor` located the requested images but failed to extract each of the five target images during fixups. The logs show fixup/stub/ObjC metadata errors; this is not evidence of API absence.
- `ktool` does not directly parse the dyld shared cache here.
- `otool`, `nm`, and `class-dump` against the dyld cache or stub framework paths did not produce useful per-image declarations.
- A PyObjC runtime-inspection attempt was started to list classes by `class_getImageName`, but PyObjC was not installed for system Python and a local install attempt was interrupted after stalling. This failed path is also not evidence of absence.

## Comparison With macOS 26.5.2

The macOS 26.5.2 report lists `FindMyLocateObjCWrapper` as the best Objective-C bridge candidate and includes the same class and selector names. The macOS 15.7.7 cache contains those same names.

Practical conclusion: the people-location API surface did not disappear on macOS 15.7.7. BlueBubbles failing to return Find My people locations on this machine is more likely caused by runtime authorization, entitlement, process context, or API-call behavior than by the absence of `FindMyLocateObjCWrapper` or the `FindMyLocateSession` people-location selectors.

