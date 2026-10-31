# Release policy

The private repository is the canonical source and development workspace.

## Public release allowlist

The public repository is a Basic-only distribution. The sync workflow publishes only:

- `release-public/README.md` as the public root README.
- `release-public/CHANGELOG.md` as the public changelog.
- `release-public/docs/**` as Basic-only documentation.
- `release-public/.github/workflows/luau-validation.yml` as the public Basic validation workflow.
- `LICENSE` as the Basic distribution license.
- `dist/UltraBoost-Basic.lua` as `dist/UltraBoost-Basic.lua` and the legacy root-level `UltraBoost.lua`.

## Never publish

The following remain private and must not be copied into the public release:

- `dist/UltraBoost-Premium-DEV.lua`
- `src/**`, including the Premium dashboard and Server Finder modules.
- Premium-only documentation, test plans, licensing/backend work and internal implementation notes.
- Repository secrets, tokens, credentials or private configuration.

The sync workflow replaces the public repository contents from the allowlisted staging directory on every release. A guard fails the workflow if Premium/Server Finder/source paths appear in the resulting public tree.

## Changing the public surface

Any new file intended for the public release must be added deliberately to `release-public/` and documented here. Do not change the workflow back to mirroring the entire private repository.
