-- =============================================================================
-- Chicago Traffic Crash Analytics - PostgreSQL schema (Phase 1)
-- Source dataset : City of Chicago Data Portal - "Traffic Crashes - Crashes"
--                  https://data.cityofchicago.org/d/85ca-t3if  (dataset id 85ca-t3if)
-- Target         : PostgreSQL 16
--
-- Layers
--   staging.*  : raw landing zone. One TEXT column per source CSV column, so the
--                Phase 2 Python ingestion can load files without type errors.
--   core.*     : cleaned, typed, normalized tables (lookup tables + crashes).
--   analytics.*: views for the analytical questions (created in views.sql).
--
-- This script is safe to run more than once (IF NOT EXISTS / ON CONFLICT).
-- It runs automatically the first time the PostgreSQL container starts
-- (mounted into /docker-entrypoint-initdb.d by docker-compose.yml).
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS analytics;

COMMENT ON SCHEMA staging   IS 'Raw landing zone: source CSV/API data stored as text, untouched.';
COMMENT ON SCHEMA core      IS 'Cleaned, typed and normalized crash data.';
COMMENT ON SCHEMA analytics IS 'Reporting views used by the dashboard and analytical questions.';

-- -----------------------------------------------------------------------------
-- 1. STAGING: raw crashes, exactly as published (49 public columns, all TEXT)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS staging.crashes_raw (
    crash_record_id                 TEXT,
    crash_date_est_i                TEXT,
    crash_date                      TEXT,
    posted_speed_limit              TEXT,
    traffic_control_device          TEXT,
    device_condition                TEXT,
    weather_condition               TEXT,
    lighting_condition              TEXT,
    first_crash_type                TEXT,
    trafficway_type                 TEXT,
    lane_cnt                        TEXT,
    alignment                       TEXT,
    roadway_surface_cond            TEXT,
    road_defect                     TEXT,
    report_type                     TEXT,
    crash_type                      TEXT,
    intersection_related_i          TEXT,
    not_right_of_way_i              TEXT,  -- API field name: private_property_i
    hit_and_run_i                   TEXT,
    damage                          TEXT,
    date_police_notified            TEXT,
    prim_contributory_cause         TEXT,
    sec_contributory_cause          TEXT,
    street_no                       TEXT,
    street_direction                TEXT,
    street_name                     TEXT,
    beat_of_occurrence              TEXT,
    photos_taken_i                  TEXT,
    statements_taken_i              TEXT,
    dooring_i                       TEXT,
    work_zone_i                     TEXT,
    work_zone_type                  TEXT,
    workers_present_i               TEXT,
    num_units                       TEXT,
    most_severe_injury              TEXT,
    injuries_total                  TEXT,
    injuries_fatal                  TEXT,
    injuries_incapacitating         TEXT,
    injuries_non_incapacitating     TEXT,
    injuries_reported_not_evident   TEXT,
    injuries_no_indication          TEXT,
    injuries_unknown                TEXT,
    crash_hour                      TEXT,
    crash_day_of_week               TEXT,
    crash_month                     TEXT,
    idot_control_no                 TEXT,
    latitude                        TEXT,
    longitude                       TEXT,
    location                        TEXT,
    -- ingestion metadata (added by the pipeline, not part of the source)
    _source_file                    TEXT,
    _loaded_at                      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE staging.crashes_raw IS
    'Raw copy of the Chicago "Traffic Crashes - Crashes" dataset. No constraints on purpose: bad rows are found by quality_checks.sql, not rejected at load time.';

-- -----------------------------------------------------------------------------
-- 2. CORE LOOKUP TABLES (normalized categorical attributes)
--    Only attributes used by the analytical questions/dashboard are normalized.
--    Each lookup stores the exact label used in the source data.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.weather_condition (
    weather_condition_id    SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    weather_condition_name  VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS core.lighting_condition (
    lighting_condition_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lighting_condition_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS core.roadway_surface_condition (
    roadway_surface_condition_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    roadway_surface_condition_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS core.first_crash_type (
    first_crash_type_id     SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_crash_type_name   VARCHAR(100) NOT NULL UNIQUE
);

-- Shared by both the primary and the secondary contributory cause.
CREATE TABLE IF NOT EXISTS core.contributory_cause (
    contributory_cause_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contributory_cause_name VARCHAR(150) NOT NULL UNIQUE,
    -- TRUE for labels that carry no real cause (e.g. UNABLE TO DETERMINE, NOT APPLICABLE).
    -- Set during Phase 2 transformation; used to exclude them from cause analysis.
    is_undetermined         BOOLEAN NOT NULL DEFAULT FALSE
);

-- The source has exactly three damage labels (verified via the Socrata API).
CREATE TABLE IF NOT EXISTS core.damage_category (
    damage_category_id      SMALLINT PRIMARY KEY,
    damage_category_name    VARCHAR(50)   NOT NULL UNIQUE,
    min_usd                 NUMERIC(10,2) NOT NULL,
    max_usd                 NUMERIC(10,2),          -- NULL = no upper bound
    sort_order              SMALLINT      NOT NULL UNIQUE,
    CONSTRAINT chk_damage_range CHECK (max_usd IS NULL OR max_usd >= min_usd)
);

INSERT INTO core.damage_category (damage_category_id, damage_category_name, min_usd, max_usd, sort_order)
VALUES
    (1, '$500 OR LESS',   0.00,  500.00, 1),
    (2, '$501 - $1,500', 501.00, 1500.00, 2),
    (3, 'OVER $1,500',  1500.01,   NULL, 3)
ON CONFLICT (damage_category_id) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. CORE FACT TABLE: one row per crash
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS core.crashes (
    crash_record_id                 VARCHAR(128) PRIMARY KEY,

    -- when
    crash_date                      TIMESTAMP    NOT NULL,
    crash_date_est_i                BOOLEAN,
    date_police_notified            TIMESTAMP,
    crash_hour                      SMALLINT,
    crash_day_of_week               SMALLINT,    -- 1 = Sunday ... 7 = Saturday (source coding)
    crash_month                     SMALLINT,
    crash_year                      SMALLINT GENERATED ALWAYS AS (EXTRACT(YEAR FROM crash_date)::SMALLINT) STORED,

    -- normalized categories (foreign keys)
    weather_condition_id            SMALLINT REFERENCES core.weather_condition (weather_condition_id),
    lighting_condition_id           SMALLINT REFERENCES core.lighting_condition (lighting_condition_id),
    roadway_surface_condition_id    SMALLINT REFERENCES core.roadway_surface_condition (roadway_surface_condition_id),
    first_crash_type_id             SMALLINT REFERENCES core.first_crash_type (first_crash_type_id),
    prim_contributory_cause_id      SMALLINT REFERENCES core.contributory_cause (contributory_cause_id),
    sec_contributory_cause_id       SMALLINT REFERENCES core.contributory_cause (contributory_cause_id),
    damage_category_id              SMALLINT REFERENCES core.damage_category (damage_category_id),

    -- other descriptive attributes (kept as text: low analytical value for Phase 1)
    crash_type                      VARCHAR(50),
    report_type                     VARCHAR(50),
    traffic_control_device          VARCHAR(100),
    device_condition                VARCHAR(100),
    trafficway_type                 VARCHAR(100),
    alignment                       VARCHAR(100),
    road_defect                     VARCHAR(100),
    most_severe_injury              VARCHAR(50),
    work_zone_type                  VARCHAR(50),

    -- road and vehicles
    posted_speed_limit              SMALLINT,
    lane_cnt                        INTEGER,
    num_units                       SMALLINT,

    -- Y/N indicator flags converted to BOOLEAN (NULL = not recorded)
    intersection_related_i          BOOLEAN,
    not_right_of_way_i              BOOLEAN,
    hit_and_run_i                   BOOLEAN,
    photos_taken_i                  BOOLEAN,
    statements_taken_i              BOOLEAN,
    dooring_i                       BOOLEAN,
    work_zone_i                     BOOLEAN,
    workers_present_i               BOOLEAN,

    -- injuries (counts of people)
    injuries_total                  SMALLINT,
    injuries_fatal                  SMALLINT,
    injuries_incapacitating         SMALLINT,
    injuries_non_incapacitating     SMALLINT,
    injuries_reported_not_evident   SMALLINT,
    injuries_no_indication          SMALLINT,
    injuries_unknown                SMALLINT,

    -- where
    street_no                       INTEGER,
    street_direction                VARCHAR(2),
    street_name                     VARCHAR(100),
    beat_of_occurrence              SMALLINT,
    latitude                        NUMERIC(9,6),
    longitude                       NUMERIC(9,6),
    idot_control_no                 VARCHAR(50),

    -- lineage
    _loaded_at                      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- domain rules that must always hold (softer rules live in quality_checks.sql)
    CONSTRAINT chk_crash_hour        CHECK (crash_hour BETWEEN 0 AND 23),
    CONSTRAINT chk_crash_day_of_week CHECK (crash_day_of_week BETWEEN 1 AND 7),
    CONSTRAINT chk_crash_month       CHECK (crash_month BETWEEN 1 AND 12),
    CONSTRAINT chk_speed_limit       CHECK (posted_speed_limit >= 0),
    CONSTRAINT chk_num_units         CHECK (num_units >= 0),
    CONSTRAINT chk_injuries_non_negative CHECK (
        COALESCE(injuries_total, 0) >= 0 AND COALESCE(injuries_fatal, 0) >= 0
        AND COALESCE(injuries_incapacitating, 0) >= 0
        AND COALESCE(injuries_non_incapacitating, 0) >= 0
        AND COALESCE(injuries_reported_not_evident, 0) >= 0
        AND COALESCE(injuries_no_indication, 0) >= 0
        AND COALESCE(injuries_unknown, 0) >= 0
    ),
    CONSTRAINT chk_latitude          CHECK (latitude  BETWEEN -90  AND 90),
    CONSTRAINT chk_longitude         CHECK (longitude BETWEEN -180 AND 180)
);

COMMENT ON TABLE  core.crashes IS 'One row per traffic crash reported by the Chicago Police Department (cleaned from staging.crashes_raw).';
COMMENT ON COLUMN core.crashes.crash_record_id   IS 'Unique crash identifier from the source; joins to the People and Vehicles datasets.';
COMMENT ON COLUMN core.crashes.crash_day_of_week IS 'Source coding: 1 = Sunday, 2 = Monday, ... 7 = Saturday.';
COMMENT ON COLUMN core.crashes.not_right_of_way_i IS 'Source column NOT_RIGHT_OF_WAY_I (API field name private_property_i).';

-- -----------------------------------------------------------------------------
-- 4. INDEXES for the analytical queries
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_crashes_crash_date      ON core.crashes (crash_date);
CREATE INDEX IF NOT EXISTS idx_crashes_year            ON core.crashes (crash_year);
CREATE INDEX IF NOT EXISTS idx_crashes_dow_hour        ON core.crashes (crash_day_of_week, crash_hour);
CREATE INDEX IF NOT EXISTS idx_crashes_prim_cause      ON core.crashes (prim_contributory_cause_id);
CREATE INDEX IF NOT EXISTS idx_crashes_weather         ON core.crashes (weather_condition_id);
CREATE INDEX IF NOT EXISTS idx_crashes_lighting        ON core.crashes (lighting_condition_id);
CREATE INDEX IF NOT EXISTS idx_crashes_surface         ON core.crashes (roadway_surface_condition_id);
CREATE INDEX IF NOT EXISTS idx_crashes_damage          ON core.crashes (damage_category_id);
