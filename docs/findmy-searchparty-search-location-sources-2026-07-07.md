# Find My SearchParty searchLocationSources - 2026-07-07

## Summary

`SPLocationFetchContext.searchLocationSources` appears to be SearchParty request configuration, not location payload data.

In the guarded `last-online-identifiers` probe, the retained runtime context reported:

```text
path: SPLocationFetchContext.searchLocationSources
class: Swift.__SwiftDeferredNSArray
count: 12
```

The values look like source-channel names. They likely tell SearchParty which internal observation streams or retrieval paths may be consulted while fetching location state for the context's `searchIdentifiers`.

This interpretation fits SearchParty's broader model: location evidence can come from the wider Find My network, from owner devices, from the device/accessory itself when capable, from local cache, or from explicit request/response flows.

## Observed sources

| Source | Current interpretation | Confidence |
| --- | --- | --- |
| `connectionEvent` | Location or proximity evidence derived from a device/accessory connection event. | Maybe correct |
| `connectionmaintenance` | Ongoing connection maintenance state, probably related to nearby/proximate device upkeep. | Maybe correct |
| `disconnection` | Location or proximity evidence derived from a disconnect event. | Maybe correct |
| `harvesterNetwork` | Observations harvested from the wider Find My/SearchParty network. | Probably correct |
| `harvesterOnDiskNearOwner` | Cached harvested observations stored locally and associated with near-owner context. | Maybe correct |
| `harvesterOnDiskWild` | Cached harvested observations stored locally from wider, non-near-owner network context. | Maybe correct |
| `intentLocationUpdate` | Explicit location-update request path, likely started by a Find My/UI/client intent. | Maybe correct |
| `intentResponse` | Response/result path for an explicit location intent. | Maybe correct |
| `localReductiveFilter` | Local filtering or reduction stage before a result is exposed. | Maybe correct |
| `pairingLocationManager` | Pairing-time or locally paired accessory/device location source. | Maybe correct |
| `selfPublish` | Location published by the local device/account/device itself. | Probably correct |
| `ownedDeviceLocation` | Owner-account device location path, likely relevant to Devices. | Probably correct |

## Important related context

The first guarded call had:

```text
lastOnlineLocationInfo count: 10
searchLocationSources count: 12
searchIdentifiers count: 0
```

The second guarded call had:

```text
lastOnlineLocationInfo count: 10
searchLocationSources count: 12
searchIdentifiers count: 10
```

That second shape is more promising because it includes both:

- identifiers to search for;
- the source channels that SearchParty is allowed to use.

This is the closest context shape we have seen to a real item/device fetch request. It still did not expose coordinates directly in the inspected `SPLastOnlineLocationInfo` entries.

## Current working model

`searchLocationSources` is best treated as a routing/filter list for SearchParty fetches:

```text
searchIdentifiers + searchTypes + searchLocationSources + cachePolicy + subscribe/report flags
```

Together, those fields likely describe what SearchParty should look for, which categories of records are relevant, which source channels are acceptable, and whether the context is a one-shot fetch or subscribed/live update flow.

## What this does not prove

This list does not prove that each source can independently return coordinates through the helper route. It also does not prove that copying these values into a generated `SPLocationFetchContext` is sufficient.

Previous generated-context attempts that copied `searchLocationSources` still failed to populate `SPLocationFetchResult.locationsByBeaconIdentifier`. That suggests at least one of these is also required:

- a retained internal context object rather than a newly allocated imitation;
- correctly populated `searchIdentifiers`;
- a matching private session/proxy state;
- a live subscription lifecycle;
- an XPC-side entitlement/account/session state that cannot be recreated only by setting ivars.

## Next question

The next useful comparison is between contexts where `searchIdentifiers` is empty and contexts where it is populated. Understanding what caused the second guarded call to populate 10 identifiers may be more important than the sources list itself.
