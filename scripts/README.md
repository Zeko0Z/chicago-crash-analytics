# scripts/ – Python ingestion (Phase 2, not built yet)

This folder will hold the Python code that moves data from the Chicago Data Portal into PostgreSQL. **No ingestion code exists in Phase 1** – this file describes the plan so the database design and the code match.

## Planned files

| File | Job |
|---|---|
| `requirements.txt` | `requests`, `pandas`, `psycopg[binary]`, `python-dotenv` |
| `extract.py` | Download the data: full CSV export (first load) or the SODA JSON API with paging (daily incremental loads). |
| `load_staging.py` | Bulk-load raw rows into `staging.crashes_raw` with `COPY` (fast for ~1.1 M rows). |
| `transform_core.py` | Fill lookup tables, cast types, convert `Y`/`N` to `BOOLEAN`, and upsert into `core.crashes`. |
| `config.py` | Read connection settings from `.env` (same variables as `docker-compose.yml`). |

## Planned approach

1. **Extract**
   - Full load: `https://data.cityofchicago.org/api/views/85ca-t3if/rows.csv?accessType=DOWNLOAD` (large file, several hundred MB).
   - Incremental load: `https://data.cityofchicago.org/resource/85ca-t3if.json` with `$limit`, `$offset`, `$order=crash_record_id` and a `$where` filter on the last load date. An optional free Socrata app token raises the rate limit.
   - Save raw files under `data/raw/` (ignored by Git).
2. **Load to staging** – every value as text, plus `_source_file` and `_loaded_at`. Nothing is rejected at this step.
3. **Quality gate** – run `sql/quality_checks.sql`. Stop if any `ERROR` check fails.
4. **Transform to core**
   - Insert new labels into the lookup tables (`INSERT … ON CONFLICT DO NOTHING`).
   - Mark `UNABLE TO DETERMINE` and `NOT APPLICABLE` as `is_undetermined = TRUE` in `core.contributory_cause`.
   - Parse dates in the CSV format `MM/DD/YYYY HH:MI:SS AM` (the JSON API uses ISO 8601).
   - Upsert into `core.crashes` with `ON CONFLICT (crash_record_id) DO UPDATE`, because the City amends existing reports.
5. **Connection** – from your computer use `localhost:${POSTGRES_PORT}`; from another container on `crashes_net` use host `postgres`, port `5432`.
