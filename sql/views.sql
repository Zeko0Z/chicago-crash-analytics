-- =============================================================================
-- Chicago Traffic Crash Analytics - analytics views (Phase 1 design)
-- These views answer the three analytical questions in docs/proposal.md.
-- They are created now so the design is testable; they return rows only after
-- the Phase 2 ingestion has filled core.crashes.
--
-- Analysis window: 2018-01-01 to 2025-12-31 (eight complete calendar years).
--   * Citywide coverage only starts in September 2017 (source documentation).
--   * The current year is incomplete and the dataset is updated daily.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Base view: crashes joined to every lookup table, with helper flags
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_crashes_enriched AS
SELECT
    c.crash_record_id,
    c.crash_date,
    c.crash_year,
    c.crash_month,
    c.crash_hour,
    c.crash_day_of_week,
    CASE c.crash_day_of_week
        WHEN 1 THEN 'Sunday'    WHEN 2 THEN 'Monday'  WHEN 3 THEN 'Tuesday'
        WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday'
        WHEN 7 THEN 'Saturday'
    END                                         AS day_name,
    w.weather_condition_name                    AS weather_condition,
    l.lighting_condition_name                   AS lighting_condition,
    s.roadway_surface_condition_name            AS roadway_surface_condition,
    f.first_crash_type_name                     AS first_crash_type,
    pc.contributory_cause_name                  AS prim_contributory_cause,
    pc.is_undetermined                          AS prim_cause_is_undetermined,
    sc.contributory_cause_name                  AS sec_contributory_cause,
    d.damage_category_name                      AS damage_category,
    d.sort_order                                AS damage_sort_order,
    c.crash_type,
    c.posted_speed_limit,
    c.num_units,
    c.hit_and_run_i,
    c.injuries_total,
    c.injuries_fatal,
    c.injuries_incapacitating,
    c.latitude,
    c.longitude,
    -- helper flags used by the questions
    (COALESCE(c.injuries_total, 0) > 0)                                       AS is_injury_crash,
    (COALESCE(c.injuries_fatal, 0) + COALESCE(c.injuries_incapacitating, 0) > 0) AS is_severe_crash,
    (c.crash_date >= DATE '2018-01-01' AND c.crash_date < DATE '2026-01-01')  AS in_analysis_window
FROM core.crashes c
LEFT JOIN core.weather_condition         w  ON w.weather_condition_id         = c.weather_condition_id
LEFT JOIN core.lighting_condition        l  ON l.lighting_condition_id        = c.lighting_condition_id
LEFT JOIN core.roadway_surface_condition s  ON s.roadway_surface_condition_id = c.roadway_surface_condition_id
LEFT JOIN core.first_crash_type          f  ON f.first_crash_type_id          = c.first_crash_type_id
LEFT JOIN core.contributory_cause        pc ON pc.contributory_cause_id       = c.prim_contributory_cause_id
LEFT JOIN core.contributory_cause        sc ON sc.contributory_cause_id       = c.sec_contributory_cause_id
LEFT JOIN core.damage_category           d  ON d.damage_category_id           = c.damage_category_id;

COMMENT ON VIEW analytics.v_crashes_enriched IS 'All crashes with lookup labels and helper flags. Base for every other view.';

-- -----------------------------------------------------------------------------
-- Q1. At which hours of the day and days of the week are crashes most likely
--     to cause injuries? (168 rows: 7 days x 24 hours)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_q1_injury_rate_by_day_hour AS
SELECT
    crash_day_of_week,
    day_name,
    crash_hour,
    COUNT(*)                                                     AS crash_count,
    COUNT(*) FILTER (WHERE is_injury_crash)                      AS injury_crash_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_injury_crash) / COUNT(*), 2)        AS injury_crash_pct,
    ROUND(1000.0 * COUNT(*) FILTER (WHERE is_severe_crash) / COUNT(*), 2)       AS severe_crashes_per_1000,
    RANK() OVER (ORDER BY 1.0 * COUNT(*) FILTER (WHERE is_injury_crash) / COUNT(*) DESC) AS injury_rate_rank
FROM analytics.v_crashes_enriched
WHERE in_analysis_window
  AND crash_hour IS NOT NULL
  AND crash_day_of_week IS NOT NULL
