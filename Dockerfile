########################
# Stage 1: builder
########################
FROM --platform=$BUILDPLATFORM node:18 AS builder

WORKDIR /calcom

# Build-time args Cal.com needs so Next.js can bake config
ARG NEXT_PUBLIC_LICENSE_CONSENT
ARG NEXT_PUBLIC_WEBSITE_TERMS_URL
ARG NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL
ARG CALCOM_TELEMETRY_DISABLED
ARG DATABASE_URL
ARG NEXTAUTH_SECRET=secret
ARG CALENDSO_ENCRYPTION_KEY=secret
ARG MAX_OLD_SPACE_SIZE=4096
ARG NEXT_PUBLIC_API_V2_URL
ARG NEXT_PUBLIC_SINGLE_ORG_SLUG
ARG ORGANIZATIONS_ENABLED
ARG CSP_POLICY

ENV NEXT_PUBLIC_WEBAPP_URL=http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER \
    NEXT_PUBLIC_API_V2_URL=$NEXT_PUBLIC_API_V2_URL \
    NEXT_PUBLIC_LICENSE_CONSENT=$NEXT_PUBLIC_LICENSE_CONSENT \
    NEXT_PUBLIC_WEBSITE_TERMS_URL=$NEXT_PUBLIC_WEBSITE_TERMS_URL \
    NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL=$NEXT_PUBLIC_WEBSITE_PRIVACY_POLICY_URL \
    CALCOM_TELEMETRY_DISABLED=$CALCOM_TELEMETRY_DISABLED \
    DATABASE_URL=$DATABASE_URL \
    DATABASE_DIRECT_URL=$DATABASE_URL \
    NEXTAUTH_SECRET=${NEXTAUTH_SECRET} \
    CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY} \
    NEXT_PUBLIC_SINGLE_ORG_SLUG=$NEXT_PUBLIC_SINGLE_ORG_SLUG \
    ORGANIZATIONS_ENABLED=$ORGANIZATIONS_ENABLED \
    NODE_OPTIONS=--max-old-space-size=${MAX_OLD_SPACE_SIZE} \
    BUILD_STANDALONE=true \
    CSP_POLICY=$CSP_POLICY

# Copy the monorepo from YOUR repo layout (no calcom/ prefix)
COPY package.json yarn.lock .yarnrc.yml turbo.json i18n.json ./
COPY .yarn ./.yarn

COPY apps ./apps
COPY packages ./packages
COPY tests ./tests

# You told me you have both api/v1 and api/v2, so:
COPY apps/api/v1 ./apps/api/v1
COPY apps/api/v2 ./apps/api/v2

# Make yarn install more reliable
RUN yarn config set httpTimeout 1200000

# Create a pruned workspace for just what we need in production
RUN npx turbo prune --scope=@calcom/web --scope=@calcom/trpc --docker

# Install deps for that pruned workspace
RUN yarn install

# Build shared server layer first
RUN yarn workspace @calcom/trpc run build

# Build embed core
RUN yarn --cwd packages/embeds/embed-core workspace @calcom/embed-core run build

# Build the main Next.js web app (standalone output)
RUN yarn --cwd apps/web workspace @calcom/web run build

# Clean up cache to shrink image
RUN rm -rf node_modules/.cache .yarn/cache apps/web/.next/cache


########################
# Stage 2: builder-two
########################
FROM node:18 AS builder-two

WORKDIR /calcom

# Default runtime URL — Railway will override this via env vars
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000

ENV NODE_ENV=production

# Copy root config
COPY package.json .yarnrc.yml turbo.json i18n.json ./
COPY .yarn ./.yarn

# Bring compiled output + dependencies from builder stage
COPY --from=builder /calcom/yarn.lock ./yarn.lock
COPY --from=builder /calcom/node_modules ./node_modules
COPY --from=builder /calcom/packages ./packages
COPY --from=builder /calcom/apps ./apps
COPY --from=builder /calcom/packages/prisma/schema.prisma ./prisma/schema.prisma

# Copy the runtime scripts we just added to your repo
COPY scripts ./scripts

# Record the URL we built with, so we can detect changes at runtime
ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL

# Rewrite baked URLs (placeholder -> actual build-time URL)
RUN ./scripts/replace-placeholder.sh http://NEXT_PUBLIC_WEBAPP_URL_PLACEHOLDER ${NEXT_PUBLIC_WEBAPP_URL}


########################
# Stage 3: runner
########################
FROM node:18 AS runner

WORKDIR /calcom

# Copy everything from builder-two (ready-to-run app)
COPY --from=builder-two /calcom ./

# Default runtime URL, overridden in Railway with env vars
ARG NEXT_PUBLIC_WEBAPP_URL=http://localhost:3000

ENV NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    BUILT_NEXT_PUBLIC_WEBAPP_URL=$NEXT_PUBLIC_WEBAPP_URL \
    NODE_ENV=production

EXPOSE 3000

# Healthcheck (Railway uses this to mark service healthy)
HEALTHCHECK --interval=30s --timeout=30s --retries=5 \
    CMD wget --spider http://localhost:3000 || exit 1

# At runtime we:
# 1. compare BUILT_NEXT_PUBLIC_WEBAPP_URL vs NEXT_PUBLIC_WEBAPP_URL
# 2. rewrite URLs again if needed (for example: staging URL vs prod custom domain)
# 3. start the Next.js standalone server
CMD ["/calcom/scripts/start.sh"]
