# SearchParty `latestLocationsForIdentifiers` plan

This note tracks the focused follow-up for `SPOwnerSessionXPCProtocol latestLocationsForIdentifiers:fetchLimit:sources:completion:`. That proxy method is the most promising coordinate-bearing lead found so far because it is exposed directly by the live `__NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol` object under `SPOwnerSessionLocationFetch.proxy`.

## Starting evidence

- Live proxy class: `__NSXPCInterfaceProxy_SPOwnerSessionXPCProtocol`
- Candidate method: `latestLocationsForIdentifiers:fetchLimit:sources:completion:`
- Previous call shape:
  - identifiers: `53`
  - sources: `12`
  - fetch limit: `53`
- Previous result:
  - no completion within the probe window
  - `SPOwnerSession.locationsForBeacons:completion:` still returned an empty dictionary
  - no coordinates surfaced

## Investigation steps

1. Call `latestLocationsForIdentifiers:fetchLimit:sources:completion:` with one identifier at a time.

   Hypothesis: one stale/offline beacon may block or delay the whole 53-identifier request. A one-identifier call may complete even if the broad call does not.

   Notes:
   - Added focused probe selector `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.singleIdentifier`.
   - Test run used one generated `NSUUID` identifier, `fetchLimit = 1`, and the captured `Swift.__SwiftDeferredNSArray` source collection from the real `SPLocationFetchContext`.
   - Result: timed out. The `latestLocationsForIdentifiers` completion did not fire.
   - Baseline `SPOwnerSession.locationsForBeacons:completion:` still completed with an empty dictionary.
   - No `SPLocationFetchResult`, `locationsByBeaconIdentifier`, `CLLocation`, latitude, longitude, or accuracy data surfaced.

2. Preserve exact argument classes.

   Hypothesis: the XPC method may expect the same concrete Foundation/Swift collection classes Find My uses internally. Normalizing to arrays may change bridging enough to affect completion.

   Notes:
   - Added focused probe selector `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.exactContextArguments`.
   - Captured context argument classes:
     - `real_search_identifiers_class`: `Swift.__EmptyArrayStorage`
     - `real_search_identifiers_count`: `0`
     - `real_search_location_sources_class`: `Swift.__SwiftDeferredNSArray`
     - source element class: `__NSCFConstantString`
   - Because the captured context identifier array was empty, the test preserved the generated identifier set class (`__NSSetM`) and the captured Swift source array.
   - Result: timed out. The exact-argument completion did not fire.
   - After the timeout, Find My was force quit and the Find My helper disconnected before the next probe could start.
   - No coordinate-bearing result surfaced.

3. Call proxy `locationForContext:completion:` directly.

   Hypothesis: the wrapper `SPOwnerSessionLocationFetch locationForContext:completion:` may alter or filter results. Calling the XPC proxy directly with the captured context may expose a lower-level result.

   Notes:
   - Added focused probe selector `SPOwnerSessionXPCProtocol.locationForContext:completion:`.
   - Reordered the focused probe so this step could run first on a clean helper, avoiding the destabilizing exact-argument probe.
   - Result: the probe started and timed out with one pending completion, which was the direct proxy `locationForContext:completion:` call.
   - Baselines completed:
     - `SPBeaconManagerSimpleBeaconUpdateInterface.startUpdatingSimpleBeaconsWithContext:completion:` returned `nil`.
     - `SPOwnerSession.locationsForBeacons:completion:` returned an empty dictionary.
   - No `SPLocationFetchResult` or coordinate-bearing payload surfaced.

4. Call `latestLocationsForIdentifiers:fetchLimit:sources:completion:` with source subsets.

   Hypothesis: only some source values are relevant for devices/items, or one source causes the request to hang. Testing one source at a time should reveal whether any source completes with location data.

   Notes:
   - Added source-subset focused probe labels:
     - `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.0`
     - `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.1`
     - `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.2`
     - `SPOwnerSessionXPCProtocol.latestLocationsForIdentifiers.sourceSubset.3`
   - First observed source values from the captured source array were:
     - `connectionEvent`
     - `connectionmaintenance`
     - `disconnection`
     - `harvesterNetwork`
   - Attempting to reach this step after step 3 failed because the Find My helper disconnected and the route returned `Transaction timeout`.
   - I then changed the rotation order to put source subsets first for the next clean helper launch. This gives source subsets a clean first attempt in the next run instead of requiring step 3 to complete first.
   - No source-subset completion has produced coordinate data yet.

## Current instrumentation behavior

The location probe now runs one focused lead per `/api/v1/icloud/findmy/searchparty/locations/start` call. The current order is:

1. source subsets
2. direct proxy `locationForContext:completion:`
3. single identifier `latestLocationsForIdentifiers`
4. exact/context-preserving `latestLocationsForIdentifiers`

The order is intentionally different from the investigation list because `latestLocationsForIdentifiers` and direct proxy context calls can leave the Find My helper disconnected after a timeout. Running the most fragile leads later makes it possible to test source subsets on a clean helper process.

## Desired evidence

For each attempt, record:

- selector invoked
- identifier count
- source count
- concrete argument classes
- whether completion fired
- result class
- result count
- whether any value serializes as `CLLocation` or contains latitude/longitude/accuracy
