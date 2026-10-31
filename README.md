# UltraBoost 2.0

This private repository is the canonical source and development workspace for UltraBoost. It contains the Premium development line and shared visual-engine work.

## Product split

- **UltraBoost Basic:** public, keyless distribution in [kawanzyn/Ultra-boost-2.0-Release](https://github.com/kawanzyn/Ultra-boost-2.0-Release).
- **UltraBoost Premium DEV:** private internal test bundle at `dist/UltraBoost-Premium-DEV.lua`. It has no active key gate and is not a commercial release.
- **Premium licensing:** backend validation, device limits, revocation and monetized key acquisition remain planned work. No fake client-side key check is used.

## Premium DEV 2.0 features in the current bundle

- Unified responsive dashboard with Home, Optimizer, Auto, Performance Lab, Server Finder, Smart Restore, Game Profiles and Settings.
- Custom Mode controls for textures, decals, effects, vegetation, material simplification, shadows and environment visibility.
- Auto Optimizer with 30/45/60 FPS targets and stability hysteresis.
- Performance Lab with current/average/min/max FPS estimates, session duration, estimated frame time, a recent stability trace, and manual baseline/optimized markers.
- Server Finder with Empty Server, Low Population, Oldest Empty, Low Ping and Balanced filters; maximum population setting; recent-visit exclusion; refresh/history/statistics; optional 30-second auto-refresh; bounded entry attempts.
- Smart Restore for textures, materials and Lighting, plus Restore All.
- Quick HUD and session-only profiles keyed by PlaceId.

## Important limits

All visual changes are local client changes. FPS is estimated from client frame updates; benchmark markers are manual samples, not a controlled performance lab. The script cannot promise a fixed frame rate, free RAM, lower server load or lower network latency.

Server Finder relies on the public server-list endpoint and whatever HTTP/teleport capabilities the runtime exposes. Missing ping/FPS values remain unavailable. "Oldest Empty" means the earliest locally observed empty sequence, not actual server creation time. A teleport request or "started" signal is not proof of arrival.

Game Profiles currently persist only in the current script session. Premium DEV has no key protection or licensing backend. Do not embed a personal GitHub token in a client loader.

## Repository layout

- `src/`: modular client engine and Premium dashboard development source.
- `src/ServerFinder/`: HTTP adapter, discovery, ranking, observation history and entry adapter.
- `dist/UltraBoost-Basic.lua`: keyless public Basic artifact.
- `dist/UltraBoost-Premium-DEV.lua`: private standalone Premium development build.
- `release-public/`: curated staging area for the public Basic repository only.
- `docs/RELEASE_POLICY.md`: public-release allowlist and files that must remain private.
- `docs/`: internal design, compatibility and test notes.

The public sync workflow publishes only `release-public/`, `LICENSE`, and `dist/UltraBoost-Basic.lua` (as both the `dist/` artifact and legacy root `UltraBoost.lua`). It does not mirror the private repository. Premium files, `src/`, and internal development documentation remain private.

The original `UltraBoost` and `UltraBoost-Release-` repositories were not modified.
