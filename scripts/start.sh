#!/bin/bash
set -e

echo "🚀 Starting Cal.com (Schedulo)"

# Wait for database to be ready (optional)
if [ -n "$DATABASE_HOST" ]; then
  echo "⏳ Waiting for database at $DATABASE_HOST..."
  ./scripts/wait-for-it.sh "$DATABASE_HOST" --timeout=60 --strict -- echo "✅ Database is ready"
fi

# Run database migrations
echo "📦 Running Prisma migrations..."
cd packages/prisma
npx prisma migrate deploy --schema ./schema.prisma
cd ../..

# Seed app store if needed (only on first run)
if [ "$SEED_APP_STORE" = "true" ]; then
  echo "🌱 Seeding app store..."
  yarn workspace @calcom/prisma db-seed || echo "⚠️  Seeding skipped or failed (non-fatal)"
fi

# Check if API v2 is built and should be started
API_V2_BUILT=false
if [ -f "apps/api/v2/dist/apps/api/v2/src/main.js" ]; then
  API_V2_BUILT=true
  echo "✅ API v2 detected and ready"
else
  echo "⚠️  API v2 not built, will start web only"
fi

# Start services based on what's available
if [ "$API_V2_BUILT" = "true" ] && [ -n "$REDIS_URL" ]; then
  echo "🎯 Starting both Web and API v2..."
  
  # Start API v2 in background
  echo "🔧 Starting API v2 on port ${API_PORT:-5555}..."
  yarn workspace @calcom/api-v2 start:prod &
  API_PID=$!
  
  # Start web server
  echo "🌐 Starting web server on port ${PORT:-3000}..."
  yarn workspace @calcom/web start &
  WEB_PID=$!
  
  # Wait for both processes
  echo "✨ Both services started. Press Ctrl+C to stop."
  wait $API_PID $WEB_PID
else
  # Start web only (safer default)
  echo "🌐 Starting web server on port ${PORT:-3000}..."
  yarn workspace @calcom/web start
fi
