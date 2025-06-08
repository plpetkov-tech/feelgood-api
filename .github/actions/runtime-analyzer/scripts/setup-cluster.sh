#!/bin/bash
set -euo pipefail

# Runtime Analyzer: Setup Cluster Script
echo "🎲 Setting up Kubernetes cluster for runtime analysis..."

# Input parameters (passed as environment variables)
CLUSTER_NAME="${CLUSTER_NAME:-security-analysis-cluster}"
USE_EXTERNAL_CLUSTER="${USE_EXTERNAL_CLUSTER:-false}"
VEX_ANALYSIS_TIME="${VEX_ANALYSIS_TIME:-15m}"
TIMEOUT="${TIMEOUT:-600}"

# Check if we should use external cluster (kubeconfig should be pre-configured)
if [ "$USE_EXTERNAL_CLUSTER" = "true" ] && [ -f ~/.kube/config ]; then
  echo "🔗 Using existing Kubernetes cluster from KUBECONFIG..."
  
  # Verify cluster connectivity
  echo "🔍 Testing kubectl connectivity..."
  if kubectl cluster-info; then
    NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
    K8S_VERSION=$(kubectl version --client=false -o json | jq -r '.serverVersion.gitVersion')
    CLUSTER_NAME=$(kubectl config current-context)
    
    echo "### 🔗 Existing Kubernetes Cluster" >> $GITHUB_STEP_SUMMARY
    echo "" >> $GITHUB_STEP_SUMMARY
    echo "| 📋 Cluster Information | Value |" >> $GITHUB_STEP_SUMMARY
    echo "|------------------------|-------|" >> $GITHUB_STEP_SUMMARY
    echo "| 🔗 Cluster Context | $CLUSTER_NAME |" >> $GITHUB_STEP_SUMMARY
    echo "| 🖥️ Node Count | $NODE_COUNT |" >> $GITHUB_STEP_SUMMARY
    echo "| ⚙️ Kubernetes Version | $K8S_VERSION |" >> $GITHUB_STEP_SUMMARY
    echo "| 🔧 Runtime | External Cluster |" >> $GITHUB_STEP_SUMMARY
    echo "" >> $GITHUB_STEP_SUMMARY
    echo "✅ **Using existing Kubernetes cluster**" >> $GITHUB_STEP_SUMMARY
    echo "" >> $GITHUB_STEP_SUMMARY
  else
    echo "❌ **Failed to connect to existing cluster, falling back to Kind**" >> $GITHUB_STEP_SUMMARY
    USE_KIND=true
  fi
else
  USE_KIND=true
fi

# Fallback to Kind cluster if no external cluster or connection failed
if [ "${USE_KIND:-false}" = "true" ]; then
  echo "🎲 Creating new Kind cluster for runtime analysis..."
  
  # Create Kind cluster
  cat > kind-config.yaml << EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 30080
    hostPort: 30080
    protocol: TCP
EOF
  
  # Install Kind if not present
  if ! command -v kind &> /dev/null; then
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
  fi
  
  # Create cluster
  kind create cluster --config=kind-config.yaml --wait=60s
  
  # Verify cluster
  kubectl cluster-info
  NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
  K8S_VERSION=$(kubectl version --client=false -o json | jq -r '.serverVersion.gitVersion')
  
  echo "### 🎲 Kind Kubernetes Cluster" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "| 📋 Cluster Information | Value |" >> $GITHUB_STEP_SUMMARY
  echo "|------------------------|-------|" >> $GITHUB_STEP_SUMMARY
  echo "| 🎲 Cluster Name | ${CLUSTER_NAME} |" >> $GITHUB_STEP_SUMMARY
  echo "| 🖥️ Node Count | $NODE_COUNT |" >> $GITHUB_STEP_SUMMARY
  echo "| ⚙️ Kubernetes Version | $K8S_VERSION |" >> $GITHUB_STEP_SUMMARY
  echo "| 🔧 Runtime | Kind (Docker) |" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "✅ **Kind cluster ready for deployment**" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
fi

# Install Kubescape Operator
echo "🛡️ Installing Kubescape Operator with VEX generation..."

# Ensure helm is available
if ! command -v helm &> /dev/null; then
  echo "📥 Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add kubescape https://kubescape.github.io/helm-charts/
helm repo update

echo "### 🛡️ Kubescape Operator Installation" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

