# Changelog

## v2.0.0-alpha.4 — Mobile mesh optimization
- Add reversible `MeshPart.RenderFidelity = Performance` in Ultra and as a Custom Mode geometry toggle.
- Apply geometry simplification to eligible unprotected MeshParts regardless of anchoring.
- Add selective mesh-quality restoration and extend selective texture restoration to MeshPart and SpecialMesh.
- Continue to treat Android thermal, power, and device-level FPS caps as outside the Lua client's control.

## v2.0.0-alpha.3 — Mobile compatibility improvements
- Prefer client `RunService.PreRender` for FPS cadence sampling, with a `Heartbeat` fallback for older runtimes.
- Apply the Light profile immediately when Auto Optimizer is enabled from Original or Custom mode.
- Extend reversible visual texture simplification to eligible `MeshPart.TextureID` and `SpecialMesh.TextureId` instances.
- Document Android/iOS compatibility as device/runtime-dependent and add a real-device comparison checklist.
- Fix the standalone bundle's Server Finder dependency injection to use its bundled HTTP client instead of a missing sibling ModuleScript.

## v2.0.0-alpha.2 — Premium DEV dashboard
- Replaced the Basic-only visual panel in the Premium DEV bundle with a unified responsive multi-page dashboard.
- Added Home/Intelligence overview, Custom Mode controls, Auto Optimizer, Performance Lab, Server Finder, Smart Restore, Game Profiles and Settings.
- Added selectable 30/45/60 FPS targets with hysteresis to reduce rapid mode switching.
- Added session FPS average/min/max, estimated frame time, session duration, stability trace and manual benchmark markers.
- Added selective texture, material and Lighting restoration plus emergency Restore All.
- Added session-only per-PlaceId profiles, draggable touch/mouse dashboard, minimize quick button and Quick HUD.
- Embedded the latest dashboard module into the standalone Premium DEV bundle.
- Kept the Premium DEV bundle private and keyless for internal testing; no backend/license gate is active.

## v2.0.0-alpha.1
- Split keyless Basic distribution from private Premium development.
- Migrated the v0.4.0 standalone visual engine and modular source files.
- Added initial Server Finder modules for public API retrieval, pagination, cache, validation, deduplication, five filters, local observation/visit history, bounded retries, auto-refresh, statistics and guarded teleport attempts.
- Documented runtime limits and test status.

## v0.4.0 baseline
- Strong-reference property snapshots and batched restoration.
- Bounded initial scans and protected subtree skipping.
- Independent Workspace and Lighting scan generations.
- Heartbeat FPS estimate and draggable touch/mouse UI.
