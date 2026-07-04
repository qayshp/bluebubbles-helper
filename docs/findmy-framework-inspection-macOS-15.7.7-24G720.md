# FindMy Private Framework Inspection

Date: 2026-07-04
Host: macOS 15.7.7 build 24G720 / x86_64

## Tools Built/Installed

- `class-dump`: built from `nygard/class-dump` into `tools/bin/class-dump`
  - Build note: direct `xcodebuild` was unavailable because the active developer directory is Command Line Tools, not full Xcode.
  - Manual build used `clang`, ARC, the project prefix header, bundled Blowfish source, and `PLATFORM_IOSMAC=PLATFORM_MACCATALYST` compatibility.
- `ktool`: installed from cloned `0cyn/ktool` into `.venv-0cyn-ktool/bin/ktool`.
- `DyldExtractor`: cloned and run from source as a helper to extract dyld-cache images, because the FindMy frameworks do not have on-disk Mach-O binaries at their framework paths.

## Framework Location Reality

All `/System/Library/PrivateFrameworks/FindMy*.framework` directories are dyld-cache stubs on this system. None has a direct executable Mach-O at:

```text
/System/Library/PrivateFrameworks/<Name>.framework/<Name>
/System/Library/PrivateFrameworks/<Name>.framework/Versions/Current/<Name>
```

The actual code is in:

```text
/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64
```

The cache map confirms these FindMy images are present:

```text
FindMyBase
FindMyBluetooth
FindMyCloudKit
FindMyCommon
FindMyCore
FindMyCrypto
FindMyDaemonSupport
FindMyDevice
FindMyDeviceUI
FindMyLocate
FindMyLocateObjCWrapper
FindMyMac
FindMyMessaging
FindMyPairing
FindMyServerInteraction
FindMyStorage
FindMyUnsafeAsyncBridging
```

## Extraction Result

`DyldExtractor` was able to list the FindMy images in the macOS dyld cache, but extraction of most images failed during ObjC fixups with:

```text
struct.error: required argument is not an integer
```

This happened after repeated warnings like:

```text
Class pointer ... points to class outside MachO file
Protocol pointer ... points to protocol outside MachO file
```

Usable extracted Mach-O images were produced for only:

```text
analysis/findmy-dyld-x86_64/System/Library/PrivateFrameworks/FindMyCrypto.framework/Versions/A/FindMyCrypto
analysis/findmy-dyld-x86_64/System/Library/PrivateFrameworks/FindMyPairing.framework/Versions/A/FindMyPairing
analysis/findmy-dyld-x86_64/System/Library/PrivateFrameworks/FindMyUnsafeAsyncBridging.framework/Versions/A/FindMyUnsafeAsyncBridging
```

## class-dump Findings

Raw outputs live under:

```text
analysis/findmy-class-dump/
```

`class-dump` could open the three extracted files but emitted:

```text
Unknown load command: 0x80000033
```

Generated headers were minimal:

- `FindMyCrypto`: only `CDStructures.h`, no ObjC class headers.
- `FindMyPairing`: no generated headers; `class-dump` also reported an address/offset mapping error.
- `FindMyUnsafeAsyncBridging`: only `CDStructures.h`, no ObjC class headers.

Interpretation: these three extracted images are primarily Swift, and `class-dump` is not useful for their Swift interfaces. It also does not handle this modern load command cleanly.

## ktool Findings

Raw outputs live under:

```text
analysis/findmy-ktool/
```

### FindMyCrypto

`ktool list --classes` found no ObjC classes.

`ktool symbols --exports`, demangled with `swift demangle`, shows Swift crypto primitives relevant to Find My encrypted payloads and beacon/location key material, including:

- `FindMyCrypto.PrivateKey`
- `FindMyCrypto.PublicKey`
- `FindMyCrypto.P256PrivateKey`
- `FindMyCrypto.P256PublicKey`
- `FindMyCrypto.SymmetricKey256`
- `FindMyCrypto.LocationDecryptionKey`
- `FindMyCrypto.Advertisement`
- `FindMyCrypto.NearOwnerAdvertisement`
- `FindMyCrypto.HashedAdvertisement`
- `FindMyCrypto.TimeBasedKey`
- `FindMyCrypto.EncryptAndSignEnvelope`
- `FindMyCrypto.CryptoError`
- `FindMyCrypto.CryptoTokenError`

