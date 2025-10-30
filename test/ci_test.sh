#!/bin/sh
set -e

echo "🔍 Checking running containers..."
docker ps

echo "🩺 Checking container health..."
for container in blue green nginx; do
  status=$(docker inspect -f '{{.State.Health.Status}}' $container 2>/dev/null || echo "not_found")
  if [ "$status" != "healthy" ]; then
    echo "❌ $container is not healthy! (status: $status)"
    docker logs $container
    exit 1
  fi
done

echo "🌐 Testing Nginx endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/version || true)

if [ "$response" -ne 200 ]; then
  echo "❌ Health check failed! Nginx returned HTTP $response"
  exit 1
fi

echo "✅ All checks passed. Blue-Green deployment is healthy!"
