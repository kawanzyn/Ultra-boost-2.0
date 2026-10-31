# Testing — UltraBoost Basic

## Automated validation

The public GitHub Actions workflow compiles both Basic distribution files with the Luau compiler and checks that the legacy root file matches the file in `dist/`.

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
