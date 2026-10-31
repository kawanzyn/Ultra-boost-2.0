# Compatibility

## Visual engine
The migrated standalone preserves the v0.4.0 client-side implementation. Prior user testing reported the three profiles, buttons and texture restoration working in that user's runtime; this is not a universal compatibility guarantee.

## Server Finder
The HTTP adapter probes request/http_request, syn.request, http.request, game:HttpGet or HttpService:GetAsync. Availability and permission depend on the runtime. If no transport works, the Finder reports an error rather than fabricating results.

The EntryAdapter checks TeleportToPlaceInstance availability and wraps calls in pcall. Method exposure does not prove that teleporting is permitted. A submitted request is not treated as a confirmed arrival.

Missing ping/fps values remain unavailable. Reported ping is not guaranteed to equal the player's actual latency. Oldest Empty uses local observations rather than actual instance creation time or exact time empty.

No anti-cheat bypass, server-side mutation or remote-event abuse is implemented.
