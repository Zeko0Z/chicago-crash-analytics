# Chicago Traffic Crash Analytics – Data Engineering Project

> \*\*Status: Phase 1 (proposal + environment).\*\* This repository contains the project design, the PostgreSQL schema, data quality checks and a Docker environment with PostgreSQL and pgAdmin. Data ingestion (Phase 2), Kestra orchestration (Phase 3) and the dashboard (Phase 4) are \*\*not built yet\*\*.

\---

## 1\. Project overview

Chicago records about one traffic crash every few minutes. This project builds an end-to-end data pipeline that collects the City of Chicago's public crash data, stores it in a well-designed PostgreSQL database, and answers three questions about **when**, **why** and **in which conditions** crashes cause injuries.

The full proposal is in [`docs/proposal.pdf`](docs/proposal.pdf) (source text: [`docs/proposal.md`](docs/proposal.md)).

## 2\. Dataset

|Item|Value|
|-|-|
|Name|**Traffic Crashes – Crashes**|
|Publisher|City of Chicago Data Portal (data from Chicago Police Department E-Crash reports)|
|Landing page|https://data.cityofchicago.org/d/85ca-t3if|
|CSV download|https://data.cityofchicago.org/api/views/85ca-t3if/rows.csv?accessType=DOWNLOAD|
|JSON API (SODA)|https://data.cityofchicago.org/resource/85ca-t3if.json|
|Rows|**1,112,485** (checked through the API on 12 Nov 2026; grows every day)|
|Columns|**49** published columns|
|Date range|2013-03-03 → 2026-11-10 (citywide coverage only from **September 2017**)|
|Primary key|`CRASH\_RECORD\_ID`|
|Update frequency|Daily|

Check the current row count yourself (open in a browser):
`https://data.cityofchicago.org/resource/85ca-t3if.json?$select=count(\*)`

Column-by-column details are in [`docs/data\_dictionary.md`](docs/data_dictionary.md).

## 3\. Analytical questions

1. **When are crashes most dangerous?** For 2018–2025, which day-of-week and hour-of-day combinations have the highest percentage of crashes with at least one injury?
2. **Which causes are the most dangerous?** Among primary contributory causes with at least 1,000 crashes (2018–2025, undetermined causes excluded), which have the most severe crashes (fatal or incapacitating injury) per 1,000 crashes?
3. **Do weather and light matter?** How much do weather and lighting conditions raise or lower the injury-crash rate compared with the average, and what share of those crashes cause more than $1,500 of damage?

Each question has a ready SQL view in [`sql/views.sql`](sql/views.sql).

## 4\. Architecture

!\[Architecture diagram](docs/architecture.png)

|#|Component|Responsibility|Phase|
|-|-|-|-|
|1|Public Dataset / API|Chicago Data Portal publishes crash data as CSV and JSON (Socrata API).|Source|
|2|Python Ingestion|Downloads the data, loads it into `staging`, cleans it into `core`.|2|
|3|PostgreSQL|Stores raw (`staging`), clean (`core`) and reporting (`analytics`) data.|**1 – built**|
|4|Kestra|Schedules ingestion daily, runs SQL transforms and quality checks, retries on failure.|3|
|5|Dashboard|Shows the three questions as charts using the `analytics` views.|4|

## 5\. Technologies

|Tool|Version|Used for|
|-|-|-|
|Docker + Docker Compose|Compose **v2.24 or newer**|Running PostgreSQL and pgAdmin|
|PostgreSQL|16 (`postgres:16-alpine`, official image)|Database|
|pgAdmin 4|9.x (`dpage/pgadmin4:9`, official pgAdmin image)|Web UI for the database|
|Python|3.11+ (Phase 2)|Ingestion scripts|
|Kestra|(Phase 3)|Orchestration|
|Dashboard tool|to be chosen in Phase 4 (e.g. Metabase or Apache Superset)|Visualization|
|Git + GitHub|–|Version control|

## 6\. Repository structure

