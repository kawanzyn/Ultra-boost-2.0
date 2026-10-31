# Testing the private Premium DEV bundle

File: \`dist/UltraBoost-Premium-DEV.lua\`

## Why there is no one-line HTTP loader

This repository is private. A client executor's anonymous HTTP request cannot read a private GitHub repository. Do not put a personal GitHub access token in a script or loader: anyone who receives that script could extract the token.

## Manual test on a device

1. Sign in to the GitHub account that has access to this private repository.
2. Open the Premium DEV file in the repository browser.
3. Use GitHub's Raw or Download Raw action to view/download the complete \`.lua\` file.
4. Copy the complete file contents or import the downloaded file into the executor's script editor, if that editor supports file import.
5. Execute the file in a client session. Do not use the public Basic loader; that points to a different script.

If the executor only accepts a remote URL, use a private hosting method supported by that executor, or explicitly authorize a separate public test mirror. Do not publish the private file by accident.

## What to verify

- Dashboard opens with Home, Visual, Auto, Lab, Servers, Restore, Profiles and Settings.
- Touch navigation, dragging, minimize and Quick HUD.
- Ultra, Balanced, Light, Custom Mode and Restore All.
- Auto Optimizer thresholds and stability protection.
- Performance Lab values and manual benchmark markers.
- Server Finder modes, pagination/results, refresh, stats/history and entry state messages.

## Test boundaries

This is a keyless internal DEV build. It does not contain production key authentication, a license backend, or monetized key acquisition. The GitHub Actions workflow compiles Luau syntax; live HTTP access, server listing and teleport behavior still require runtime testing. A teleport request or initiation event is not proof that the destination was entered.
