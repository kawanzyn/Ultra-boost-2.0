# Server Finder modules

- HttpClient.lua: detects a public GET transport at runtime; sends no account cookies or credentials.
- Service.lua: validated API pages, cursor pagination, cache, deduplication, filters, balanced scoring, local history, statistics, backoff and auto-refresh.
- EntryAdapter.lua: probes TeleportToPlaceInstance and records request/start/failure states without claiming an accepted call means successful entry.
- Controller.lua: mobile-friendly panel with five modes, population filter, visited-server exclusion, refresh, server cards, entry attempts and statistics.

Balanced scoring uses occupancy ratio (playing/maxPlayers) at weight 0.60 and reported ping at weight 0.40. The weights are renormalized when a metric is missing. No values are invented. Oldest Empty uses locally observed empty-state history, not actual server age.

History/cache are currently session-memory only. HTTP and teleport availability vary by runtime. See docs/SERVER_FINDER.md and docs/TESTING.md.
