# Testing checklist

## Basic migration
- [ ] Compile standalone script and modular source.
- [ ] Test Ultra, Equilibrado and Leve.
- [ ] Verify Decal, Texture and SurfaceAppearance restoration.
- [ ] Verify Restore All and close behavior.
- [ ] Verify ground and collision protections.
- [ ] Verify touch/mouse dragging.

## Server Finder simulated tests
- [ ] Missing/invalid id, playing, maxPlayers, ping and fps.
- [ ] Invalid JSON and non-2xx responses.
- [ ] HTTP 429/5xx bounded backoff.
- [ ] Multi-page pagination and repeated-cursor termination.
- [ ] Duplicate JobId counted once.
- [ ] Cache hit/expiration and one-flight behavior.
- [ ] Current/recently visited/failed server exclusions.
- [ ] All five mode orderings and missing-metric handling.
- [ ] Oldest Empty observation semantics.
- [ ] Auto-refresh start/stop.
- [ ] Synchronous entry failure retry limit.
- [ ] Teleport started/failure events where exposed.

## Live runtime tests — not yet performed
- [ ] Live public server API query.
- [ ] iPhone/Delta test with exact runtime version.
- [ ] Confirm HTTP transport is available.
- [ ] Confirm TeleportToPlaceInstance is callable and permitted.
- [ ] Verify destination arrival separately from request accepted/teleport started.

Compilation or mocked responses do not prove API availability or successful device behavior.
