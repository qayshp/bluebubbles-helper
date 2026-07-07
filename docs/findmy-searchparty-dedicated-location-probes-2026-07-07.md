# SearchParty dedicated location probes

This note tracks the move away from the rotating `/locations/start` probe toward one-route-per-risky-call testing. The rotating probe made evidence ambiguous because one hanging XPC call could block or destabilize the helper before the next lead ran.

## Dedicated routes

The server now exposes these focused starts:

- `POST /api/v1/icloud/findmy/searchparty/locations/latest-single`
  - Helper event: `debug-findmy-searchparty-locations-latest-single`
  - Focused helper step: `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier`
  - Goal: call `latestLocationsForIdentifiers:fetchLimit:sources:completion:` with one beacon identifier and the captured source array.

- `POST /api/v1/icloud/findmy/searchparty/locations/source-subset`
  - Helper event: `debug-findmy-searchparty-locations-source-subset`
  - Focused helper step: `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.*`
  - Goal: call `latestLocationsForIdentifiers:fetchLimit:sources:completion:` with one beacon identifier and individual source values.

- `POST /api/v1/icloud/findmy/searchparty/locations/proxy-context`
  - Helper event: `debug-findmy-searchparty-locations-proxy-context`
  - Focused helper step: `SPOwnerSessionXPCProtocol.locationForContext:completion:`
  - Goal: call the live `SPOwnerSessionXPCProtocol` proxy directly with the generated `SPLocationFetchContext`.

The existing status route remains shared:

- `POST /api/v1/icloud/findmy/searchparty/locations`

## Why this shape

Each dedicated route sends one private API action to the injected Find My helper. The helper records `dedicated_probe = true`, the focused step, invoked selector labels, argument classes, source summaries, completion results, and timeout state in the shared location probe status payload.

This should make each result attributable:

- If `latest-single` hangs, the single-identifier contract is still wrong or insufficient.
- If `source-subset` hangs, the exact source value under test is visible in `latest_locations_source_subset_arguments`.
- If `proxy-context` hangs, the lower-level proxy call itself is not producing a completion for the generated context.

## Initial test notes

Tested locally on 2026-07-07 with the rebuilt helper dylib loaded by the
development Electron server. The tracked server copy and the dev runtime copy
both had md5 `92b608d61b329b62cd535f4f1c6275e7`.

### `source-subset`

Route:

```text
POST /api/v1/icloud/findmy/searchparty/locations/source-subset
```

Result:

- HTTP start returned 200.
- Probe recorded `dedicated_probe = true`.
- Probe recorded `focused_probe_step = 4`.
- Probe status became `timed_out`.
- `pending_completion_count = 4` after the timeout window.
- Invoked selectors:
  - `SPOwnerSession.locationsForBeacons:completion:`
  - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:`
  - `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubsets`
- Completed selectors:
  - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` returned `<nil>`.
  - `SPOwnerSession.locationsForBeacons:completion:` returned `__NSDictionary0`.
- Source subset attempts were made with individual `__NSCFConstantString`
  source values including:
  - `connectionEvent`
  - `connectionmaintenance`
  - `disconnection`
  - `harvesterNetwork`

Interpretation: the helper can run this focused route and can still see the
SearchParty objects, but the individual
`latestLocationsForIdentifiers:fetchLimit:sources:completion:` calls do not
produce completions for the generated identifier/source combinations currently
being used.

### `latest-single`

Route:

```text
POST /api/v1/icloud/findmy/searchparty/locations/latest-single
```

Result:

- HTTP start returned 200.
- Probe recorded `dedicated_probe = true`.
- Probe recorded `focused_probe_step = 1`.
- Probe status became `timed_out`.
- `pending_completion_count = 1` after the timeout window.
- The probe saw `allBeaconsCache` and `allBeacons` as `__NSSetI` with 53
  `SPBeacon` elements.
- Invoked selectors:
  - `SPOwnerSession.locationsForBeacons:completion:`
  - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:`
  - `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier`
- Completed selectors:
  - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` returned `<nil>`.
  - `SPOwnerSession.locationsForBeacons:completion:` returned `__NSDictionary0`.

Interpretation: this proves the single-route shape is working and that a real
beacon cache is present. However, the direct latest-location XPC call still does
not complete for the current argument shape.

### `proxy-context`

Route:

```text
POST /api/v1/icloud/findmy/searchparty/locations/proxy-context
```

Result:

- The HTTP start request timed out after 60 seconds with no response body.
- The shared location probe status stayed `not_started`.
- Server log showed the Find My helper socket disconnected immediately after
  the request:
  - `Private API Helper (com.apple.findmy) disconnected`
  - `Detected DYLIB crash for App FindMy. Error: Process was force quit`
- The server relaunched Find My and the helper reconnected afterward.

Interpretation: the direct proxy-context route is currently unsafe. It appears
to block or crash before the helper can publish probe state. Keep it isolated
from the other probes and do not use it as part of routine Android-facing
refresh behavior.

## Android-facing API sanity check

After the focused probe tests, the normal Find My routes were called through the
local HTTP API:

- `GET /api/v1/icloud/findmy/friends` returned HTTP status field 200 and 8
  records.
- `GET /api/v1/icloud/findmy/devices` returned HTTP status field 200 with
  `data = null`.
- `GET /api/v1/icloud/findmy/items` returned HTTP status field 200 with
  `data = null`.

Interpretation: the existing friend path still works. Devices and items still
need a location-bearing source; enumeration through `SPBeacon`/SearchParty is
available, but these latest-location calls have not produced a usable location
dictionary yet.
