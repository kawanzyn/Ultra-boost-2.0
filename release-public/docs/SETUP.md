# Setup — UltraBoost Basic

## Roblox Studio

For an experience you own or are authorized to edit:

1. Download `dist/UltraBoost-Basic.lua`.
2. In Roblox Studio, create a **LocalScript** under `StarterPlayer > StarterPlayerScripts`.
3. Paste the complete script contents into that LocalScript.
4. Run a client test session.
5. Use the UltraBoost panel to select a profile. Use **Restore Original** before removing or disabling the script.

The script uses `Players.LocalPlayer` and `PlayerGui`, so it must run in a client context. It will stop with a warning if those client objects are unavailable.

## Existing Basic loader compatibility

The root-level `UltraBoost.lua` file is retained for older Basic loaders. It is kept byte-for-byte identical to `dist/UltraBoost-Basic.lua`.

## Notes

- Only one Basic panel can run per PlayerGui at a time.
- The panel can be dragged with touch or mouse and minimized.
- The FPS value is an estimate based on client frame updates.
- Use the script only where local scripts are permitted.
