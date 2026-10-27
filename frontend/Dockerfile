# Dockerfile: builds the website (React) as a container image: Node builds
# the static files, nginx serves them.
#
# Build only for now (build-frontend.yml): the live site is still the same
# build uploaded to S3 and served by CloudFront (deploy-frontend.yml).
# Base images are pinned by digest, like backend/Dockerfile.

FROM node:22-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
ARG VITE_API_BASE_URL=/api/v1
RUN npm run build

FROM nginx:1.28-alpine@sha256:a8b39bd9cf0f83869a2162827a0caf6137ddf759d50a171451b335cecc87d236
COPY --from=build /app/dist /usr/share/nginx/html