# Install Kubescape with VEX generation enabled
echo "🔧 Configuring VEX analysis duration: ${VEX_ANALYSIS_TIME}"
if helm upgrade --install kubescape kubescape/kubescape-operator \
  -n kubescape \
  --create-namespace \
  --set clusterName=${CLUSTER_NAME} \
  --set capabilities.vexGeneration=enable \
  --set capabilities.vulnerabilityScan=enable \
  --set capabilities.relevancy=enable \
  --set capabilities.runtimeObservability=enable \
  --set capabilities.networkEventsStreaming=disable \
  --set nodeAgent.config.applicationActivityTime=${VEX_ANALYSIS_TIME} \
  --set nodeAgent.config.learningPeriod=${VEX_ANALYSIS_TIME} \
  --set nodeAgent.config.maxLearningPeriod=${VEX_ANALYSIS_TIME} \
  --set nodeAgent.config.updatePeriod=1m \
  --set kubevuln.config.storeFilteredSbom=true \
  --wait \
  --timeout=${TIMEOUT}s; then
  
  echo "✅ **Kubescape Operator installed successfully**" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "| 🔧 Capability | Status | Configuration |" >> $GITHUB_STEP_SUMMARY
  echo "|---------------|--------|---------------|" >> $GITHUB_STEP_SUMMARY
  echo "| 📋 VEX Generation | ✅ Enabled | Learning: ${VEX_ANALYSIS_TIME}, Max: 24h, Update: 10m |" >> $GITHUB_STEP_SUMMARY
  echo "| 📦 Filtered SBOM Storage | ✅ Enabled | Runtime-relevant components only |" >> $GITHUB_STEP_SUMMARY
  echo "| 🛡️ Vulnerability Scan | ✅ Enabled | - |" >> $GITHUB_STEP_SUMMARY
  echo "| 🎯 Relevancy Analysis | ✅ Enabled | - |" >> $GITHUB_STEP_SUMMARY
  echo "| 🔍 Runtime Observability | ✅ Enabled | - |" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  
  # Verify configuration was applied correctly (non-blocking)
  echo "🔍 Verifying Kubescape configuration..."
  
  # Get the actual Helm values to verify configuration
  echo "📋 Checking Helm release values..."
  if helm get values kubescape -n kubescape > kubescape-values.yaml 2>/dev/null; then
    echo "✅ **Retrieved Helm values successfully**" >> $GITHUB_STEP_SUMMARY
    
    # Check if filtered SBOM storage is actually enabled
    if grep -q "storeFilteredSbom.*true" kubescape-values.yaml; then
      echo "✅ **Confirmed: Filtered SBOM storage is enabled**" >> $GITHUB_STEP_SUMMARY
    else
      echo "⚠️ **Warning: Filtered SBOM storage may not be enabled**" >> $GITHUB_STEP_SUMMARY
      echo "📋 **Current kubevuln config:**" >> $GITHUB_STEP_SUMMARY
      echo '```yaml' >> $GITHUB_STEP_SUMMARY
      grep -A 3 -B 3 "kubevuln" kubescape-values.yaml >> $GITHUB_STEP_SUMMARY 2>&1 || echo "kubevuln config not found" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
    fi
    
    # Check nodeAgent configuration
    if grep -q "learningPeriod.*${VEX_ANALYSIS_TIME}" kubescape-values.yaml; then
      echo "✅ **Confirmed: Learning period set to ${VEX_ANALYSIS_TIME}**" >> $GITHUB_STEP_SUMMARY
    else
      echo "⚠️ **Warning: Learning period may not be set correctly**" >> $GITHUB_STEP_SUMMARY
      echo "📋 **Current nodeAgent config:**" >> $GITHUB_STEP_SUMMARY
      echo '```yaml' >> $GITHUB_STEP_SUMMARY
      grep -A 3 -B 3 "nodeAgent" kubescape-values.yaml >> $GITHUB_STEP_SUMMARY 2>&1 || echo "nodeAgent config not found" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
    fi
  else
    echo "⚠️ **Could not retrieve Helm values, checking via ConfigMaps...**" >> $GITHUB_STEP_SUMMARY
    
    # Fallback: check ConfigMaps
    echo "🔍 Checking Kubescape ConfigMaps..."
    kubectl get configmap -n kubescape > configmaps.txt 2>/dev/null || echo "Failed to get configmaps"
    
    if kubectl get configmap kubescape-config -n kubescape -o yaml > kubescape-config.yaml 2>/dev/null; then
      echo "✅ **Found kubescape-config ConfigMap**" >> $GITHUB_STEP_SUMMARY
      
      # Show relevant config sections
      echo "📋 **Configuration summary:**" >> $GITHUB_STEP_SUMMARY
      echo '```yaml' >> $GITHUB_STEP_SUMMARY
      grep -A 10 -B 2 -i "sbom\|vex\|learning\|node" kubescape-config.yaml >> $GITHUB_STEP_SUMMARY 2>&1 || echo "No relevant config found" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
    else
      echo "⚠️ **No configuration verification available**" >> $GITHUB_STEP_SUMMARY
      echo "📋 **Available ConfigMaps:**" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
      cat configmaps.txt >> $GITHUB_STEP_SUMMARY 2>&1 || echo "No configmaps found" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
    fi
  fi
  
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "📋 **Configuration verification completed (non-blocking)**" >> $GITHUB_STEP_SUMMARY
else
  echo "❌ **Kubescape installation failed**" >> $GITHUB_STEP_SUMMARY
  exit 1
