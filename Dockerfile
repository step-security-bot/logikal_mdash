# ── Build stage ──────────────────────────────────────────────────────────────
FROM node:22-slim@sha256:80fdb3f57c815e1b638d221f30a826823467c4a56c8f6a8d7aa091cd9b1675ea AS build

WORKDIR /app

# Copy workspace root manifests first for better layer caching
COPY package.json package-lock.json ./
COPY client/package.json client/
COPY server/package.json server/
COPY shared/package.json shared/

RUN npm ci

# Copy source code
COPY tsconfig.base.json ./
COPY shared/ shared/
COPY client/ client/
COPY server/ server/

# Build everything: shared types, client (Vite), server (tsc)
RUN npm run build

# ── Run stage ────────────────────────────────────────────────────────────────
FROM node:22-slim@sha256:80fdb3f57c815e1b638d221f30a826823467c4a56c8f6a8d7aa091cd9b1675ea AS run

WORKDIR /app

# Copy workspace root manifests
COPY package.json package-lock.json ./
COPY client/package.json client/
COPY server/package.json server/
COPY shared/package.json shared/

# Install production dependencies only
RUN npm ci --omit=dev

# Copy built artifacts from build stage
COPY --from=build /app/client/dist client/dist
COPY --from=build /app/server/dist server/dist

# Shared package exports types only (type-only imports in server).
# Copy its source so the workspace link resolves at install time.
COPY --from=build /app/shared/src shared/src

# Configurable environment variables
ENV PORT=3000
ENV STORAGE_DIR=/data
ENV BASE_URL=http://localhost:3000

# Storage volume mount point
VOLUME /data

EXPOSE ${PORT}

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:' + (process.env.PORT || 3000) + '/health').then(r => { if (!r.ok) process.exit(1) })"

CMD ["node", "server/dist/index.js"]
