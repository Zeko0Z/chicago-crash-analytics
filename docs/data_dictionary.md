# Data Dictionary – Chicago Traffic Crash Analytics

**Database:** `chicago_crashes` (PostgreSQL 16)  **Source:** City of Chicago Data Portal – *Traffic Crashes – Crashes* (`85ca-t3if`)  **DDL:** [`sql/schema.sql`](../sql/schema.sql)  **Views:** [`sql/views.sql`](../sql/views.sql)

## 1. Overview

| Schema | Object | Type | Rows (target) | Purpose |
|---|---|---|---|---|
| `staging` | `crashes_raw` | table | ~1.1 M | Raw landing copy of the source. All columns `TEXT`, no constraints. |
| `core` | `crashes` | table | ~1.1 M | One cleaned, typed row per crash. Main fact table. |
| `core` | `weather_condition` | lookup | 12 | Weather labels |
| `core` | `lighting_condition` | lookup | small | Lighting labels |
| `core` | `roadway_surface_condition` | lookup | small | Road-surface labels |
| `core` | `first_crash_type` | lookup | small | Type of first collision |
| `core` | `contributory_cause` | lookup | 40 | Cause labels (used for primary **and** secondary cause) |
| `core` | `damage_category` | lookup | 3 | Damage bands with numeric ranges (seeded in `schema.sql`) |
| `analytics` | `v_crashes_enriched` | view | – | Crashes joined to all lookups + helper flags |
| `analytics` | `v_q1_injury_rate_by_day_hour` | view | 168 | Answers Question 1 |
| `analytics` | `v_q2_cause_severity` | view | – | Answers Question 2 |
| `analytics` | `v_q3_weather_lighting_risk` | view | – | Answers Question 3 |
| `analytics` | `v_monthly_trend` | view | – | Monthly totals for dashboard trend charts |

Row counts for `staging`/`core` are targets based on the source (1,112,485 crashes on 12 Nov 2026). The tables are empty in Phase 1 – loading starts in Phase 2. The 12 weather labels, 40 primary-cause labels and 3 damage labels were verified with grouped API queries; the other lookup sizes will be confirmed after the first load.

### Relationships (entity–relationship summary)

```
core.weather_condition          1 ──< core.crashes.weather_condition_id
core.lighting_condition         1 ──< core.crashes.lighting_condition_id
core.roadway_surface_condition  1 ──< core.crashes.roadway_surface_condition_id
core.first_crash_type           1 ──< core.crashes.first_crash_type_id
core.contributory_cause         1 ──< core.crashes.prim_contributory_cause_id
core.contributory_cause         1 ──< core.crashes.sec_contributory_cause_id
core.damage_category            1 ──< core.crashes.damage_category_id
staging.crashes_raw.crash_record_id ·····> core.crashes.crash_record_id   (logical, via the ETL; no FK)
```

All relationships are **one-to-many**: one lookup row describes many crashes. Foreign keys are nullable because the source sometimes leaves a category empty.

### Normalization notes

- **1NF:** every column holds one atomic value. The source `LOCATION` column (a `POINT` that repeats latitude and longitude) is not stored in `core`; it can be rebuilt from `latitude` and `longitude`.
- **2NF:** `core.crashes` has a single-column primary key (`crash_record_id`), so there are no partial dependencies.
- **3NF:** repeated text labels used in analysis (weather, lighting, road surface, first crash type, causes, damage) are moved to lookup tables. This removes update anomalies (a label is fixed in one place) and saves space on ~1.1 M rows.
- **Deliberate denormalization:** `crash_hour`, `crash_day_of_week` and `crash_month` can be computed from `crash_date`, but they are kept because the source publishes them and dashboards group by them often. Check `B05` in `quality_checks.sql` confirms they agree with `crash_date`. Low-value descriptive labels (e.g. `alignment`, `road_defect`) stay as `VARCHAR` columns for Phase 1 to avoid unnecessary complexity.
- **Future extension:** the related portal datasets *Traffic Crashes – People* (`u6pd-qa9d`) and *Traffic Crashes – Vehicles* (`68nd-jvt3`) share `crash_record_id` and can be added later as child tables with a foreign key to `core.crashes`.