fi
echo "" >> $GITHUB_STEP_SUMMARY

# Verify Kubescape core components with progressive timeout
echo "🔍 Verifying Kubescape deployment..."

# Define critical components that must be ready
CRITICAL_COMPONENTS=("kubescape" "kubevuln")

echo "### 🔍 Kubescape Pod Status" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

# Wait for critical components first
CRITICAL_SUCCESS=true
for component in "${CRITICAL_COMPONENTS[@]}"; do
  echo "⏳ Waiting for $component pods..."
  if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=$component -n kubescape --timeout=180s; then
    echo "✅ **$component pods ready**" >> $GITHUB_STEP_SUMMARY
  else
    echo "❌ **$component pods failed to start**" >> $GITHUB_STEP_SUMMARY
    CRITICAL_SUCCESS=false
  fi
done

# Check all pods status (informational)
POD_COUNT=$(kubectl get pods -n kubescape --no-headers | wc -l)
READY_COUNT=$(kubectl get pods -n kubescape --no-headers | grep -c "Running" || echo "0")
PENDING_COUNT=$(kubectl get pods -n kubescape --no-headers | grep -c "Pending\|ContainerCreating" || echo "0")

echo "" >> $GITHUB_STEP_SUMMARY
echo "| 📊 Pod Metrics | Count |" >> $GITHUB_STEP_SUMMARY
echo "|----------------|-------|" >> $GITHUB_STEP_SUMMARY
echo "| 🚀 Total Pods | $POD_COUNT |" >> $GITHUB_STEP_SUMMARY
echo "| ✅ Running Pods | $READY_COUNT |" >> $GITHUB_STEP_SUMMARY
echo "| ⏳ Pending Pods | $PENDING_COUNT |" >> $GITHUB_STEP_SUMMARY
echo "| 🎯 Success Rate | $((POD_COUNT > 0 ? READY_COUNT * 100 / POD_COUNT : 0))% |" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

# Show detailed pod status for debugging
echo "<details><summary>📋 Detailed Pod Status</summary>" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY
echo '```' >> $GITHUB_STEP_SUMMARY
kubectl get pods -n kubescape -o wide >> $GITHUB_STEP_SUMMARY 2>&1 || echo "Failed to get pod status" >> $GITHUB_STEP_SUMMARY
echo '```' >> $GITHUB_STEP_SUMMARY
echo "</details>" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

if [ "$CRITICAL_SUCCESS" = "true" ]; then
  echo "✅ **Critical Kubescape components are running**" >> $GITHUB_STEP_SUMMARY
  if [ "$PENDING_COUNT" -gt 0 ]; then
    echo "⚠️ **Some non-critical pods still starting (this is normal)**" >> $GITHUB_STEP_SUMMARY
  fi
else
  echo "❌ **Critical Kubescape components failed to start**" >> $GITHUB_STEP_SUMMARY
  echo "🔧 **Attempting to continue with available components...**" >> $GITHUB_STEP_SUMMARY
  # Don't exit - continue with what we have
fi
echo "" >> $GITHUB_STEP_SUMMARY
