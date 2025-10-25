# ---- build stage ----
FROM node:20-bullseye AS builder
WORKDIR /app

# Use the packageManager declared in package.json (yarn)
RUN corepack enable

# Build-time placeholder for NEXT_PUBLIC_WEBAPP_URL so Next.js compiles
# We rewrite it at runtime via scripts/replace-placeholder.sh
ARG BUILT_NEXT_PUBLIC_WEBAPP_URL="https://build.placeholder"
ENV NEXT_PUBLIC_WEBAPP_URL=${BUILT_NEXT_PUBLIC_WEBAPP_URL}

# Build-time required environment variables for Next.js config
# Provide placeholder defaults so build succeeds even without explicit build args
# Real secrets will be used at runtime from Fly.io secrets
ARG NEXTAUTH_SECRET="build-time-placeholder-secret-min-32-characters-long-xxxxxxxxxxxx"
ARG CALENDSO_ENCRYPTION_KEY="build-time-placeholder-encryption-key-32-chars-xxxxxxxxx"
ARG DATABASE_URL="postgresql://placeholder:placeholder@localhost:5432/placeholder"

ENV NEXTAUTH_SECRET=${NEXTAUTH_SECRET}
ENV CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}
ENV DATABASE_URL=${DATABASE_URL}
ENV NEXTAUTH_URL="${BUILT_NEXT_PUBLIC_WEBAPP_URL}/api/auth"

# For development/testing: bypass license checks
ENV IS_E2E="true"
ENV CALCOM_LICENSE_KEY="00000000-0000-0000-0000-000000000000"

# Copy repo (includes .yarn directory for Yarn Berry)
COPY . .

# Install deps with inline builds (better for monorepo)
RUN yarn install --inline-builds --network-timeout 300000

# Generate Prisma Client (essential for both apps)
RUN yarn workspace @calcom/prisma prisma generate

# Give Node more heap for large turborepo builds
ENV NODE_OPTIONS="--max-old-space-size=8192"
ENV TURBO_TELEMETRY_DISABLED="1"
ENV NEXT_TELEMETRY_DISABLED="1"

# Skip Sentry release in Docker builds (unless SENTRY_AUTH_TOKEN is provided)
ENV SENTRY_AUTH_TOKEN=""

# Build both apps with their dependencies in one pass
# The ... suffix includes dependencies, and --concurrency=1 prevents OOM
RUN yarn turbo run build --filter=@calcom/web... --filter=@calcom/api-v2... --concurrency=1

# ---- run stage ----
FROM node:20-bullseye-slim AS runner
WORKDIR /app
ENV NODE_ENV=production

# tini for sane PID1 (optional), wget for wait-for-it http mode  
RUN apt-get update && apt-get install -y tini wget && rm -rf /var/lib/apt/lists/*
ENTRYPOINT ["/usr/bin/tini","--"]

# Copy only necessary files from builder
COPY --from=builder /app/package.json /app/yarn.lock /app/.yarnrc.yml /app/i18n.json ./
COPY --from=builder /app/.yarn ./.yarn
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/apps/web ./apps/web
COPY --from=builder /app/apps/api/v2 ./apps/api/v2
COPY --from=builder /app/scripts ./scripts
COPY --from=builder /app/turbo.json ./turbo.json

# Clean up unnecessary files to reduce image size
RUN find . -name "*.test.ts" -o -name "*.test.tsx" -o -name "*.spec.ts" | xargs rm -f || true && \
    find . -name "__tests__" -type d | xargs rm -rf || true && \
    find . -name "*.map" | xargs rm -f || true

# Ensure scripts are executable
RUN chmod +x scripts/*.sh

# Ports & health
ENV PORT=3000
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=5 \
  CMD node -e "require('http').get('http://127.0.0.1:${process.env.PORT||3000}',r=>process.exit(r.statusCode<500?0:1)).on('error',()=>process.exit(1))"

# Environment knobs used by start.sh:
# - BUILT_NEXT_PUBLIC_WEBAPP_URL (same as build arg)
# - NEXT_PUBLIC_WEBAPP_URL (your real domain, set at runtime)
# - DATABASE_URL (Prisma), DATABASE_HOST (optional wait-for-it)
# - SEED_APP_STORE=true (first run only)
ENV BUILT_NEXT_PUBLIC_WEBAPP_URL="https://build.placeholder"

# Start script runs: replace placeholder -> migrate -> (seed) -> start API+Web
CMD ["bash","scripts/start.sh"]
