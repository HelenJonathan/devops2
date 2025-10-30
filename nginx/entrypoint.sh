#!/bin/sh
set -eu

echo "Rendering nginx templates..."
envsubst < /etc/nginx/nginx.conf > /etc/nginx/conf.d/default.conf

echo "Starting nginx (exec)..."
exec "$@"