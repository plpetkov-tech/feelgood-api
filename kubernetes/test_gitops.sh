#!/bin/bash

set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
# Get the workspace root directory (parent of tests directory)
WORKSPACE_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}==>${NC} $1"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

# Function to print error messages
print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Function to wait for pods to be ready
wait_for_pods() {
    local namespace=$1
    local label=$2
    local timeout=$3
    print_status "Waiting for pods with label $label in namespace $namespace to be ready..."
    kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="$timeout" || {
        print_error "Pods with label $label in namespace $namespace failed to become ready within $timeout"
        kubectl get pods -n "$namespace" -l "$label"
        exit 1
    }
}

# Create Kind cluster if it doesn't exist
if ! kind get clusters | grep -q gitops-host; then
    print_status "Creating Kind cluster..."
    kind create cluster --name gitops-host --config "$SCRIPT_DIR/kind-config.yaml"
else
    print_warning "Kind cluster 'gitops-host' already exists"
fi

# Wait for cluster to be ready
sleep 5

# Create flux-system namespace
print_status "Installing Kyverno in kyverno-system namespace..."
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update
helm install -n kyverno-system --create-namespace kyverno kyverno/kyverno
# Apply infrastructure components in order
print_status "Applying Kyverno Manifests..."
kubectl apply -f "$SCRIPT_DIR/kyverno-policies.yaml"
kubectl create ns bank-system

print_status "GitOps test deployment completed successfully!"
echo ""
echo "To clean up the cluster, run:"
echo "kind delete cluster --name gitops-host"
echo ""
echo "To use the cluster:"
echo "kubectl config use-context kind-gitops-host" 
echo ""
echo "To test the policy you can do:"
echo "kubectl run feelgood-api -it -n bank-system --rm --image ghcr.io/plpetkov-tech/feelgood-api:1.0.0 -- bash"
echo ""
echo "And if you get a shell, congrats! the Kyverno policies allowed that!"

