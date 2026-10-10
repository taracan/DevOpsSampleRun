# Nightly report job. Build from the repo root so it can reuse the backend code:
#   docker build -f jobs/Dockerfile -t smallproject-jobs .
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install -r requirements.txt

COPY backend/app ./app
COPY jobs/nightly_report.py .

RUN useradd --create-home appuser
USER appuser

CMD ["python", "nightly_report.py"]
