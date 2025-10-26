# ---- build stage ----
FROM node:20-bullseye AS builder
WORKDIR /calcom

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Enable Corepack for Yarn Berry
RUN corepack enable

# Build-time variables (following official Cal.com Docker approach)
ARG NEXT_PUBLIC_WEBAPP_URL="http://localhost:3000"
ARG NEXT_PUBLIC_LICENSE_CONSENT
ARG CALCOM_TELEMETRY_DISABLED=1
ARG DATABASE_URL="postgresql://placeholder:placeholder@localhost:5432/calendso"
ARG NEXTAUTH_SECRET="secret"
ARG CALENDSO_ENCRYPTION_KEY="secret"
ARG MAX_OLD_SPACE_SIZE=8192

# Set environment variables for build
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT \
    CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED \
    DATABASE_URL=$DATABASE_URL \
    NEXTAUTH_SECRET=$NEXTAUTH_SECRET \
    CALENDSO_ENCRYPTION_KEY=$CALENDSO_ENCRYPTION_KEY \
    NEXTAUTH_URL="${NEXT_PUBLIC_WEBAPP_URL}/api/auth"

# Official Cal.com localhost development license key (for build-time)
ENV CALCOM_LICENSE_KEY="59c0bed7-8b21-4280-8514-e022fbfc24c7"

# Disable telemetry
ENV NEXT_TELEMETRY_DISABLED=1 \
    TURBO_TELEMETRY_DISABLED=1

# Copy entire monorepo (Yarn Berry workspaces need all package.json files)
COPY . .

# Set Node memory limit BEFORE any operations that might trigger builds
ENV NODE_OPTIONS="--max-old-space-size=${MAX_OLD_SPACE_SIZE}"

# Install dependencies (with longer timeout)
RUN yarn install --network-timeout 1000000

# Generate Prisma Client (must be before any builds)
RUN yarn workspace @calcom/prisma prisma generate

# Build both web and API v2 in one command (Turbo handles dependencies correctly)
RUN yarn turbo run build --filter=@calcom/web... --filter=@calcom/api-v2... --concurrency=1

# ---- runtime stage ----
FROM node:20-bullseye-slim AS runner
WORKDIR /calcom

# Install runtime dependencies (following official Cal.com Docker)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tini \
    wget \
    curl \
    openssl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user (security best practice)
RUN groupadd --gid 1001 nodejs && \
    useradd --uid 1001 --gid nodejs --shell /bin/bash --create-home nodejs

# Copy only necessary runtime files from builder (not entire monorepo)
COPY --from=builder --chown=nodejs:nodejs /calcom/package.json /calcom/yarn.lock /calcom/.yarnrc.yml ./
COPY --from=builder --chown=nodejs:nodejs /calcom/.yarn ./.yarn
COPY --from=builder --chown=nodejs:nodejs /calcom/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /calcom/packages ./packages
COPY --from=builder --chown=nodejs:nodejs /calcom/apps/web ./apps/web
COPY --from=builder --chown=nodejs:nodejs /calcom/apps/api ./apps/api
COPY --from=builder --chown=nodejs:nodejs /calcom/turbo.json ./turbo.json

# Copy scripts and make executable
COPY --from=builder --chown=nodejs:nodejs /calcom/scripts ./scripts
RUN chmod +x scripts/*.sh

# Set production environment
ENV NODE_ENV=production \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1

# Expose ports
EXPOSE 3000 5555

# Health check (following official patterns)
HEALTHCHECK --interval=30s --timeout=10s --retries=5 --start-period=40s \
  CMD curl -f http://localhost:3000/api/health || exit 1

# Use tini for proper signal handling
ENTRYPOINT ["/usr/bin/tini", "--"]

# Switch to non-root user
USER nodejs

# Start the application
CMD ["/calcom/scripts/start.sh"]
