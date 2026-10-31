# Compatibility — UltraBoost Basic

## Runtime

UltraBoost Basic is a standalone Luau client script that uses standard Roblox client APIs. It expects a valid `Players.LocalPlayer` and that player's `PlayerGui`.

The script is intended for a LocalScript/client context in an experience you own or are authorized to modify. Runtime restrictions and experience-specific behavior can still prevent individual changes from applying.

## What the modes change

The visual profiles may adjust eligible environmental materials, textures, effects, terrain decoration/colors, lighting shadows and local transparency. The script uses conservative name/class checks to avoid many gameplay-related objects, but no heuristic can identify every custom object in every experience.

## Performance and authority limits

- FPS is estimated from Heartbeat updates; it is not a hardware-level or rendered-frame benchmark.
- Visual changes are local to the client.
- The script cannot guarantee a fixed frame rate, a specific RAM reduction, lower server load or lower network latency.
- Local collision changes may be ignored or overridden by server authority.
- The script does not modify server-owned state, invoke remote events, delete game instances or bypass anti-cheat systems.

## Restoration

The script records original values before changing supported properties and provides a restore action. Restoration is best-effort: properties that could not be read or changed may not be recoverable, and other scripts may independently modify the same properties during the session.