---

## 2. `staging.crashes_raw`

Raw copy of the source. Each of the 49 published source columns has a `TEXT` column with the same name in lowercase (the CSV export uses UPPERCASE headers). Two metadata columns are added:

| Column | Type | Description |
|---|---|---|
| *49 source columns* | `TEXT` | Exact source values, not cleaned. One exception: the CSV header `NOT_RIGHT_OF_WAY_I` is called `private_property_i` in the API; we store it as `not_right_of_way_i`. |
| `_source_file` | `TEXT` | File name or API URL the row came from (lineage). |
| `_loaded_at` | `TIMESTAMPTZ` | Load time, default `now()`. |

---

## 3. `core.crashes`

**Primary key:** `crash_record_id`  **Grain:** one row per crash report.

| # | Column | PostgreSQL type | Null? | Key / rule | Source column | Description |
|---|---|---|---|---|---|---|
| 1 | `crash_record_id` | `VARCHAR(128)` | NO | **PK** | CRASH_RECORD_ID | Unique crash ID. Also links to the People and Vehicles datasets. |
| 2 | `crash_date` | `TIMESTAMP` | NO | indexed | CRASH_DATE | Date and time of the crash (local Chicago time, no time zone in source). |
| 3 | `crash_date_est_i` | `BOOLEAN` | yes | | CRASH_DATE_EST_I | TRUE if the crash date was estimated (crash reported at a police station days later). |
| 4 | `date_police_notified` | `TIMESTAMP` | yes | | DATE_POLICE_NOTIFIED | When police were notified. |
| 5 | `crash_hour` | `SMALLINT` | yes | CHECK 0–23 | CRASH_HOUR | Hour part of `crash_date`. |
| 6 | `crash_day_of_week` | `SMALLINT` | yes | CHECK 1–7 | CRASH_DAY_OF_WEEK | Day of week, **1 = Sunday** … 7 = Saturday (source coding). |
| 7 | `crash_month` | `SMALLINT` | yes | CHECK 1–12 | CRASH_MONTH | Month part of `crash_date`. |
| 8 | `crash_year` | `SMALLINT` | – | generated | (derived) | `EXTRACT(YEAR FROM crash_date)`, stored generated column. |
| 9 | `weather_condition_id` | `SMALLINT` | yes | **FK** → `weather_condition` | WEATHER_CONDITION | Weather at the time of crash. |
| 10 | `lighting_condition_id` | `SMALLINT` | yes | **FK** → `lighting_condition` | LIGHTING_CONDITION | Light condition (daylight, darkness, dusk…). |
| 11 | `roadway_surface_condition_id` | `SMALLINT` | yes | **FK** → `roadway_surface_condition` | ROADWAY_SURFACE_COND | Road surface (dry, wet, snow…). |
| 12 | `first_crash_type_id` | `SMALLINT` | yes | **FK** → `first_crash_type` | FIRST_CRASH_TYPE | Type of first collision (rear end, angle, pedestrian…). |
| 13 | `prim_contributory_cause_id` | `SMALLINT` | yes | **FK** → `contributory_cause` | PRIM_CONTRIBUTORY_CAUSE | Main cause, as judged by the reporting officer. |
| 14 | `sec_contributory_cause_id` | `SMALLINT` | yes | **FK** → `contributory_cause` | SEC_CONTRIBUTORY_CAUSE | Secondary cause. |
| 15 | `damage_category_id` | `SMALLINT` | yes | **FK** → `damage_category` | DAMAGE | Estimated damage band (field observation). |
| 16 | `crash_type` | `VARCHAR(50)` | yes | | CRASH_TYPE | Overall category: injury and/or tow vs. no injury / drive away. |
| 17 | `report_type` | `VARCHAR(50)` | yes | | REPORT_TYPE | Administrative report type (on scene, desk report…). |
| 18 | `traffic_control_device` | `VARCHAR(100)` | yes | | TRAFFIC_CONTROL_DEVICE | Traffic control at the location (signal, stop sign…). |
| 19 | `device_condition` | `VARCHAR(100)` | yes | | DEVICE_CONDITION | Whether the control device was working. |
| 20 | `trafficway_type` | `VARCHAR(100)` | yes | | TRAFFICWAY_TYPE | Road layout (divided, one-way, intersection type…). |
| 21 | `alignment` | `VARCHAR(100)` | yes | | ALIGNMENT | Road alignment (straight and level, curve…). |
| 22 | `road_defect` | `VARCHAR(100)` | yes | | ROAD_DEFECT | Road defects (none, ruts, debris…). |
| 23 | `most_severe_injury` | `VARCHAR(50)` | yes | | MOST_SEVERE_INJURY | Worst injury in the crash. |
| 24 | `work_zone_type` | `VARCHAR(50)` | yes | | WORK_ZONE_TYPE | Type of work zone, if any. |
| 25 | `posted_speed_limit` | `SMALLINT` | yes | CHECK ≥ 0 | POSTED_SPEED_LIMIT | Posted speed limit (mph). |
| 26 | `lane_cnt` | `INTEGER` | yes | | LANE_CNT | Number of through lanes (often missing; outliers checked in B11). |
| 27 | `num_units` | `SMALLINT` | yes | CHECK ≥ 0 | NUM_UNITS | Number of units (vehicles, pedestrians, cyclists) involved. |
| 28 | `intersection_related_i` | `BOOLEAN` | yes | | INTERSECTION_RELATED_I | Crash related to an intersection. |
| 29 | `not_right_of_way_i` | `BOOLEAN` | yes | | NOT_RIGHT_OF_WAY_I (API: `private_property_i`) | Crash began outside the public right-of-way. |
| 30 | `hit_and_run_i` | `BOOLEAN` | yes | | HIT_AND_RUN_I | A driver left the scene. |
| 31 | `photos_taken_i` | `BOOLEAN` | yes | | PHOTOS_TAKEN_I | Police took photos. |
| 32 | `statements_taken_i` | `BOOLEAN` | yes | | STATEMENTS_TAKEN_I | Statements were taken. |
| 33 | `dooring_i` | `BOOLEAN` | yes | | DOORING_I | Cyclist hit by an opening car door. |
| 34 | `work_zone_i` | `BOOLEAN` | yes | | WORK_ZONE_I | Crash in a work zone. |
| 35 | `workers_present_i` | `BOOLEAN` | yes | | WORKERS_PRESENT_I | Workers present in the work zone. |
| 36 | `injuries_total` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_TOTAL | People injured (fatal + incapacitating + non-incapacitating + reported-not-evident). |
| 37 | `injuries_fatal` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_FATAL | Fatal injuries. |
| 38 | `injuries_incapacitating` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_INCAPACITATING | Incapacitating (serious) injuries. |
| 39 | `injuries_non_incapacitating` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_NON_INCAPACITATING | Non-incapacitating injuries. |
| 40 | `injuries_reported_not_evident` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_REPORTED_NOT_EVIDENT | Injuries reported but not visible. |
| 41 | `injuries_no_indication` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_NO_INDICATION | People with no sign of injury. |
| 42 | `injuries_unknown` | `SMALLINT` | yes | CHECK ≥ 0 | INJURIES_UNKNOWN | People with unknown injury status. |
| 43 | `street_no` | `INTEGER` | yes | | STREET_NO | Street address number. |
| 44 | `street_direction` | `VARCHAR(2)` | yes | | STREET_DIRECTION | Street direction (N, S, E, W). |
| 45 | `street_name` | `VARCHAR(100)` | yes | | STREET_NAME | Street name. |
| 46 | `beat_of_occurrence` | `SMALLINT` | yes | | BEAT_OF_OCCURRENCE | Chicago Police beat. |
| 47 | `latitude` | `NUMERIC(9,6)` | yes | CHECK −90…90 | LATITUDE | Latitude derived from the reported address. |
| 48 | `longitude` | `NUMERIC(9,6)` | yes | CHECK −180…180 | LONGITUDE | Longitude derived from the reported address. |
| 49 | `idot_control_no` | `VARCHAR(50)` | yes | | IDOT_CONTROL_NO | Illinois DOT control number (added to the source in May 2026). |
| 50 | `_loaded_at` | `TIMESTAMPTZ` | NO | default `now()` | (pipeline) | When the row was written to `core`. |

