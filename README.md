# SmallProject — User Registration

React (frontend) → FastAPI (backend) → PostgreSQL (database)

| Step | What happens |
|------|--------------|
| 1. Register | User fills in the form at `http://localhost:5173/register` → `POST /api/v1/auth/register` |
| 2. Create database | On startup the backend creates the `smallproject` database and `users` table; the new user is saved |
| 3. Success | User is redirected to `/success`, which shows **"Registered successfully!"** |

## Project structure
```
SmallProject/
├── docker-compose.yml          # PostgreSQL container (host port 5433)
├── backend/
│   ├── requirements.txt, requirements-dev.txt
│   ├── pyproject.toml          # ruff + pytest settings
│   ├── .env.example
│   ├── alembic.ini, migrations/  # database migrations (Alembic), see migrations/README.md
│   ├── tests/
│   └── app/
│       ├── main.py             # FastAPI app, CORS, health checks
│       ├── core/               # config.py (settings), security.py (password hashing)
│       ├── db/                 # base.py, session.py, migrate.py (creates DB, runs migrations)
│       ├── models/             # SQLAlchemy ORM models (user.py)
│       ├── schemas/            # Pydantic request/response schemas
│       ├── services/           # business logic (user_service.py)
│       └── api/v1/
│           ├── router.py
│           └── endpoints/      # auth.py -> POST /auth/register
├── scraper/, ai/                # placeholders: Dockerfile + main.py, image build only
├── infra/backend/              # Terraform for the backend (network, ECS, DB, jobs); envs/alpha, envs/beta
├── infra/frontend/             # Terraform for the website (S3 + CloudFront); envs/alpha, envs/beta
├── .github/workflows/          # CI, deploy-backend/-frontend (each runs its own terraform), build-*, release
└── frontend/
    ├── package.json, vite.config.js (+ Vitest settings), eslint.config.js, index.html, .env.example
    └── src/
        ├── main.jsx, App.jsx
        ├── config/             # env.js (API base URL)
        ├── routes/             # AppRoutes.jsx, paths.js
        ├── services/           # apiClient.js, authService.js
        ├── components/         # reusable UI (FormInput)
        ├── pages/              # Register/, Success/
        └── styles/             # global.css
```

## Run it

**1. Database** (Docker, or a local `brew install postgresql@16`)
```bash
docker compose up -d
```

**2. Backend**
```bash
cd backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python -m app.db.migrate      # create the database and tables (re-run after pulling)
uvicorn app.main:app --reload
```
API: http://localhost:8000 · Docs: http://localhost:8000/docs

**3. Frontend**
```bash
cd frontend
npm install
cp .env.example .env
npm run dev
```
Open http://localhost:5173

**4. Backend lint and tests** (needs the database from step 1; tests use their own `smallproject_test` database)
```bash
cd backend
pip install -r requirements-dev.txt
ruff check . && ruff format --check . && pytest
```

**5. Frontend lint and tests** (no backend needed)
```bash
cd frontend
npm run lint && npm test
```

## Environments, releases and undo
Two copies of the stack run in one AWS account: **alpha** (`smallproject-*`,
where selected changes are tested) and **beta** (`smallproject-beta-*`, shown
to the client), each with its own deploy role that can only touch its own
resources. Branches: `code` (the default) is integration and deploys nowhere;
`alpha` gets selected tickets one PR at a time and deploys to alpha;
`release/*` copies alpha to beta; `main` is locked, kept for production later. Everything runs from GitHub Actions; nothing is run
from a laptop.

| What | How |
|---|---|
| Change AWS (Terraform) | Two stacks, `infra/backend/` and `infra/frontend/`, each with its own state. A PR touching one shows its plan; merging into `alpha` applies it to alpha, then deploys that part (`deploy-backend.yml` / `deploy-frontend.yml` call `terraform.yml`) |
| Integrate | Merge feature PRs into `code`: checks only, no deploy |
| Ship to alpha | Actions → **promote** → Run workflow: tickets `SP-1,SP-3,SP-5`. It opens one PR copying those tickets' commits from `code` into `alpha` (on a conflict it prints the commands to fix it by hand); let CI pass, then **Rebase and merge**: alpha deploys the part that changed |
| Ship to beta | Actions → **release** → Run workflow: version `1.3`. It cuts `release/1.3` from `alpha` as tested and deploys it to beta after your approval |
| Mark a release | When beta looks good, publish tag `v1.3` on `release/1.3` from the Releases page |
| Turn an environment off | Actions → **terraform** → stack `frontend`, then stack `backend`; env, `destroy`, type the env name. A database snapshot is kept |
| API keys | Secrets Manager console → `<env prefix>/app` (JSON), then add the key to `secrets` in `infra/backend/app.tf` |

Every PR title starts with its Jira ticket number, e.g. `SI-12 Supplier sync`
(`pr-title.yml`); that is how the promote button finds a feature. A feature's
backend and frontend PRs use the same ticket, so promote takes both halves.

**Undo, from smallest to biggest**
1. Automatic: if new backend tasks fail their health checks, ECS rolls back.
2. Revert the PR and merge: the pipeline redeploys the old code.
3. Fast backend undo: Actions → **deploy-backend** → Run workflow with the env
   and the full commit SHA of a version that worked.
4. Database: restore the `<db>-predeploy-<sha>` snapshot taken before migrations.
5. Infrastructure: revert the `infra/backend/` or `infra/frontend/` PR; merging applies the old setup.

## Repo settings
The GitHub settings (squash merge only, the default branch `code`, the rules protecting `code` and `main`, and
the `v*` release tags) are kept as code in
[`.github/settings/apply-settings.sh`](.github/settings/apply-settings.sh).
Change them there in a PR, then apply them with Actions → **repo-settings**
→ Run workflow (tick *dry run* to preview first).
