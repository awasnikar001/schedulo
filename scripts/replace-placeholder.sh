#!/bin/bash
echo "Replacing env placeholders..."
for file in $(grep -rl "PLACEHOLDER" .); do
  sed -i "s|PLACEHOLDER|${NEXT_PUBLIC_WEBAPP_URL}|g" "$file"
done