Source column `LOCATION` (point) is intentionally not stored in `core` (see normalization notes).

**Indexes:** `crash_date`, `crash_year`, (`crash_day_of_week`, `crash_hour`), and every lookup foreign key.

---

## 4. Lookup tables

### `core.weather_condition`, `core.lighting_condition`, `core.roadway_surface_condition`, `core.first_crash_type`

All four have the same structure:

| Column | Type | Key | Description |
|---|---|---|---|
| `<name>_id` | `SMALLINT GENERATED ALWAYS AS IDENTITY` | **PK** | Surrogate key |
| `<name>_name` | `VARCHAR(100)` | UNIQUE, NOT NULL | Exact label from the source, e.g. `CLEAR`, `RAIN`, `UNKNOWN` |

Verified weather labels (12): CLEAR, RAIN, UNKNOWN, SNOW, CLOUDY/OVERCAST, OTHER, FREEZING RAIN/DRIZZLE, FOG/SMOKE/HAZE, SLEET/HAIL, BLOWING SNOW, SEVERE CROSS WIND GATE, BLOWING SAND, SOIL, DIRT.

### `core.contributory_cause`

| Column | Type | Key | Description |
|---|---|---|---|
| `contributory_cause_id` | `SMALLINT IDENTITY` | **PK** | Surrogate key |
| `contributory_cause_name` | `VARCHAR(150)` | UNIQUE, NOT NULL | Cause label, e.g. `FAILING TO YIELD RIGHT-OF-WAY` |
| `is_undetermined` | `BOOLEAN` | NOT NULL, default FALSE | TRUE for labels with no real cause (`UNABLE TO DETERMINE`, `NOT APPLICABLE`). Used to exclude them in Question 2. |

