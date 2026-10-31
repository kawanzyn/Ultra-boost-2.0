# Testing — UltraBoost Basic

## Automated validation

The public GitHub Actions workflow compiles the Lua files found under `src/` and `dist/`. The public Basic repository intentionally contains no `src/` tree and only the Basic artifact in `dist/`, so the public workflow validates the Basic distribution.

Before publishing, the private release workflow also checks that the legacy root-level `UltraBoost.lua` file is byte-for-byte identical to `dist/UltraBoost-Basic.lua`.

A successful compile verifies syntax only. It does not run Roblox APIs or prove device compatibility.

## Manual client checklist

- [ ] Run in a client context with `LocalPlayer` and `PlayerGui`.
- [ ] Confirm the panel appears once and duplicate execution is safely rejected.
- [ ] Test Ultra, Balanced and Light.
- [ ] Confirm the environment collision toggle can be enabled and disabled.
- [ ] Use Restore Original and compare the environment with its original state.
- [ ] Verify the FPS monitor can be toggled.
- [ ] Test dragging and minimizing with touch and mouse.
- [ ] Test on a small-screen device and a lower-powered device.
- [ ] Observe frame-time and memory impact in the target experience.

## Not covered by compilation

Live behavior varies by experience and runtime. A syntax check cannot establish that the script improves FPS or works identically on every device.
