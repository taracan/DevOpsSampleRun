# Dockerfile: builds the website (React) as a container image: Node builds
# the static files, nginx serves them.
#
# Build only for now (build-frontend.yml): the live site is still the same
# build uploaded to S3 and served by CloudFront (deploy-frontend.yml).
# Base images are pinned by digest, like backend/Dockerfile.

FROM node:26-alpine@sha256:c6ad9e9c1d80f6eb607c26b4b0a132ff7a2344fad1c78ea3baa2a7d4c8de6d94 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE_URL=/api/v1
RUN npm run build

FROM nginx:1.31-alpine@sha256:785835ea65db4bba6f021acc0f3be91b0fef76a53fe41f8588c6698d2aed0606
COPY --from=build /app/dist /usr/share/nginx/html
