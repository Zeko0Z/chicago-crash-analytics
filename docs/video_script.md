# Video Walkthrough Script – Phase 1 (3–5 minutes)

**Target length:** about 4 minutes. **Speakers:** one person can present everything, or split the sections between team members (suggested split in brackets).

## Before you record (checklist)

- [ ] Docker Desktop is running.
- [ ] Your `.env` file exists and has real passwords.
- [ ] To show a clean first start, run `docker compose down -v` before recording. **This deletes the database data** – fine in Phase 1, because the tables are still empty.
- [ ] Open: this script, the terminal in the project folder, `docs/architecture.png`, and a browser tab.
- [ ] Increase the terminal font size so commands are readable on video.
- [ ] Hide your `.env` file – **never show your real passwords on screen.**
- [ ] Optional: run `docker compose pull` before recording, so the image download does not slow the video.

---

## 0:00 – 0:30 · Project introduction [Member 1]

*(Screen: README.md on GitHub, or the proposal PDF title page)*

> "Hello, we are team [team name]. Our Data Engineering project is called **Chicago Traffic Crash Analytics**.
> The goal is to build an end-to-end data pipeline. It takes public crash data from the City of Chicago, stores it in a PostgreSQL database, and answers three questions about when, why and in which conditions crashes cause injuries.
> This video shows Phase 1: our dataset, our questions, our architecture, and our working Docker environment."

## 0:30 – 1:10 · Dataset explanation [Member 2]

*(Screen: the dataset page https://data.cityofchicago.org/d/85ca-t3if)*

> "Our dataset is **Traffic Crashes – Crashes** from the Chicago Data Portal. The Chicago Police Department collects it from crash reports.
> It has about **1.1 million rows** and **49 columns**. When we checked it on the 12th of November 2026, it had 1,112,485 crashes, and it grows every day.
> Every row is one crash. The primary key is **CRASH_RECORD_ID**.
> We have dates, like the crash date. We have numbers, like the injury counts and the speed limit. And we have categories, like weather, lighting and the main cause.
> We can download it as CSV or read it through a JSON API.
> We also found some data quality issues. For example, data before September 2017 does not cover the whole city, and about 40% of crashes have the cause 'Unable to determine'. We handle these in our design."

## 1:10 – 1:50 · Three analytical questions [Member 3]

*(Screen: the questions section of the proposal or README)*

> "We will answer three questions, using the years 2018 to 2025.
> **Question 1:** At which hours and on which days of the week do crashes most often cause injuries? The result will be a heatmap of 7 days by 24 hours.
> **Question 2:** Which main causes lead to the most severe crashes? We measure severe crashes – fatal or incapacitating injuries – per 1,000 crashes, for each cause.
> **Question 3:** How do weather and lighting change the risk of an injury? We compare each condition with the average.
> We already wrote a SQL view for each question in the file views.sql."

## 1:50 – 2:40 · Architecture diagram [Member 4]

*(Screen: docs/architecture.png – point at each box)*

> "This is our architecture. Data flows from top to bottom.
> **One:** the public dataset and API from the Chicago Data Portal.
> **Two:** Python ingestion. It will download the data and load it into the database.
> **Three:** PostgreSQL. We use three schemas: *staging* for raw data, *core* for clean data – one crashes table and six lookup tables with foreign keys – and *analytics* for the views.
> **Four:** Kestra, our orchestrator. It will run the pipeline every day, run our quality checks, and retry if something fails. The dashed arrow shows that Kestra starts the Python job.
> **Five:** the dashboard, which reads the analytics views.
> In Phase 1 we built the PostgreSQL part with Docker. Python, Kestra and the dashboard come in the next phases."

## 2:40 – 3:20 · Terminal and `docker compose up -d` [Member 5]

*(Screen: terminal in the project folder)*

> "Now I will start our environment. Our docker-compose file has two services: PostgreSQL and pgAdmin. The passwords come from a .env file, which is not uploaded to GitHub."

Type and run:

```bash
docker compose up -d
```

> "Docker creates the network, the volumes and the two containers. Now I check the status."

```bash
docker compose ps
```

> "PostgreSQL shows **healthy**. This comes from our health check, which runs pg_isready every 10 seconds. pgAdmin starts only after the database is healthy."

Optional extra proof:

```bash
docker compose exec postgres sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"'
```

> "It says: accepting connections."

## 3:20 – 4:20 · pgAdmin and PostgreSQL connectivity [Member 5 or Member 1]

*(Screen: browser → http://localhost:5050)*

> "Now I open pgAdmin in the browser at localhost port 5050 and log in."

*(Log in. Do not show the password.)*

> "Our server, **Chicago Crashes (Docker)**, is already registered by our docker-compose file. I click it and enter the database password."

*(Expand Servers → Chicago Crashes (Docker) → Databases → chicago_crashes → Schemas)*

> "We are connected. Here are our three schemas: analytics, core and staging. Our schema.sql file created them automatically on the first start."

*(Expand core → Tables. Then open Tools → Query Tool and run:)*

```sql
SELECT version();
SELECT * FROM core.damage_category;
```

> "The first query shows PostgreSQL version 16. The second query returns the three damage categories that our schema adds. This proves pgAdmin is connected to PostgreSQL.
> The tables are still empty. Loading the crash data is the job of Phase 2."

## 4:20 – 4:40 · Closing [Member 1]

> "To sum up: we chose a large, real dataset with 1.1 million rows, defined three clear questions, designed a normalized PostgreSQL database, and set up a working Docker environment with persistent volumes.
> Next, we will build the Python ingestion and the Kestra flows. Thank you for watching."

---

### Speaking tips

- Speak slowly. Pause for one second after each command.
- If a command takes time, say what is happening ("Docker is downloading the images…").
- If something fails, stop the recording, fix it, and record that part again. Do not edit the output.