```
data-engineering-project/
├── docs/
│   ├── proposal.md          # proposal text (source of the PDF)
│   ├── proposal.pdf         # submission-ready proposal
│   ├── architecture.png     # architecture diagram (also .svg)
│   ├── data\_dictionary.md   # every table, column, type and key
│   └── video\_script.md      # 3–5 minute walkthrough script
├── scripts/
│   └── README.md            # plan for the Phase 2 Python ingestion
├── sql/
│   ├── schema.sql           # schemas, tables, keys, indexes (runs automatically)
│   ├── quality\_checks.sql   # 20 data quality checks
│   └── views.sql            # analytics views for Q1–Q3 (runs automatically)
├── flows/
│   └── README.md            # plan for the Phase 3 Kestra flows
├── docker-compose.yml       # PostgreSQL + pgAdmin
├── .env.example             # template for your local .env (no real secrets)
├── .gitignore
└── README.md
```

## 7\. Prerequisites

* **Docker Desktop** (Windows / macOS) or **Docker Engine + Compose plugin** (Linux). Compose must be **v2.24 or newer** because `docker-compose.yml` uses an inline `configs.content` block. Check:

```bash
  docker --version
  docker compose version
  ```

* **Git**
* Free ports **5432** (PostgreSQL) and **5050** (pgAdmin). You can change them in `.env`.
* A web browser.

## 8\. Installation

```bash
git clone https://github.com/Zeko0Z/chicago-crash-analytics.git

cd chicago-crash-analytics
```

## 9\. Configure the `.env` file

The `.env` file holds your passwords. It stays on your computer and is **never committed** (it is in `.gitignore`).

1. Copy the template:

```bash
   cp .env.example .env          # macOS / Linux / Git Bash
   copy .env.example .env        # Windows Command Prompt
   ```

2. Open `.env` in a text editor and change at least:

   * `POSTGRES\_PASSWORD` – a strong password for the database
   * `PGADMIN\_DEFAULT\_EMAIL` – the e-mail you will use to log in to pgAdmin
   * `PGADMIN\_DEFAULT\_PASSWORD` – the pgAdmin login password
3. Optional: change `POSTGRES\_PORT` (e.g. to `5433`) if you already have PostgreSQL installed, or `PGADMIN\_PORT` if 5050 is busy.
4. Check that Git ignores it:

```bash
   git check-ignore -v .env      # should print: .gitignore:2:.env  .env
   ```

If a required value is missing, `docker compose` stops with a message such as `required variable POSTGRES\_PASSWORD is missing a value`.

## 10\. Start the containers

```bash
docker compose up -d
```

The first start downloads the images (a few hundred MB) and creates the database. On the **first start only**, PostgreSQL runs `sql/schema.sql` and `sql/views.sql` automatically.

Check the status (wait until `postgres` shows **healthy**):

```bash
docker compose ps
```

See the logs if something is wrong:

```bash
docker compose logs postgres
docker compose logs pgadmin
```

## 11\. Access pgAdmin

1. Open **http://localhost:5050** (or your `PGADMIN\_PORT`).
2. Log in with `PGADMIN\_DEFAULT\_EMAIL` and `PGADMIN\_DEFAULT\_PASSWORD` from your `.env`.

> pgAdmin can take 20–60 seconds to start the first time. Refresh the page if it does not load.

## 12\. Connect pgAdmin to PostgreSQL

The server is **already registered** for you (generated from `.env` by `docker-compose.yml`):

1. In the left panel, open **Servers → Chicago Crashes (Docker)**.
2. Enter the `POSTGRES\_PASSWORD` from your `.env` (tick *Save password* if you want).
3. Open **Databases → chicago\_crashes → Schemas** – you should see `analytics`, `core` and `staging`.

If you need to add the server manually (**Object → Register → Server**):

|Field|Value|
|-|-|
|Name|anything, e.g. `Chicago Crashes`|
|Host name/address|`postgres` ← the Docker service name, **not** `localhost`|
|Port|`5432` ← the port inside Docker, even if you changed `POSTGRES\_PORT`|
|Maintenance database|value of `POSTGRES\_DB`|
|Username|value of `POSTGRES\_USER`|
|Password|value of `POSTGRES\_PASSWORD`|

Why `postgres` and not `localhost`? pgAdmin runs in its own container. Inside that container, `localhost` means pgAdmin itself. Both containers share the `crashes\_net` network, where the database is reachable by its service name `postgres`.

