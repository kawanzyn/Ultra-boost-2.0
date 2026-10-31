# Testing checklist

## Automated validation
- GitHub Actions compiles every `.lua` file under `src/` and `dist/` with the Luau compiler.
- A successful compile confirms syntax only. It does not execute Roblox APIs or simulate Delta.

## Visual engine and dashboard
- [ ] Open every dashboard tab on an iPhone-sized viewport.
- [ ] Verify touch navigation, dragging, minimize and quick-open.
- [ ] Test Ultra, Balanced and Light; confirm Restore All.
- [ ] Toggle every Custom Mode option independently and in combinations.
- [ ] Verify new descendants are processed while a mode is active.
- [ ] Test collision toggle separately; server authority may override local changes.
- [ ] Test selective texture, material and Lighting restore.
- [ ] Confirm Auto Optimizer steps down after sustained low FPS and recovers only after sustained headroom.
- [ ] Check that manual FPS markers and estimates are clearly labelled.
- [ ] Save/load a per-PlaceId profile in the same script session.

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
- [ ] Auto-refresh start/stop and no overlapping scans.
- [ ] Synchronous entry failure retry limit.
- [ ] Teleport started/failure events where exposed.

## Live runtime tests — not yet performed
- [ ] Live public server API query.
- [ ] iPhone/Delta test with the exact executor/runtime version.
- [ ] Confirm HTTP transport is available.
- [ ] Confirm TeleportToPlaceInstance is callable and permitted.
- [ ] Verify destination arrival separately from request accepted/teleport started.
- [ ] Check memory/frame-time impact of the dashboard and periodic sampling on a low-end device.

Compilation or mocked responses do not prove API availability or successful device behavior. Premium DEV has no key authentication until a backend is selected and implemented.
