-- =============================================================================
-- Chicago Traffic Crash Analytics - data quality checks
--
-- How to run (from the project folder, with the containers running):
--   docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < sql/quality_checks.sql
--
-- Every check returns ONE row: check name, layer, severity, number of failing
-- rows and a description. failed_rows = 0 means the check passed.
--   severity = 'ERROR' -> must be fixed before data is trusted
--   severity = 'WARN'  -> known source issue; handle in transformation / document
--   severity = 'INFO'  -> profiling figure, not a failure
--
-- In Phase 1 the tables are empty, so every check returns 0. The checks are
-- written now so Phase 2 (ingestion) and Phase 3 (Kestra) can run them after
-- every load.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PART A: staging.crashes_raw (raw text, straight from the CSV/API)
-- -----------------------------------------------------------------------------
SELECT 'A01 raw: row count' AS check_name, 'staging' AS layer, 'INFO' AS severity,
       COUNT(*) AS failed_rows,
       'Total rows loaded into staging (compare with the API count).' AS description
FROM staging.crashes_raw

UNION ALL
SELECT 'A02 raw: missing crash_record_id', 'staging', 'ERROR', COUNT(*),
       'Rows without the primary identifier cannot be loaded into core.'
FROM staging.crashes_raw
WHERE crash_record_id IS NULL OR btrim(crash_record_id) = ''

UNION ALL
SELECT 'A03 raw: duplicate crash_record_id', 'staging', 'ERROR', COALESCE(SUM(n - 1), 0),
       'Extra copies of the same crash (e.g. a file loaded twice, or amended reports).'
FROM (SELECT crash_record_id, COUNT(*) AS n
      FROM staging.crashes_raw
      GROUP BY crash_record_id
      HAVING COUNT(*) > 1) d

UNION ALL
SELECT 'A04 raw: missing crash_date', 'staging', 'ERROR', COUNT(*),
       'crash_date is required (NOT NULL in core.crashes).'
FROM staging.crashes_raw
WHERE crash_date IS NULL OR btrim(crash_date) = ''

UNION ALL
SELECT 'A05 raw: non-numeric injury counts', 'staging', 'ERROR', COUNT(*),
       'injuries_total must be empty or a whole number before casting to SMALLINT.'
FROM staging.crashes_raw
WHERE injuries_total IS NOT NULL AND btrim(injuries_total) <> ''
  AND btrim(injuries_total) !~ '^[0-9]+$'

UNION ALL
SELECT 'A06 raw: unexpected damage label', 'staging', 'ERROR', COUNT(*),
       'damage must be one of the 3 labels in core.damage_category.'
FROM staging.crashes_raw r
WHERE r.damage IS NOT NULL
  AND r.damage NOT IN (SELECT damage_category_name FROM core.damage_category)

-- -----------------------------------------------------------------------------
-- PART B: core.crashes (typed and cleaned)
-- -----------------------------------------------------------------------------
UNION ALL
SELECT 'B01 core: row count', 'core', 'INFO', COUNT(*),
       'Rows in core.crashes.'
FROM core.crashes

UNION ALL
SELECT 'B02 core: crashes before full coverage (< 2017-09-01)', 'core', 'WARN', COUNT(*),
       'Citywide data only starts in Sept 2017; earlier rows cover some districts only. Exclude from trends.'
FROM core.crashes
WHERE crash_date < DATE '2017-09-01'

UNION ALL
SELECT 'B03 core: crash_date in the future', 'core', 'ERROR', COUNT(*),
       'A crash cannot happen after the load time.'
FROM core.crashes
WHERE crash_date > now()::TIMESTAMP

UNION ALL
SELECT 'B04 core: police notified before crash', 'core', 'WARN', COUNT(*),
       'date_police_notified earlier than crash_date (data-entry error or estimated date).'
FROM core.crashes
WHERE date_police_notified < crash_date

UNION ALL
SELECT 'B05 core: hour/day/month do not match crash_date', 'core', 'WARN', COUNT(*),
       'Derived source columns must agree with crash_date (DOW: 1 = Sunday).'
