# UltraBoost 2.0

This private repository is the development source for the Premium product and the shared visual engine.

## Product split

- **UltraBoost Basic:** public, keyless distribution in kawanzyn/Ultra-boost-2.0-Release.
- **UltraBoost Premium:** private development line; key verification and monetized key acquisition are planned separately.

## Preserved v0.4.0 visual engine

The Basic baseline carries forward the working three visual profiles, texture/decal/SurfaceAppearance restoration, independent optional environmental collision control, FPS estimate, touch-friendly panel, incremental scanning and batched restoration.

## Premium roadmap

- Server Finder: public server list, five search modes, filters, pagination, cache, history, auto-refresh, statistics, and runtime-dependent entry attempts.
- Custom Mode and visual presets.
- Auto Optimizer and Performance Lab.
- Smart Restore, Game Profiles and Quick Panel.
- Server-side key validation and monetized key acquisition.

## Repository layout

- src/: modular visual engine.
- src/ServerFinder/: Premium server discovery, ranking, observation history, entry adapter and UI.
- dist/UltraBoost-Basic.lua: keyless standalone baseline.
- docs/: design and validation notes.

The original UltraBoost and UltraBoost-Release repositories are unchanged. This repository does not yet contain a final standalone Premium bundle or a completed key backend. Server Finder source modules are an initial implementation; live API and target-runtime tests are still pending.
