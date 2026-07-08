# Find My Local Item Location Gap - 2026-07-07

## Observation

The development Mac used for this work does not show locations for any Items in the Find My app.

The same Apple ID does show at least some Item locations on other Macs and on iPhone. On this development Mac, Find My still shows some locations for Devices and Friends, but no Item locations.

## Why this matters

This changes the interpretation of empty SearchParty item-location results.

Previously, empty `SPLocationFetchResult.locationsByBeaconIdentifier` results could have meant:

- our helper was missing the correct API path;
- the fetch context was incomplete;
- the result existed elsewhere in the object graph;
- the local Find My/SearchParty stack did not currently have Item coordinates.

The local Find My UI now makes the last explanation much more plausible for Items on this host. If Apple's own app is not materializing any Item coordinates on this Mac, the injected helper may be observing true local state rather than failing to extract coordinates that are present.

## Fits observed instrumentation

This host still exposes Item/SearchParty identity and freshness state:

- `SPBeacon` inventory records are available.
- `SPLocationFetchContext.lastOnlineLocationInfo` is non-empty.
- `SPLocationFetchContext.searchLocationSources` is non-empty.
- `SPLocationFetchContext.searchIdentifiers` can become non-empty.
- `SPLastOnlineLocationInfo` exposes timestamp-style state.

But coordinate-bearing state remains absent:

- `SPLocationFetchResult.locationsByBeaconIdentifier` has been empty.
- No Item `CLLocation` object has been found.
- No Item latitude/longitude fields have surfaced.

That shape now matches the Find My UI: this Mac knows about Items and recent SearchParty state, but is not resolving/displaying Item coordinates.

## Current interpretation

For Items, this Mac may have a local SearchParty state problem or missing local material needed to resolve item reports into coordinates.

Possible explanations:

- local SearchParty cache or account state is incomplete for Items;
- local key/material needed to decrypt or resolve Item reports is missing or stale;
- Item coordinate materialization is failing locally even though identity and last-online metadata are present;
- the local app and helper both depend on the same Item location pipeline, so both see no coordinates.

This does not prove the SearchParty APIs cannot return Item coordinates. It means this host may be a poor test machine for proving Item coordinate extraction unless we first fix or compare the local Find My Item location state.

## Practical next steps

Prefer Devices or another host for coordinate-positive instrumentation:

- Use this Mac for Device or Friend location paths where the local Find My UI already shows some coordinates.
- For Items, compare this Mac against a Mac where Find My does show Item locations.
- On a coordinate-positive Mac, re-run the same SearchParty probes and check whether `SPLocationFetchResult.locationsByBeaconIdentifier` becomes non-empty.
- Compare `SPLocationFetchContext`, `searchIdentifiers`, `searchLocationSources`, `lastOnlineLocationInfo`, local caches, and account/session state between the coordinate-negative and coordinate-positive Macs.

## Important boundary

The Android-facing BlueBubbles routes are product integration surfaces and should not be used as evidence for Apple's internal SearchParty architecture. This note is about local Find My/SearchParty state observed in Apple's app and in the injected helper.
