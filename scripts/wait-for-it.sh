#!/bin/bash
# Wait for a host and port before continuing
host="$1"
port="$2"

while ! nc -z $host $port; do
  echo "Waiting for $host:$port..."
  sleep 2
done

echo "$host:$port is available!"
