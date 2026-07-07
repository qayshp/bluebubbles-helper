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

   Notes: Pending.

2. Preserve exact argument classes.

   Hypothesis: the XPC method may expect the same concrete Foundation/Swift collection classes Find My uses internally. Normalizing to arrays may change bridging enough to affect completion.

   Notes: Pending.

3. Call proxy `locationForContext:completion:` directly.

   Hypothesis: the wrapper `SPOwnerSessionLocationFetch locationForContext:completion:` may alter or filter results. Calling the XPC proxy directly with the captured context may expose a lower-level result.

   Notes: Pending.

4. Call `latestLocationsForIdentifiers:fetchLimit:sources:completion:` with source subsets.

   Hypothesis: only some source values are relevant for devices/items, or one source causes the request to hang. Testing one source at a time should reveal whether any source completes with location data.

   Notes: Pending.

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
