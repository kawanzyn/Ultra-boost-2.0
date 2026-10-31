# Compatibility

## Visual engine and dashboard
The Basic distribution preserves the earlier v0.4.0 client-side visual engine. The Premium DEV bundle includes the same reversible visual engine inside a new responsive multi-page dashboard. Prior user testing reported the three visual profiles, buttons and texture restoration working in that user's runtime; this is not a universal compatibility guarantee.

The dashboard is built with standard client UI services and touch/mouse input. Device-specific layout, executor restrictions and performance still require testing. FPS values are client Heartbeat estimates, not hardware telemetry or a guarantee of rendered FPS. Benchmark entries are manually recorded rolling averages.

## Server Finder
The HTTP adapter probes request/http_request, syn.request, http.request, game:HttpGet or HttpService:GetAsync. Availability and permission depend on the runtime. If no transport works, the Finder reports an error rather than fabricating results.

The EntryAdapter checks TeleportToPlaceInstance availability and wraps calls in pcall. Method exposure does not prove that teleporting is permitted. A submitted request is not treated as a confirmed arrival.

Missing ping/fps values remain unavailable. Reported ping is not guaranteed to equal the player's actual latency. Oldest Empty uses local observations rather than actual instance creation time or exact time empty.

Game Profiles are in-memory for the active script session only. The Premium DEV bundle currently has no key protection or licensing backend.

No anti-cheat bypass, server-side mutation or remote-event abuse is implemented.