FROM core.crashes
WHERE crash_hour        <> EXTRACT(HOUR  FROM crash_date)
   OR crash_month       <> EXTRACT(MONTH FROM crash_date)
   OR crash_day_of_week <> EXTRACT(DOW   FROM crash_date) + 1

UNION ALL
SELECT 'B06 core: injury breakdown does not add up', 'core', 'WARN', COUNT(*),
       'fatal + incapacitating + non_incapacitating + reported_not_evident should equal injuries_total.'
FROM core.crashes
WHERE injuries_total IS NOT NULL
  AND injuries_total <> COALESCE(injuries_fatal, 0) + COALESCE(injuries_incapacitating, 0)
                      + COALESCE(injuries_non_incapacitating, 0) + COALESCE(injuries_reported_not_evident, 0)

UNION ALL
SELECT 'B07 core: missing injury counts', 'core', 'WARN', COUNT(*),
       'injuries_total is NULL; these crashes count as non-injury in the views.'
FROM core.crashes
WHERE injuries_total IS NULL

UNION ALL
SELECT 'B08 core: missing coordinates', 'core', 'WARN', COUNT(*),
       'No latitude/longitude; crash cannot be mapped.'
FROM core.crashes
WHERE latitude IS NULL OR longitude IS NULL

UNION ALL
SELECT 'B09 core: coordinates outside Chicago', 'core', 'WARN', COUNT(*),
       'Coordinates outside an approximate Chicago bounding box (lat 41.6-42.1, lon -88.0 to -87.5), incl. 0,0.'
FROM core.crashes
WHERE latitude IS NOT NULL AND longitude IS NOT NULL
  AND NOT (latitude BETWEEN 41.6 AND 42.1 AND longitude BETWEEN -88.0 AND -87.5)

UNION ALL
SELECT 'B10 core: unusual posted speed limit', 'core', 'WARN', COUNT(*),
       'Speed limit above 70 mph or not a multiple of 5 (likely typing errors).'
FROM core.crashes
WHERE posted_speed_limit > 70 OR posted_speed_limit % 5 <> 0

UNION ALL
SELECT 'B11 core: unusual lane count', 'core', 'WARN', COUNT(*),
       'lane_cnt above 12 is not realistic for city streets.'
FROM core.crashes
WHERE lane_cnt > 12

UNION ALL
SELECT 'B12 core: undetermined primary cause', 'core', 'INFO', COUNT(*),
       'Crashes whose primary cause is UNABLE TO DETERMINE / NOT APPLICABLE (excluded from Q2).'
FROM core.crashes c
JOIN core.contributory_cause cc ON cc.contributory_cause_id = c.prim_contributory_cause_id
WHERE cc.is_undetermined

UNION ALL
SELECT 'B13 core: unknown weather or lighting', 'core', 'INFO', COUNT(*),
       'Crashes with UNKNOWN weather or lighting (excluded from Q3).'
FROM core.crashes c
LEFT JOIN core.weather_condition  w ON w.weather_condition_id  = c.weather_condition_id
LEFT JOIN core.lighting_condition l ON l.lighting_condition_id = c.lighting_condition_id
WHERE w.weather_condition_name = 'UNKNOWN' OR l.lighting_condition_name = 'UNKNOWN'

-- -----------------------------------------------------------------------------
-- PART C: staging vs core reconciliation
-- -----------------------------------------------------------------------------
UNION ALL
SELECT 'C01 recon: raw ids missing from core', 'recon', 'ERROR', COUNT(*),
       'Every valid raw crash_record_id should exist in core.crashes after transformation.'
FROM (SELECT DISTINCT crash_record_id FROM staging.crashes_raw
      WHERE crash_record_id IS NOT NULL AND btrim(crash_record_id) <> '') r
LEFT JOIN core.crashes c ON c.crash_record_id = r.crash_record_id
WHERE c.crash_record_id IS NULL

ORDER BY check_name;
