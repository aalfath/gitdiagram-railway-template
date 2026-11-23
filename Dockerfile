# GitDiagram for Railway, built from a pinned upstream commit.
# Upstream publishes no image and no release tags, so the source is fetched at
# a fixed commit and checked against its SHA-256. To update: change
# GITDIAGRAM_COMMIT and GITDIAGRAM_SHA256 together, add a CHANGELOG.md entry,
# and merge to main (that notifies every deployer).
ARG GITDIAGRAM_COMMIT=39847f550220c5b547696277fdea89b9ba9eaff5
ARG GITDIAGRAM_SHA256=86861e4408c99b22d04163288f2d7c7da80ac6f831f6fdb28d5f23efc889fbd5

FROM node:22.23.5-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS source
ARG GITDIAGRAM_COMMIT
ARG GITDIAGRAM_SHA256
WORKDIR /src
RUN node -e 'fetch(`https://codeload.github.com/ahmedkhaleel2004/gitdiagram/tar.gz/${process.argv[1]}`).then(async r=>{if(!r.ok)throw new Error("HTTP "+r.status);require("fs").writeFileSync("/tmp/src.tgz",Buffer.from(await r.arrayBuffer()))})' "$GITDIAGRAM_COMMIT" \
  && echo "$GITDIAGRAM_SHA256  /tmp/src.tgz" | sha256sum -c - \
  && tar -xzf /tmp/src.tgz --strip-components=1 --no-same-owner \
  && rm /tmp/src.tgz
COPY wrapper/patch.mjs /tmp/patch.mjs
RUN node /tmp/patch.mjs

FROM oven/bun:1.3.14-slim@sha256:d56a2534ffd262e92c12fd3249d3924d296d97086da773f821d7d0477435ea04 AS dependencies
WORKDIR /app
COPY --from=source /src/package.json /src/bun.lock ./
COPY --from=source /src/patches ./patches
RUN bun install --frozen-lockfile

FROM node:22.23.5-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS builder
WORKDIR /app
COPY --from=source /src ./
COPY --from=dependencies /app/node_modules ./node_modules
ENV NEXT_TELEMETRY_DISABLED=1 \
    RAILWAY_DOCKER_BUILD=1 \
    NEXT_SKIP_TYPECHECK=1 \
    NODE_OPTIONS=--max-old-space-size=3072
RUN node scripts/build-mcp-app.mjs && node node_modules/next/dist/bin/next build

# The Redis bridge needs only the official Redis client (no dependencies).
FROM node:22.23.5-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee AS shim
WORKDIR /opt/redis-rest-shim
RUN npm install --no-audit --no-fund --omit=dev @redis/client@6.3.0
COPY wrapper/redis-rest-shim.mjs ./

FROM caddy:2.11.9-alpine@sha256:003a97808e781aa9f7e75cc2f43d34d461099031faf5e20faefb9f61126836f0 AS caddy

FROM node:22.23.5-bookworm-slim@sha256:e9f565d32859f0cbfb52125eafe8be39390f24dac302dc3cdf566e8ba3ab21ee
ARG GITDIAGRAM_COMMIT
WORKDIR /app
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates tini \
  && rm -rf /var/lib/apt/lists/* \
  && groupadd --system --gid 1001 nodejs \
  && useradd --system --uid 1001 --gid nodejs --create-home nextjs
COPY --from=caddy /usr/bin/caddy /usr/local/bin/caddy
COPY --from=shim --chown=1001:1001 /opt/redis-rest-shim /opt/redis-rest-shim
COPY --from=builder --chown=1001:1001 /app/public ./public
COPY --from=builder --chown=1001:1001 /app/.next/standalone ./
COPY --from=builder --chown=1001:1001 /app/.next/static ./.next/static
COPY wrapper/Caddyfile /etc/gitdiagram-railway/Caddyfile
COPY wrapper/start.sh /usr/local/bin/gitdiagram-railway-start
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    GITDIAGRAM_VERSION=${GITDIAGRAM_COMMIT} \
    PORT=8080
USER nextjs
EXPOSE 8080
ENTRYPOINT ["tini", "--", "/usr/local/bin/gitdiagram-railway-start"]