GROUP BY crash_day_of_week, day_name, crash_hour;

COMMENT ON VIEW analytics.v_q1_injury_rate_by_day_hour IS
    'Q1: crash volume, injury-crash percentage and severe crashes per 1,000 for each day-of-week x hour cell (2018-2025).';

-- -----------------------------------------------------------------------------
-- Q2. Which primary contributory causes lead to the most severe outcomes?
--     Causes with fewer than 1,000 crashes are excluded so rates are stable.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_q2_cause_severity AS
SELECT
    prim_contributory_cause,
    COUNT(*)                                                     AS crash_count,
    SUM(COALESCE(injuries_fatal, 0))                             AS fatalities,
    SUM(COALESCE(injuries_incapacitating, 0))                    AS incapacitating_injuries,
    ROUND(100.0 * COUNT(*) FILTER (WHERE is_injury_crash) / COUNT(*), 2)  AS injury_crash_pct,
    ROUND(1000.0 * COUNT(*) FILTER (WHERE is_severe_crash) / COUNT(*), 2) AS severe_crashes_per_1000,
    RANK() OVER (ORDER BY 1.0 * COUNT(*) FILTER (WHERE is_severe_crash) / COUNT(*) DESC) AS severity_rank
FROM analytics.v_crashes_enriched
WHERE in_analysis_window
  AND prim_contributory_cause IS NOT NULL
  AND NOT prim_cause_is_undetermined
GROUP BY prim_contributory_cause
HAVING COUNT(*) >= 1000;

COMMENT ON VIEW analytics.v_q2_cause_severity IS
    'Q2: severity metrics per primary contributory cause (2018-2025, causes with >= 1,000 crashes, undetermined causes excluded).';

-- -----------------------------------------------------------------------------
-- Q3. How do weather and lighting conditions change the chance of an injury
--     crash, compared with the overall average?
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_q3_weather_lighting_risk AS
WITH base AS (
    SELECT weather_condition, lighting_condition, is_injury_crash, damage_category
    FROM analytics.v_crashes_enriched
    WHERE in_analysis_window
      AND weather_condition  IS NOT NULL AND weather_condition  <> 'UNKNOWN'
      AND lighting_condition IS NOT NULL AND lighting_condition <> 'UNKNOWN'
),
overall AS (
    SELECT AVG(CASE WHEN is_injury_crash THEN 1.0 ELSE 0.0 END) AS overall_injury_rate
    FROM base
)
SELECT
    b.weather_condition,
    b.lighting_condition,
    COUNT(*)                                                             AS crash_count,
    ROUND(100.0 * COUNT(*) FILTER (WHERE b.is_injury_crash) / COUNT(*), 2)        AS injury_crash_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE b.damage_category = 'OVER $1,500') / COUNT(*), 2) AS over_1500_damage_pct,
    ROUND((1.0 * COUNT(*) FILTER (WHERE b.is_injury_crash) / COUNT(*))
          / NULLIF(MAX(o.overall_injury_rate), 0), 2)                    AS relative_injury_risk
FROM base b
CROSS JOIN overall o
GROUP BY b.weather_condition, b.lighting_condition
HAVING COUNT(*) >= 500;

COMMENT ON VIEW analytics.v_q3_weather_lighting_risk IS
    'Q3: injury-crash percentage, high-damage percentage and relative risk (1.00 = average) per weather x lighting combination (2018-2025, >= 500 crashes).';

-- -----------------------------------------------------------------------------
-- Dashboard helper: monthly trend (all complete data from Sept 2017 onwards)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW analytics.v_monthly_trend AS
SELECT
    DATE_TRUNC('month', crash_date)::DATE                        AS month_start,
    COUNT(*)                                                     AS crash_count,
    COUNT(*) FILTER (WHERE is_injury_crash)                      AS injury_crash_count,
    SUM(COALESCE(injuries_total, 0))                             AS people_injured,
    SUM(COALESCE(injuries_fatal, 0))                             AS fatalities
FROM analytics.v_crashes_enriched
WHERE crash_date >= DATE '2017-09-01'
GROUP BY DATE_TRUNC('month', crash_date)::DATE;

COMMENT ON VIEW analytics.v_monthly_trend IS 'Monthly crash and injury totals for dashboard trend charts (from September 2017, when citywide coverage begins).';
