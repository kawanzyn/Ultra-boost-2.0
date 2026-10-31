# Changelog

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
