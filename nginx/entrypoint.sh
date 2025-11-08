#!/bin/sh
set -eu

echo "Rendering nginx templates..."

mkdir -p /var/log/nginx

# Create access.log and error.log if they don't exist
touch /var/log/nginx/access.log
touch /var/log/nginx/error.log

echo "Starting nginx (exec)..."
exec "$@"

