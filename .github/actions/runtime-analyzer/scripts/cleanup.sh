#!/bin/bash
set -euo pipefail

echo "🧹 Cleaning up runtime analysis environment..."

echo "### 🧹 Cleanup Process" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

# Force cleanup any hanging processes
pkill -f "kubectl port-forward" || true
pkill -f "kind" || true

# Get the repository name for cleanup (fallback if APP_NAME not set)
REPO_NAME=$(echo "${GITHUB_REPOSITORY:-}" | cut -d'/' -f2)
CLEANUP_APP="${APP_NAME:-$REPO_NAME}"

# Check if we used an external cluster or Kind
if [ "${USE_EXTERNAL_CLUSTER:-false}" = "true" ]; then
  echo "🔗 Used external cluster - skipping cluster deletion..."
  echo "✅ **External cluster preserved (no cleanup needed)**" >> $GITHUB_STEP_SUMMARY
  
  # Clean up our application deployments only
  if [ -n "$CLEANUP_APP" ]; then
    kubectl delete deployment "$CLEANUP_APP" --ignore-not-found=true || true
    kubectl delete service "$CLEANUP_APP-service" --ignore-not-found=true || true
    echo "✅ **Application resources cleaned up**" >> $GITHUB_STEP_SUMMARY
  fi
else
  # Delete Kind cluster with timeout
  if command -v kind &> /dev/null; then
    echo "🗑️ Deleting Kind cluster..."
    CLUSTER_NAME="${CLUSTER_NAME:-security-analysis-cluster}"
    timeout 60s kind delete cluster --name "$CLUSTER_NAME" || {
      echo "⚠️ **Cluster deletion timed out, forcing cleanup...**" >> $GITHUB_STEP_SUMMARY
      docker ps -a --filter "label=io.x-k8s.kind.cluster=$CLUSTER_NAME" -q | xargs -r docker rm -f || true
    }
    echo "✅ **Kind cluster cleanup attempted**" >> $GITHUB_STEP_SUMMARY
  fi
  
  # Clean up Docker networks
  docker network ls --filter "name=kind" -q | xargs -r docker network rm || true
  
  # Clean up any leftover containers
  docker ps -a --filter "label=io.x-k8s.kind.cluster" -q | xargs -r docker rm -f || true
fi

# Clean up temporary files
rm -f kind-config.yaml app-deployment.yaml || true
rm -f ~/.kube/config || true
echo "✅ **Temporary files cleaned up**" >> $GITHUB_STEP_SUMMARY

echo "✅ **Cleanup completed**" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY