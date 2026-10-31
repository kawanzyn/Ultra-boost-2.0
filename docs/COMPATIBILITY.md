# Compatibility

## Visual engine and dashboard
The Basic distribution preserves the earlier v0.4.0 client-side visual engine. The Premium DEV bundle includes the same reversible visual engine inside a new responsive multi-page dashboard. Prior user testing reported the three visual profiles, buttons and texture restoration working in that user's runtime; this is not a universal compatibility guarantee.

The dashboard is built with standard client UI services and touch/mouse input. Its code is not iOS-only: it uses client services intended to run on both Android and iOS, but runtime/executor compatibility and performance must be tested on each device. FPS sampling prefers `RunService.PreRender` (with `Heartbeat` fallback), so it estimates client render cadence before the frame is drawn; it is not an operating-system/compositor presentation measurement or hardware telemetry. Benchmark entries are manually recorded rolling averages. The visual engine also handles eligible `MeshPart.TextureID` and `SpecialMesh.TextureId` textures, with original values retained for restoration. This still cannot remove mesh geometry, rewrite the game's own scripts, change the device's thermal/power limits, or guarantee higher FPS.

The standalone Premium DEV artifact in `dist/` is a single-file bundle: its internal modules must be injected through local bundle variables, not loaded with `require(script.Parent...)`. The modular source under `src/` retains its normal ModuleScript dependencies. Run the dashboard in a client context with `Players.LocalPlayer` and `PlayerGui` available. Executor-specific download, HTTP and teleport functions are optional capabilities and are not guaranteed by the Roblox client.

## Server Finder
The HTTP adapter probes request/http_request, syn.request, http.request, game:HttpGet or HttpService:GetAsync. Availability and permission depend on the runtime. If no transport works, the Finder reports an error rather than fabricating results.

The EntryAdapter checks TeleportToPlaceInstance availability and wraps calls in pcall. Method exposure does not prove that teleporting is permitted. A submitted request is not treated as a confirmed arrival.

Missing ping/fps values remain unavailable. Reported ping is not guaranteed to equal the player's actual latency. Oldest Empty uses local observations rather than actual instance creation time or exact time empty.

Game Profiles are in-memory for the active script session only. The Premium DEV bundle currently has no key protection or licensing backend.

No anti-cheat bypass, server-side mutation or remote-event abuse is implemented.
