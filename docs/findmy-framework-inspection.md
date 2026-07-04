# Find My Framework Inspection

Generated on macOS 26.5 from the 17 `FindMy*.framework` references in `FindMy/MacOS-16+/BlueBubblesHelper.xcodeproj`.

Raw extraction and tool outputs are in:

```text
/tmp/bluebubbles-findmy-tools/inspection
```

## Tooling

- `nygard/class-dump`, built from source in `/tmp/bluebubbles-findmy-tools/class-dump`.
- `0cyn/ktool` via `k2l==2.0.0` in `/tmp/bluebubbles-findmy-tools/ktool-venv`.
- The public framework paths under `/System/Library/PrivateFrameworks` are broken symlink shells on this install. The actual arm64e Mach-O images were extracted from `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e` with `/usr/lib/dsc_extractor.bundle`.

## Tool Results

| Framework | class-dump headers | ktool headers | linked images |
| --- | ---: | ---: | ---: |
| FindMyBase | 0 | 2 | 20 |
| FindMyBluetooth | 0 | 2 | 15 |
| FindMyCloudKit | 0 | 2 | 21 |
| FindMyCommon | 0 | 2 | 18 |
| FindMyCore | 0 | 2 | 34 |
| FindMyCrypto | 1 | 2 | 14 |
| FindMyDaemonSupport | 0 | 2 | 16 |
| FindMyDevice | 0 | 2 | 8 |
| FindMyDeviceUI | 0 | 2 | 13 |
| FindMyLocate | 0 | 2 | 31 |
| FindMyLocateObjCWrapper | 0 | 2 | 23 |
| FindMyMac | 1 | 2 | 10 |
| FindMyMessaging | 0 | 2 | 17 |
| FindMyPairing | 0 | 2 | 13 |
| FindMyServerInteraction | 0 | 2 | 16 |
| FindMyStorage | 0 | 2 | 15 |
| FindMyUnsafeAsyncBridging | 0 | 2 | 15 |

`class-dump` did not recover useful Objective-C declarations from these extracted cache images. The recurring failure was:

```text
Unknown load command: 0x80000033
Error: Cannot find offset for address ... in dataOffsetForAddress:
```

`ktool dump --headers` created framework header files, but they were effectively empty for this Swift-heavy set. `ktool list --linked` was useful and confirmed the dependency graph. `ktool list --classes`, `--protocols`, and `--stypes` did not recover useful declarations from the extracted cache images.

## Dependency Shape

- `FindMyLocateObjCWrapper` links `FindMyLocate` and Swift/CoreLocation support. This remains the best direct Objective-C bridge candidate for helper work.
- `FindMyLocate` links `FindMyCommon`, `FindMyBase`, `NearbyInteraction`, `Contacts`, `Accounts`, `_LocationEssentials`, `GeoServices`, and Swift runtime libraries.
- `FindMyCore` links `FindMyLocate`, `FindMyBase`, `SPOwner`, `Contacts`, `CoreLocation`, `GeoToolbox`, AppIntents/CoreTransferable, and Swift runtime libraries.
- `FindMyMessaging` links `IDS`, `IDSFoundation`, and `FindMyBase`.
- `FindMyCloudKit` links `FindMyBase`, `FindMyCommon`, `FindMyStorage`, `FindMyDaemonSupport`, `CloudKit`, and `SwiftSQLite`.
- `FindMyBluetooth` links `FindMyBase`, `FindMyCrypto`, and `CoreBluetooth`.
- `FindMyDevice` is the older Objective-C-looking device/FMM surface, linking `FMCoreLite`, `Security`, `LocalAuthentication`, and CoreFoundation.

## Useful Candidate APIs

### FindMyLocateObjCWrapper

This is the most useful framework for the existing helper because it exposes Objective-C-facing class and selector names in the binary strings:

- Classes: `FMLDevice`, `FMLFriend`, `FMLHandle`, `FMLLocation`, `FMLPlaceMark`, `FindMyLocateSession`.
- Friend/location cache:
  - `cachedFriendsFollowingMyLocation`
  - `cachedFriendsSharingLocationWithMe`
  - `cachedFriendsSharingLocationsWithMe`
  - `cachedFriendsWithPendingOffers`
  - `cachedLocationForHandle:includeAddress:`
  - `cachedLocationFor:includeAddress:`
  - `cachedOfferExpirationForHandle:groupId:`
