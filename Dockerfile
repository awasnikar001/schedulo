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
ARG MAX_OLD_SPACE_SIZE=4096

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

# Copy package files first (better caching)
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
COPY turbo.json ./
COPY packages/prisma/schema.prisma ./packages/prisma/schema.prisma
COPY packages/prisma/package.json ./packages/prisma/package.json

# Install dependencies
RUN yarn install --frozen-lockfile --network-timeout 1000000

# Copy the rest of the application
COPY . .

# Generate Prisma Client
RUN yarn workspace @calcom/prisma prisma generate

# Build the application with memory optimization
ENV NODE_OPTIONS="--max-old-space-size=${MAX_OLD_SPACE_SIZE}"
RUN yarn build

# Build API v2 separately for better control
RUN yarn workspace @calcom/api-v2 build || echo "API v2 build skipped"

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

# Copy built application from builder
COPY --from=builder --chown=nodejs:nodejs /calcom ./

# Copy scripts and make executable
COPY --chown=nodejs:nodejs scripts ./scripts
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
