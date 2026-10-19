# Dockerfile: builds the backend container image.
#
# What it is: a recipe Docker follows to package the FastAPI app and its
# Python dependencies into one image that runs the same everywhere
# (your laptop, GitHub Actions, AWS ECS Fargate).
#
# One image, two uses:
#   - API (default command below): uvicorn serves the app on port 8000.
#     In AWS, ECS runs it behind the load balancer, which checks /health.
#   - Nightly report job: the same image with the command overridden to
#     `python -m app.report` (see app/report.py), started by Step Functions.
#
# Settings such as DB_HOST and DB_PASSWORD are NOT baked in. They come
# from environment variables at run time (in AWS, the password is injected
# from Secrets Manager), so the image contains no secrets.
#
# Build and run locally:
#   docker build -t smallproject-backend .
#   docker run -p 8000:8000 -e DB_HOST=... -e DB_PASSWORD=... smallproject-backend

# Small official Python base image, pinned by digest (@sha256:...) so a
# re-pushed 3.12-slim tag can't silently change what we build on.
# Dependabot (docker) bumps the digest when a new 3.12 patch ships.
FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1

WORKDIR /app

# Install dependencies first, so Docker can reuse this layer when only
# the app code changes (faster rebuilds).
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Then copy the application code.
COPY app ./app

# Documents the port the API listens on.
EXPOSE 8000

# Default command: start the API. 0.0.0.0 makes it reachable from outside
# the container.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
