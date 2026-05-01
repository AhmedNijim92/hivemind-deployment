#!/bin/bash
set -e

ENV=${1:-dev}

echo "🔍 Showing diff for $ENV environment"

cd "$(dirname "$0")/.."

helmfile -e $ENV diff
