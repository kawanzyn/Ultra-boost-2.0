# Setup

## Basic

The keyless standalone is `dist/UltraBoost-Basic.lua`. The curated public release is staged under `release-public/` and published to `kawanzyn/Ultra-boost-2.0-Release` as:

- `dist/UltraBoost-Basic.lua`
- `UltraBoost.lua` (legacy root path, byte-for-byte identical to the Basic artifact)

The public release contains Basic-only documentation and validation. It does not receive Premium source, the Premium DEV bundle, or internal development notes.

## Premium development

The modular visual-engine development source is under `src/`. Server Finder modules are under `src/ServerFinder/`. The standalone internal preview at `dist/UltraBoost-Premium-DEV.lua` includes the integrated dashboard and Server Finder, but the modular source is not yet connected to a reproducible build process. Do not assume that editing a module automatically regenerates the standalone bundle.

## Keys and monetization

Basic remains keyless. Premium key validation must be server-side. Do not embed administrator tokens, signing secrets or provider credentials in a client script. The monetized acquisition website depends on selecting a provider and implementing its verification callback.

## Internal Premium DEV preview

Use `dist/UltraBoost-Premium-DEV.lua` only for private runtime tests. It has no key verification, activation website or monetized key flow. It must not be copied into the public Basic release.
