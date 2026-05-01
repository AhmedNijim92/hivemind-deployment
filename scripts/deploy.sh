#!/bin/bash
set -e

ENV=${1:-dev}
SERVICE=${2:-all}

echo "🚀 Deploying HiveMind to $ENV environment"

cd "$(dirname "$0")/.."

if [ "$SERVICE" = "all" ]; then
    echo "📦 Deploying all services..."
    helmfile -e $ENV apply
else
    echo "📦 Deploying $SERVICE..."
    helmfile -e $ENV -l app=$SERVICE apply
fi

echo "✅ Deployment complete!"
echo "🔍 Checking pod status..."
kubectl get pods -n hivemind

echo ""
echo "📊 To view logs: kubectl logs -f deployment/$SERVICE -n hivemind"
echo "📈 To view status: helmfile -e $ENV status"
