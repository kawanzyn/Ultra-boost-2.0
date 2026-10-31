# Server Finder specification and runtime behavior

## Endpoint
GET https://games.roblox.com/v1/games/{PLACE_ID}/servers/Public?sortOrder=Asc&limit=100&cursor={CURSOR}

PLACE_ID means the numeric PlaceId, not UniverseId. The first page omits cursor; subsequent pages use nextPageCursor.

## Validated fields
- id: required non-empty string / JobId.
- playing and maxPlayers: optional non-negative integers.
- ping and fps: optional finite non-negative numbers.
- nextPageCursor: optional non-empty string.

Unknown or invalid values are kept unavailable rather than converted to zero.

## Modes
- Empty Server: only playing == 0.
- Low Population: known playing <= configured threshold.
- Oldest Empty: zero-player candidates ordered by locally observed empty-sequence start. This cannot establish true server creation age or uninterrupted empty duration.
- Low Ping: known ping in ascending order; unknown values are last.
- Balanced: occupancy ratio (playing/maxPlayers), weight 0.60, and reported ping, weight 0.40. Weights are renormalized when a candidate lacks one metric. If no comparable metric exists, no score is fabricated.

All modes exclude the current JobId, recently visited servers when enabled, and servers in temporary failure cooldown.

## Pagination and protection
- Sequential pagination, default limit 100 and max 10 pages per scan.
- Cache is per PlaceId/cursor with short TTL.
- A single scan may run at a time.
- HTTP 429 and 5xx use bounded exponential backoff.
- Repeated cursors stop the scan.
- Automatic refresh defaults to 30 seconds and is bounded from 10 to 300 seconds.

## History and counters
Observation, visit and failure records are held in memory for the current script session. JobIds are deduplicated across pages/refresh counts. firstSeen, lastSeen, last observed population, and observed empty sequence are recorded.

## Entry behavior
The adapter probes TeleportToPlaceInstance and invokes it through pcall. It distinguishes a request accepted by the local call from a teleport-start signal and an initialization failure. A successful arrival is not claimed. Synchronous failures may move to another filtered candidate, with a three-attempt limit. Actual capability must be verified on the target runtime.

## Test status
This initial commit contains source implementation only. It does not claim live API, executor, or iPhone validation. See docs/TESTING.md.
