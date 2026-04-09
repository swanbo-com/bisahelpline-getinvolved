#!/bin/bash
# Deploy script — static site, production-only Blue/Green
set -e

BRANCH=$1
DOMAIN=$2
APP_NAME=$3
IMAGE_TAG=$4

TRAEFIK_NETWORK="traefik-public"

docker network inspect $TRAEFIK_NETWORK >/dev/null 2>&1 || \
    docker network create $TRAEFIK_NETWORK

echo "Starting deployment for branch: $BRANCH on domain: $DOMAIN"
echo "Target Image: $IMAGE_TAG"

# Pull the freshly built image from GitHub Container Registry
echo "Pulling image: $IMAGE_TAG"
if ! docker pull $IMAGE_TAG; then
    echo "CRITICAL ERROR: Failed to pull image $IMAGE_TAG. Aborting deployment."
    exit 1
fi

export APP_NAME=$APP_NAME
export DOMAIN=$DOMAIN
export IMAGE_TAG=$IMAGE_TAG

if [ "$BRANCH" != "main" ]; then
    echo "Error: Branch '$BRANCH' is not configured. Only 'main' is supported for this static site."
    exit 1
fi

echo "Executing Blue-Green Deployment..."

if docker ps --format '{{.Names}}' | grep -q "^${APP_NAME}-blue$"; then
    ACTIVE="blue"
    IDLE="green"
else
    ACTIVE="green"
    IDLE="blue"
fi

echo "Current active container is: $ACTIVE. Deploying to: $IDLE"

# Start the idle container with the new image
docker compose -f docker-compose.yml -p ${APP_NAME} up -d app-${IDLE}

echo "Waiting for app-${IDLE} to become healthy (up to 60s)..."
HEALTH_TIMEOUT=60
ELAPSED=0
while [ $ELAPSED -lt $HEALTH_TIMEOUT ]; do
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' ${APP_NAME}-${IDLE} 2>/dev/null || echo "missing")

    if [ "$HEALTH" == "healthy" ]; then
        echo "Container app-${IDLE} is healthy!"
        break
    elif [ "$HEALTH" == "missing" ]; then
        echo "CRITICAL ERROR: Container app-${IDLE} crashed completely!"
        docker compose -f docker-compose.yml -p ${APP_NAME} rm -f app-${IDLE} 2>/dev/null
        exit 1
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "  ...still waiting (${ELAPSED}s) - status: $HEALTH"
done

if [ "$HEALTH" != "healthy" ]; then
    echo "CRITICAL ERROR: Container app-${IDLE} did not become healthy within ${HEALTH_TIMEOUT}s!"
    echo "Aborting deployment to keep app-${ACTIVE} running seamlessly."
    docker compose -f docker-compose.yml -p ${APP_NAME} stop app-${IDLE}
    docker compose -f docker-compose.yml -p ${APP_NAME} rm -f app-${IDLE}
    exit 1
fi

if docker ps --format '{{.Names}}' | grep -q "^${APP_NAME}-${ACTIVE}$"; then
    echo "Tearing down old container: app-${ACTIVE}"
    docker compose -f docker-compose.yml -p ${APP_NAME} stop app-${ACTIVE}
    docker compose -f docker-compose.yml -p ${APP_NAME} rm -f app-${ACTIVE}
fi

echo "Blue-Green deployment completed successfully!"

# Clean up old unused Docker images to prevent disk from filling up
echo "Cleaning up old unused Docker images..."
docker image prune -af --filter "until=5m"
echo "Cleanup complete."
