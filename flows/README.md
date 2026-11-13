# flows/ – Kestra orchestration (Phase 3, not built yet)

This folder will hold the Kestra flow definitions (YAML). **No flows exist in Phase 1.**

## Planned flow: `chicago_crashes_daily`

| Step | Task | What it does |
|---|---|---|
| 1 | Schedule trigger | Runs once a day (the source is updated daily). |
| 2 | Python script task | Runs the Phase 2 ingestion (`scripts/`) for new and amended crashes. |
| 3 | PostgreSQL query task | Runs `sql/quality_checks.sql`; fails the run if any `ERROR` check has `failed_rows > 0`. |
| 4 | PostgreSQL query task | Refreshes reporting objects (e.g. materialized versions of the `analytics` views if needed for speed). |
| 5 | Notification | Sends an alert when a run fails, with the failed check names. |

## Planned set-up

- Kestra will be added as a third service in `docker-compose.yml` on the same `crashes_net` network, so it reaches the database at host `postgres`, port `5432`.
- Database credentials will be passed to Kestra as secrets from `.env`, never written in the flow files.
- Retries with back-off will handle temporary API errors.
