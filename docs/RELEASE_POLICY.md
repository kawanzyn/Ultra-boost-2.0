# Release policy

The private repository is the canonical source and development workspace.

## Public release allowlist

The public repository is a Basic-only distribution. The sync workflow publishes only:

- `release-public/README.md` as the public root README.
- `release-public/CHANGELOG.md` as the public changelog.
- `release-public/docs/**` as Basic-only documentation.
- `LICENSE` as the Basic distribution license.
- `dist/UltraBoost-Basic.lua` as `dist/UltraBoost-Basic.lua` and the legacy root-level `UltraBoost.lua`.

The existing public `.github/workflows/luau-validation.yml` is preserved in place and is not rewritten by the sync workflow. This avoids granting the release token permission to modify GitHub Actions workflow files. The private publisher validates that the root Basic file and the `dist/` copy are identical before pushing.

## Never publish

The following remain private and must not be copied into the public release:

- `dist/UltraBoost-Premium-DEV.lua`
- `src/**`, including the Premium dashboard and Server Finder modules.
- Premium-only documentation, test plans, licensing/backend work and internal implementation notes.
- Repository secrets, tokens, credentials or private configuration.

The sync workflow replaces the public repository contents from the curated staging directory on every release, while explicitly preserving only the existing public CI workflow. A guard fails the workflow if Premium/Server Finder/source paths appear in the resulting public tree.

## Changing the public surface

Any new file intended for the public release must be added deliberately to `release-public/` and documented here. Do not change the workflow back to mirroring the entire private repository.
