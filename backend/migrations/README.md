<!--
  migrations/README.md: how database changes work in this project, and the
  one rule that keeps rollbacks safe. Read this before writing a migration.
-->

# Database migrations (Alembic)

Every change to the database's shape (a new table, column or index) is a
small numbered script in `versions/`. The database remembers which scripts
it has run (table `alembic_version`), so each one runs exactly once.

## Running them
- **Laptop:** `python -m app.db.migrate` (after `docker compose up -d`).
- **Tests:** run automatically before the tests (`tests/conftest.py`).
- **Production:** every backend deploy runs `python -m app.db.migrate` as a
  one-off ECS task with the new image, **before** the new version goes live.
  If it fails, the deploy stops and the old version keeps running.

## Making a new one
1. Change the model in `app/models/`.
2. `alembic revision --autogenerate -m "short description"`.
3. **Read the generated script.** Autogenerate misses some things, such as
   renames, which it sees as "drop + add" and which would lose data.
4. `pytest`: `test_models_match_migrations` fails if a model and the
   migrations disagree.

## The rule: expand → migrate → contract
During a deploy, and after any rollback, **old code runs against the new
schema**. So every migration must keep the previous release working:

1. **Expand** (release 1): only *add* things, such as a new nullable column
   or a new table. Old code ignores them.
2. **Migrate** (release 2): switch the code to use the new thing, and fill in
   data if needed.
3. **Contract** (release 3, once nothing uses the old thing): drop the old
   column or table.

**Never** drop or rename a column in the same release as the code that stops
using it. A rename is "add new column → copy data → switch code → drop old
column", spread over releases.

Migrations are not rolled back automatically. The pre-migration database
snapshot (Phase B, step 9) is for disasters.