- Refresh:
  - `startRefreshingLocationForHandles:priority:isFromGroup:completion:`
  - `startRefreshingLocationForHandles:priority:isFromGroup:reverseGeocode:completion:`
  - `stopRefreshingLocationForHandles:priority:isFromGroup:completion:`
  - `stopRefreshingLocationWithCompletion:`
- Active device:
  - `getActiveLocationSharingDeviceWithCompletion:`
  - `setActiveLocationSharingDevice:completion:`
  - `startMonitoringActiveLocationSharingDeviceChangeWithCompletion:`
- Sharing/friendship:
  - `canShareLocationWithHandle:isFromGroup:completion:`
  - `friendshipStateWithHandle:isFromGroup:completion:`
  - `sendFriendshipInviteToHandle:isFromGroup:completion:`
  - `sendFriendshipOfferToHandles:expiration:isFromGroup:completion:`
  - `stopSharingLocationWith:isFromGroup:completion:`

### FindMyLocate

The Swift implementation surface underneath the wrapper includes:

- Main class/string names: `Session`, `LocationConnection`, `FriendshipConnection`, `SettingsConnection`, `LocationTrampoline`, `FriendshipTrampoline`.
- Location refresh and cache:
  - `startRefreshingLocation(handles:priority:reverseGeocode:origin:clientID:)`
  - `addHandlesToLocationStream(handles:priority:origin:reverseGeocode:clientID:)`
  - `requestRefreshLocation(origin:handles:clientID:priority:isCached:reason:)`
  - `cachedLocation(for:includeAddress:followingsFromCached:)`
  - `latestLocations(for:clientID:)`
  - `locationsForHandles(_:completion:)`
- Device/settings:
  - `allDevices(cached:)`
  - `activeLocationSharingDevice(cached:)`
  - `setActiveLocationSharingDevice(_:)`
  - `isMyLocationEnabled(cached:)`
  - `hideMyLocation(hidden:)`
- Sharing/friendship:
  - `sendFriendshipInvite(_:)`
  - `sendFriendshipOffer(_:)`
  - `stopSharingMyLocation(_:)`
  - `allowFriendshipRequests(allowed:)`

### FindMyDevice

This framework has the clearest Objective-C selector strings, but it is more device/FMM/activation-lock oriented than people location:

- Main names: `FMDFMMManager`, `FMDFMMAccountInfo`, `FMIPDeviceDidConnectBluetoothDevice`, `FMIPDeviceDidPairBluetoothDevice`.
- Account/device management:
  - `addFMMAccount:withCompletion:`
  - `removeFMMAccountWithUsername:completion:`
  - `retrieveFMMAccountWithCompletion:`
  - `fmmAccountCacheWithCompletion:`
  - `needsDeviceOwnerCredentials:`
- Device commands:
  - `locationCommandWithCompletion:`
  - `locationPayloadWithCompletion:`
  - `fetchAPNSTokenWithCompletion:`
  - `eraseDeviceWithOptions:completion:`
  - `simulatePushWithPayload:completion:`

### FindMyMessaging

This framework is IDS/session transport for Find My features:

- Names: `SessionMessaging`, `SessionMessagingDatagramConnection`, `MessagingDelegateTrampoline`, `IDSSessionWrapper`, `Destination`, `MessagingCapability`.
- Selectors:
  - `initWithAccount:destinations:transportType:`
  - `remoteDevices(destinations:)`
  - `currentRemoteDevicesForDestinations:service:listenerID:queue:completionBlock:`
  - `datagramConnectionForSessionDestination:error:`
  - `sendMessage:toDestinations:priority:options:identifier:error:`
  - `readDatagramsWithMinimumCount:maximumCount:completionHandler:`
  - `writeDatagrams:completionHandler:`

## Practical Takeaways

1. For Find My people-location work, prefer `FindMyLocateObjCWrapper` over direct `FindMyLocate` calls. It has the Objective-C bridge classes the helper can message from Objective-C.
2. The current helper headers for `FMLSession`, `FMLHandle`, and `FMLLocation` are directionally aligned with the wrapper strings. The next useful headers to add would be `FMLDevice`, `FMLFriend`, and `FMLPlaceMark`.
3. Directly linking every framework remains risky. The earlier linker failure for `FindMyUnsafeAsyncBridging` matches the inspection: these are private Swift framework images with restricted linkage and dyld-cache-only distribution. Runtime lookup / weak references are safer for the dylib.
4. `class-dump` is not enough for macOS 26 Find My Swift frameworks. ktool helps validate Mach-O structure and dependencies, but the most useful API clues came from wrapper selector strings and Swift symbol strings after dyld-cache extraction.
