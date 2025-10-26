# ==========================================
# Simplified "Fat Container" for Staging
# ==========================================
# Purpose: Fast iteration, unblock deployment
# Tradeoff: Larger image (~1.5GB) for faster builds (~5 mins)
# Status: Staging-ready, production TODO
# ==========================================

FROM node:18-slim

WORKDIR /calcom

# Install only runtime system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openssl \
    ca-certificates \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Build-time args (needed by next.config.js even during build)
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000
ARG NEXTAUTH_SECRET=build-time-secret-placeholder
ARG CALENDSO_ENCRYPTION_KEY=build-time-encryption-placeholder
ARG DATABASE_URL=postgresql://placeholder:placeholder@localhost:5432/calendso

# Environment variables for build and runtime
ENV NODE_ENV=production \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    NEXTAUTH_URL=$NEXT_PUBLIC_WEBAPP_URL/api/auth \
    NEXTAUTH_SECRET=$NEXTAUTH_SECRET \
    CALENDSO_ENCRYPTION_KEY=$CALENDSO_ENCRYPTION_KEY \
    DATABASE_URL=$DATABASE_URL

# Copy EVERYTHING from your local repo as-is
# This includes:
# - Source code
# - .yarn cache (speeds up any yarn operations)
# - node_modules (if already installed locally)
# - packages (if already built locally)
COPY . .

# Enable Corepack for Yarn Berry
RUN corepack enable

# Safety net: Install dependencies if node_modules missing
# (Usually they'll exist from local dev)
RUN if [ ! -d "node_modules" ]; then \
      echo "Installing dependencies from scratch..."; \
      yarn install --immutable; \
    else \
      echo "Using existing node_modules from local"; \
    fi

# Safety net: Build if .next doesn't exist
# (Prefer building locally before Docker for speed)
RUN if [ ! -d "apps/web/.next" ]; then \
      echo "Building web app..."; \
      yarn workspace @calcom/prisma prisma generate && \
      yarn workspace @calcom/web build; \
    else \
      echo "Using existing build from local"; \
    fi

# Ensure Prisma is generated (critical for database access)
RUN yarn workspace @calcom/prisma prisma generate

EXPOSE 3000

# Health check for Railway/monitoring
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
    CMD wget --no-verbose --tries=1 --spider http://localhost:3000 || exit 1

# Start the Next.js app
CMD ["yarn", "workspace", "@calcom/web", "start"]
