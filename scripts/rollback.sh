#!/bin/bash
set -e

SERVICE=$1
ENV=${2:-prod}
REVISION=${3:-0}

if [ -z "$SERVICE" ]; then
    echo "Usage: ./rollback.sh <service-name> [environment] [revision]"
    echo "Example: ./rollback.sh auth-service prod 1"
    exit 1
fi

echo "⏪ Rolling back $SERVICE in $ENV to revision $REVISION"

helm rollback $SERVICE $REVISION -n hivemind

echo "✅ Rollback complete!"
kubectl get pods -n hivemind -l app=$SERVICE
