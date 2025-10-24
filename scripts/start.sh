#!/bin/bash
set -e

echo "Replacing placeholders..."
bash scripts/replace-placeholder.sh

echo "Running Prisma migrations..."
cd packages/prisma && npx prisma migrate deploy --schema ./schema.prisma
cd ../..

# Start both services in background
echo "Starting API v2 on port 5555..."
yarn workspace @calcom/api-v2 start:prod &
API_PID=$!

echo "Starting web server on port 3000..."
yarn workspace @calcom/web start &
WEB_PID=$!

# Wait for both processes
echo "Both services started. Waiting..."
wait $API_PID $WEB_PID
