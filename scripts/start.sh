#!/bin/bash
set -e

echo "Replacing placeholders..."
bash scripts/replace-placeholder.sh

echo "Running Prisma migrations..."
cd packages/prisma && npx prisma migrate deploy --schema ./schema.prisma
cd ../..

echo "Starting web and API servers..."
concurrently "yarn --cwd apps/web start" "yarn --cwd apps/api/v2 start"
