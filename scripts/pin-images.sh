#!/bin/bash
# Pin all service images to their latest SHA tag for production deployments.
# Usage: ./scripts/pin-images.sh
#
# This fetches the latest SHA from Docker Hub for each service
# and generates a helmfile values override file.

set -e

REGISTRY="ahmednijim92"
SERVICES=(
  hivemind-auth-service
  hivemind-api-gateway
  hivemind-user-service
  hivemind-group-service
  hivemind-post-service
  hivemind-meeting-service
  hivemind-notification-service
  hivemind-media-service
  hivemind-config-server
  hivemind-eureka-server
  hivemind-frontend
)

OUTPUT="environments/prod/image-pins.yaml"

echo "# Auto-generated image pins — $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$OUTPUT"
echo "# Run ./scripts/pin-images.sh to regenerate" >> "$OUTPUT"
echo "" >> "$OUTPUT"
echo "images:" >> "$OUTPUT"

for svc in "${SERVICES[@]}"; do
  IMAGE="$REGISTRY/$svc"
  # Get the digest of the :latest tag
  DIGEST=$(docker manifest inspect "$IMAGE:latest" 2>/dev/null | grep -m1 '"digest"' | cut -d'"' -f4)
  if [ -n "$DIGEST" ]; then
    echo "  $svc: \"$IMAGE@$DIGEST\"" >> "$OUTPUT"
    echo "✓ $svc → $DIGEST"
  else
    echo "  $svc: \"$IMAGE:latest\"  # WARN: could not resolve digest" >> "$OUTPUT"
    echo "✗ $svc — using :latest (no digest found)"
  fi
done

echo ""
echo "Image pins written to $OUTPUT"
echo "Deploy with: helmfile -e prod sync"