## 13\. Verify that PostgreSQL is running

```bash
# 1. Container health (look for "healthy")
docker compose ps

# 2. Ask PostgreSQL if it accepts connections
docker compose exec postgres sh -c 'pg\_isready -U "$POSTGRES\_USER" -d "$POSTGRES\_DB"'

# 3. Run a query: version + the project schemas
docker compose exec postgres sh -c 'psql -U "$POSTGRES\_USER" -d "$POSTGRES\_DB" -c "SELECT version();" -c "\\dn"'

# 4. List the tables created by schema.sql (expect 8 tables)
docker compose exec postgres sh -c 'psql -U "$POSTGRES\_USER" -d "$POSTGRES\_DB" -c "\\dt staging.\*" -c "\\dt core.\*"'

# 5. Run the data quality checks (all 0 in Phase 1 - tables are still empty)
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES\_USER" -d "$POSTGRES\_DB"' < sql/quality\_checks.sql
```

In pgAdmin you can also open **Tools → Query Tool** and run:

```sql
SELECT \* FROM core.damage\_category;   -- returns 3 seeded rows
```

## 14\. Stop the containers

```bash
docker compose stop        # pause the containers, keep everything
docker compose start       # start them again

docker compose down        # remove containers and network, KEEP the data volumes
docker compose down -v     # ⚠ remove containers AND volumes = delete all database data
```

## 15\. How persistent volumes work

* PostgreSQL stores its files in the named volume **`crashes\_postgres\_data`**, mounted at `/var/lib/postgresql/data`.
* pgAdmin stores its settings in **`crashes\_pgadmin\_data`**, mounted at `/var/lib/pgadmin`.
* Volumes live outside the containers, so `docker compose down` and `docker compose up -d` keep your data. Only `docker compose down -v` deletes them.
* See them with:

```bash
  docker volume ls
  docker volume inspect crashes\_postgres\_data
  ```

* **Important:** `sql/schema.sql` and `sql/views.sql` run **only when the data volume is empty** (the first start). If you edit them later, either run them by hand:

```bash
  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES\_USER" -d "$POSTGRES\_DB"' < sql/schema.sql
  docker compose exec -T postgres sh -c 'psql -U "$POSTGRES\_USER" -d "$POSTGRES\_DB"' < sql/views.sql
  ```

  or reset everything with `docker compose down -v` and then `docker compose up -d`.

* The same rule applies to the password: PostgreSQL saves `POSTGRES\_PASSWORD` only on the first start. Changing `.env` later does not change the password of an existing volume.

## 16\. Security notes

* Credentials come only from `.env`; nothing secret is in Git.
* Both ports are bound to `127.0.0.1`, so other computers on your network cannot reach the database or pgAdmin.
* PostgreSQL uses `scram-sha-256` password authentication.
* pgAdmin does not store the database password in `servers.json`; you type it once in the UI.

## 17\. Troubleshooting

|Problem|Fix|
|-|-|
|`port is already allocated`|Change `POSTGRES\_PORT` or `PGADMIN\_PORT` in `.env`, then `docker compose up -d`.|
|`required variable ... is missing a value`|You have no `.env` or a value is empty. Repeat step 9.|
|`configs.pgadmin\_servers Additional property content is not allowed`|Your Docker Compose is too old. Update Docker Desktop (Compose v2.24+).|
|pgAdmin: `password authentication failed`|The volume was created with an older password. Use that one, or reset with `docker compose down -v`.|
|pgAdmin page does not load|Wait 30–60 s; check `docker compose logs pgadmin`.|

## 18\. Roadmap

|Phase|Deliverable|
|-|-|
|**1**|Proposal, architecture, schema, Docker environment ← *this submission*|
|2|Python ingestion into `staging` and `core` (see `scripts/README.md`)|
|3|Kestra flows for daily scheduling and quality checks (see `flows/README.md`)|
|4|Dashboard on top of the `analytics` views|

## 19\. Data licence and attribution

Data: City of Chicago, *Traffic Crashes – Crashes*, provided under the Terms of Use linked on the dataset page (https://data.cityofchicago.org/d/85ca-t3if). The data are provisional and may change as reports are amended.