### `core.damage_category` (seeded)

| Column | Type | Key | Description |
|---|---|---|---|
| `damage_category_id` | `SMALLINT` | **PK** | 1, 2, 3 |
| `damage_category_name` | `VARCHAR(50)` | UNIQUE | Exact source label |
| `min_usd` | `NUMERIC(10,2)` | | Lower bound of the band |
| `max_usd` | `NUMERIC(10,2)` | | Upper bound (NULL = no limit) |
| `sort_order` | `SMALLINT` | UNIQUE | Order for charts |

| id | name | min_usd | max_usd | Crashes in source (12 Nov 2026) |
|---|---|---|---|---|
| 1 | `$500 OR LESS` | 0.00 | 500.00 | 120,525 |
| 2 | `$501 - $1,500` | 501.00 | 1,500.00 | 270,172 |
| 3 | `OVER $1,500` | 1,500.01 | – | 721,788 |

---

## 5. Analytics views

| View | Grain | Main columns |
|---|---|---|
| `v_crashes_enriched` | 1 row per crash | lookup labels, `day_name`, `is_injury_crash` (injuries_total > 0), `is_severe_crash` (fatal + incapacitating > 0), `in_analysis_window` (2018-01-01 ≤ date < 2026-01-01) |
| `v_q1_injury_rate_by_day_hour` | day × hour (168) | `crash_count`, `injury_crash_count`, `injury_crash_pct`, `severe_crashes_per_1000`, `injury_rate_rank` |
| `v_q2_cause_severity` | 1 row per primary cause (≥ 1,000 crashes) | `crash_count`, `fatalities`, `incapacitating_injuries`, `injury_crash_pct`, `severe_crashes_per_1000`, `severity_rank` |
| `v_q3_weather_lighting_risk` | weather × lighting (≥ 500 crashes) | `crash_count`, `injury_crash_pct`, `over_1500_damage_pct`, `relative_injury_risk` (1.00 = average) |
| `v_monthly_trend` | 1 row per month (from Sept 2017) | `crash_count`, `injury_crash_count`, `people_injured`, `fatalities` |