Notable string evidence:

```text
signature
encryptedData
LocationDecryptionKey
CryptoTokenError
missingTokenGenerationEntitlement
com.apple.findmy.framework.FindMyCrypto
```

Linked libraries include:

- `FindMyBase.framework`
- `Foundation.framework`
- `CryptoKit.framework`
- Swift runtime libraries

### FindMyPairing

`ktool list --classes` found one ObjC-visible Swift class:

```text
_TtC13FindMyPairing14PairingService
```

Demangled exports show this framework is focused on accessory/beacon pairing flows, not friend location retrieval. Examples:

- `FindMyPairing.PairingService`
- `FindMyPairing.PairingServiceProxy`
- `FindMyPairing.PairingRequest`
- `FindMyPairing.PairingResponse`
- `FindMyPairing.PairingAckRequest`
- `FindMyPairing.PairingAckResponse`
- `FindMyPairing.PairingValidator`
- `FindMyPairing.PairingPeripheralProvider`
- `FindMyPairing.PairingCoordinatorType`
- `FindMyPairing.PairingBeaconStore`
- `FindMyPairing.PairingKeysInfo`
- `FindMyPairing.PairingExecutor`
- `FindMyPairing.PairingExecutorFactory`
- `FindMyPairing.PairingInfoStore`
- `FindMyPairing.UserSessionListener`

Notable strings:

```text
PairingService
PairingCoordinator
PairingBeaconStore
PairingKeysInfo
successfullyFindMyPaired
signatureVerificationStart
signatureVerificationFinish
generatePairingDataStart
generatePairingDataFinish
```

Linked libraries include:

- `FindMyBase.framework`
- `Foundation.framework`
- Swift runtime libraries

### FindMyUnsafeAsyncBridging

`ktool list --classes` found no ObjC classes.

Demangled exports show a small Swift utility framework for bridging async code unsafely/blockingly:

- `FindMyUnsafeAsyncBridging.unsafeFromAsyncTask<A>(@Sendable () async throws -> A) throws -> A`
- `FindMyUnsafeAsyncBridging.unsafeFromAsyncTask<A>(@Sendable () async -> A) -> A`
- `FindMyUnsafeAsyncBridging.unsafeBlocking<A>(@Sendable () throws -> A) async throws -> A`
- `FindMyUnsafeAsyncBridging.unsafeBlocking<A>(@Sendable () -> A) async -> A`
- `FindMyUnsafeAsyncBridging.UnsafeSendableBox`

Linked libraries include:

- `FindMyBase.framework`
- `Foundation.framework` weak-linked
- Swift runtime libraries

## Relevance To BlueBubbles Find My

The successful dumps do not expose the friend-location service surface directly. They support the earlier diagnosis in two ways:

1. Modern Find My local cache files contain `encryptedData` and `signature`, and `FindMyCrypto` contains explicit Swift types for encryption/signing/decryption/key material.
2. The friend-location APIs of interest likely live in the images that failed extraction here, especially:
   - `FindMyLocate.framework`
   - `FindMyLocateObjCWrapper.framework`
   - possibly `FindMyCore.framework` / `FindMyStorage.framework`

Those images are present in the dyld cache, but this `class-dump` + `ktool` path could not extract/parse them cleanly on this macOS cache.

## Raw Artifact Paths

- Extracted Mach-O images: `analysis/findmy-dyld-x86_64/`
- `class-dump` output: `analysis/findmy-class-dump/`
- `ktool` output: `analysis/findmy-ktool/`
- Demangled Swift export lists:
  - `analysis/findmy-ktool/FindMyCrypto.exports.demangled.txt`
  - `analysis/findmy-ktool/FindMyPairing.exports.demangled.txt`
  - `analysis/findmy-ktool/FindMyUnsafeAsyncBridging.exports.demangled.txt`
