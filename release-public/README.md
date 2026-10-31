# UltraBoost Basic

UltraBoost Basic is the free, keyless client-side visual tuning edition of UltraBoost.

## Features

- **Ultra:** strongest supported local environment simplification.
- **Balanced:** a middle-ground visual profile.
- **Light:** lightweight material and texture simplification.
- **Environment collision toggle:** optional local collision changes for eligible environmental parts.
- **FPS monitor:** approximate client frame-rate sampling.
- **Restore:** restores the properties recorded by the script.
- **Touch and mouse support:** draggable panel with minimize and restore controls.

## Download

- [Standalone Basic script](dist/UltraBoost-Basic.lua)
- [Legacy root file](UltraBoost.lua)

The root-level `UltraBoost.lua` is kept for compatibility with existing Basic loaders. It is identical to `dist/UltraBoost-Basic.lua`.

## Installation

See [Setup](docs/SETUP.md) and [Compatibility](docs/COMPATIBILITY.md).

## Important limitations

UltraBoost Basic changes eligible properties locally on the client. It does not remove server-side work, guarantee a fixed FPS, free a specific amount of RAM, reduce network latency, or bypass anti-cheat systems. Actual results depend on the experience, device, and runtime.

Use it only in experiences and client environments where local scripts are permitted. A server may override local collision behavior.

## License

The public Basic distribution is provided under the MIT License. See [LICENSE](LICENSE).
