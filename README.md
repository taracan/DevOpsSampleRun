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
│   ├── requirements.txt
│   ├── .env.example
│   ├── tests/
│   └── app/
│       ├── main.py             # FastAPI app, CORS, startup
│       ├── core/               # config.py (settings), security.py (password hashing)
│       ├── db/                 # base.py, session.py, init_db.py (creates DB + tables)
│       ├── models/             # SQLAlchemy ORM models (user.py)
│       ├── schemas/            # Pydantic request/response schemas
│       ├── services/           # business logic (user_service.py)
│       └── api/v1/
│           ├── router.py
│           └── endpoints/      # auth.py -> POST /auth/register
└── frontend/
    ├── package.json, vite.config.js, index.html, .env.example
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
