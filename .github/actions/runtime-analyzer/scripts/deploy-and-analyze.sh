#!/bin/bash
set -euo pipefail

echo "🚀 Deploying application for runtime analysis..."

if [ -z "${IMAGE_REF:-}" ] || [ -z "${APP_NAME:-}" ]; then
  echo "❌ IMAGE_REF and APP_NAME environment variables are required"
  exit 1
fi

echo "### 🚀 Application Deployment" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY
echo "🎯 **Deploying image for runtime analysis: ${IMAGE_REF}**" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

# Create deployment manifest
cat > app-deployment.yaml << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  labels:
    app: ${APP_NAME}
    vex-enabled: "true"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
      annotations:
        vex.openvex.dev/available: "true"
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${IMAGE_REF}
        imagePullPolicy: Always
        ports:
        - containerPort: 8000 
        env:
        - name: PORT
          value: "8000"
        - name: ENV
          value: "production"
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        securityContext:
          runAsNonRoot: true
          runAsUser: 65532 
          allowPrivilegeEscalation: false
          capabilities:
            drop:
            - ALL
          readOnlyRootFilesystem: true
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}-service
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 8000
    nodePort: 30080
    protocol: TCP
  selector:
    app: ${APP_NAME}
EOF

# Deploy application
kubectl apply -f app-deployment.yaml

# Wait for deployment with progressive checks
echo "⏳ Waiting for deployment to be available..."

# First wait for deployment to exist
for i in {1..30}; do
  if kubectl get deployment ${APP_NAME} >/dev/null 2>&1; then
    break
  fi
  echo "⏳ Waiting for deployment to be created... ($i/30)"
  sleep 2
done

# Now wait for availability with shorter timeout and retries
DEPLOYMENT_SUCCESS=false
for attempt in {1..3}; do
  echo "🎯 Deployment attempt $attempt/3..."
  if kubectl wait --for=condition=available --timeout=120s deployment/${APP_NAME}; then
    DEPLOYMENT_SUCCESS=true
    break
  else
    echo "⚠️ Attempt $attempt failed, checking pod status..."
    kubectl get pods -l app=${APP_NAME} -o wide || true
    if [ $attempt -lt 3 ]; then
      echo "🔄 Retrying in 30 seconds..."
      sleep 30
    fi
  fi
done

if [ "$DEPLOYMENT_SUCCESS" = "true" ]; then
  REPLICAS=$(kubectl get deployment ${APP_NAME} -o jsonpath='{.status.replicas}')
  READY_REPLICAS=$(kubectl get deployment ${APP_NAME} -o jsonpath='{.status.readyReplicas}')
  
  echo "| 📋 Deployment Info | Value |" >> $GITHUB_STEP_SUMMARY
  echo "|-------------------|-------|" >> $GITHUB_STEP_SUMMARY
  echo "| 🚀 Application | ${APP_NAME} |" >> $GITHUB_STEP_SUMMARY
  echo "| 🖼️ Image | \`${IMAGE_REF}\` |" >> $GITHUB_STEP_SUMMARY
  echo "| 📊 Replicas | $REPLICAS |" >> $GITHUB_STEP_SUMMARY
  echo "| ✅ Ready Replicas | $READY_REPLICAS |" >> $GITHUB_STEP_SUMMARY
  echo "| 🔒 Security Context | Non-root, read-only filesystem |" >> $GITHUB_STEP_SUMMARY
  echo "| 🛡️ VEX Enabled | ✅ Yes |" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "✅ **Application deployed successfully with security hardening**" >> $GITHUB_STEP_SUMMARY
else
  echo "❌ **Application deployment failed after 3 attempts**" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "<details><summary>🔍 Deployment Troubleshooting</summary>" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo '```' >> $GITHUB_STEP_SUMMARY
  echo "=== Deployment Status ===" >> $GITHUB_STEP_SUMMARY
  kubectl describe deployment ${APP_NAME} >> $GITHUB_STEP_SUMMARY 2>&1 || echo "Failed to get deployment status" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "=== Pod Status ===" >> $GITHUB_STEP_SUMMARY
  kubectl get pods -l app=${APP_NAME} -o wide >> $GITHUB_STEP_SUMMARY 2>&1 || echo "No pods found" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "=== Pod Logs ===" >> $GITHUB_STEP_SUMMARY
  kubectl logs -l app=${APP_NAME} --tail=50 >> $GITHUB_STEP_SUMMARY 2>&1 || echo "No logs available" >> $GITHUB_STEP_SUMMARY
  echo '```' >> $GITHUB_STEP_SUMMARY
  echo "</details>" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "🔧 **Continuing with partial deployment for VEX generation...**" >> $GITHUB_STEP_SUMMARY
  # Don't exit - try to continue with partial deployment
fi
echo "" >> $GITHUB_STEP_SUMMARY

# Generate runtime load
echo "🔄 Starting comprehensive runtime testing for VEX analysis..."
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "### 🔄 Runtime Load Generation" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY
echo "🎯 **Running comprehensive runtime tests to trigger security analysis**" >> $GITHUB_STEP_SUMMARY
echo "" >> $GITHUB_STEP_SUMMARY

SUCCESS_COUNT=0
TOTAL_REQUESTS=0

# Test service connectivity first
echo "🔍 Testing service connectivity..."
SERVICE_READY=false
for test_attempt in {1..10}; do
  if curl -s --max-time 10 "http://$NODE_IP:30080/health" > /dev/null 2>&1 || \
     curl -s --max-time 10 "http://$NODE_IP:30080" > /dev/null 2>&1; then
    SERVICE_READY=true
    echo "✅ Service is responding"
    break
  else
    echo "⏳ Waiting for service to be ready... ($test_attempt/10)"
    sleep 5
  fi
done

if [ "$SERVICE_READY" = "true" ]; then
  echo "🚀 **Service ready - starting comprehensive testing**" >> $GITHUB_STEP_SUMMARY
  echo "" >> $GITHUB_STEP_SUMMARY
  
  # Run the comprehensive runtime testing script
  echo "🎭 Running runtime test suite..."
  
  if [ -f "scripts/test-during-runtime.sh" ]; then
    echo "✅ **Runtime test script found - executing comprehensive test suite**" >> $GITHUB_STEP_SUMMARY
    
    # Run the script and capture output
    # Calculate dynamic timeout based on vex-analysis-time (max: analysis time, min: 300s)
    VEX_TIME_SECONDS=$(echo "${VEX_ANALYSIS_TIME:-15m}" | sed 's/m/*60/g; s/s//g; s/h/*3600/g' | bc -l 2>/dev/null | cut -d. -f1 || echo "900")
    MAIN_TEST_TIMEOUT=$((VEX_TIME_SECONDS > 300 ? VEX_TIME_SECONDS : 300))
    
    echo "🕒 Using dynamic timeout: ${MAIN_TEST_TIMEOUT}s (based on VEX analysis time: ${VEX_ANALYSIS_TIME:-15m})"
    
    if timeout $MAIN_TEST_TIMEOUT bash scripts/test-during-runtime.sh "$NODE_IP" "30080" > runtime-test-output.log 2>&1; then
      TOTAL_REQUESTS=$(grep "Total Requests:" runtime-test-output.log | awk '{print $NF}' || echo "0")
      SUCCESS_COUNT=$(grep "Successful:" runtime-test-output.log | awk '{print $NF}' || echo "0")
      SUCCESS_RATE=$(grep "Success Rate:" runtime-test-output.log | awk '{print $NF}' | tr -d '%' || echo "0")
      
      echo "✅ **Comprehensive runtime testing completed successfully**" >> $GITHUB_STEP_SUMMARY
      echo "" >> $GITHUB_STEP_SUMMARY
      echo "| 🎯 Test Results | Value |" >> $GITHUB_STEP_SUMMARY
      echo "|----------------|-------|" >> $GITHUB_STEP_SUMMARY
      echo "| 📊 Total Requests | $TOTAL_REQUESTS |" >> $GITHUB_STEP_SUMMARY
      echo "| ✅ Successful Requests | $SUCCESS_COUNT |" >> $GITHUB_STEP_SUMMARY
      echo "| 📈 Success Rate | ${SUCCESS_RATE}% |" >> $GITHUB_STEP_SUMMARY
      echo "| 🎭 Test Categories | Health, API, Security, Fuzzing, Load, Edge Cases |" >> $GITHUB_STEP_SUMMARY
      echo "" >> $GITHUB_STEP_SUMMARY
      
      # Show test phases completed
      echo "<details><summary>🔍 Test Execution Details</summary>" >> $GITHUB_STEP_SUMMARY
      echo "" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
      tail -20 runtime-test-output.log >> $GITHUB_STEP_SUMMARY 2>/dev/null || echo "Test output not available" >> $GITHUB_STEP_SUMMARY
      echo '```' >> $GITHUB_STEP_SUMMARY
      echo "</details>" >> $GITHUB_STEP_SUMMARY
      
    else
      echo "⚠️ **Runtime test script timed out or failed, falling back to basic load generation**" >> $GITHUB_STEP_SUMMARY
      
      # Fallback to basic load generation
      SUCCESS_COUNT=0
      TOTAL_REQUESTS=30
      for i in $(seq 1 $TOTAL_REQUESTS); do
        if curl -s --max-time 5 "http://$NODE_IP:30080" > /dev/null 2>&1; then
          SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        fi
        sleep 1
      done
    fi
  else
    echo "⚠️ **Runtime test script not found, using basic load generation**" >> $GITHUB_STEP_SUMMARY
    
    # Fallback to basic load generation
    SUCCESS_COUNT=0
    TOTAL_REQUESTS=30
    for i in $(seq 1 $TOTAL_REQUESTS); do
      if curl -s --max-time 5 "http://$NODE_IP:30080" > /dev/null 2>&1; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      fi
      if [ $((i % 10)) -eq 0 ]; then
        PROGRESS=$((i * 100 / TOTAL_REQUESTS))
        echo "📊 Progress: $PROGRESS% ($i/$TOTAL_REQUESTS requests)" >> $GITHUB_STEP_SUMMARY
      fi
      sleep 1
    done
    
    echo "" >> $GITHUB_STEP_SUMMARY
    echo "| 📊 Basic Load Results | Value |" >> $GITHUB_STEP_SUMMARY
    echo "|----------------------|-------|" >> $GITHUB_STEP_SUMMARY
    echo "| 🎯 Total Requests | $TOTAL_REQUESTS |" >> $GITHUB_STEP_SUMMARY
    echo "| ✅ Successful Requests | $SUCCESS_COUNT |" >> $GITHUB_STEP_SUMMARY
    echo "| 📈 Success Rate | $((TOTAL_REQUESTS > 0 ? SUCCESS_COUNT * 100 / TOTAL_REQUESTS : 0))% |" >> $GITHUB_STEP_SUMMARY
  fi
else
  echo "⚠️ **Service not responding, generating minimal load...**" >> $GITHUB_STEP_SUMMARY
  # Still attempt some requests to trigger analysis
  SUCCESS_COUNT=0
  TOTAL_REQUESTS=5
  for i in $(seq 1 $TOTAL_REQUESTS); do
    curl -s --max-time 10 "http://$NODE_IP:30080" > /dev/null 2>&1 && SUCCESS_COUNT=$((SUCCESS_COUNT + 1)) || true
    sleep 3
  done
  
  echo "" >> $GITHUB_STEP_SUMMARY
  echo "| 📊 Minimal Load Results | Value |" >> $GITHUB_STEP_SUMMARY
  echo "|------------------------|-------|" >> $GITHUB_STEP_SUMMARY
  echo "| 🎯 Total Requests | $TOTAL_REQUESTS |" >> $GITHUB_STEP_SUMMARY
  echo "| ✅ Successful Requests | $SUCCESS_COUNT |" >> $GITHUB_STEP_SUMMARY
  echo "| 📈 Success Rate | $((SUCCESS_COUNT * 100 / TOTAL_REQUESTS))% |" >> $GITHUB_STEP_SUMMARY
fi
echo "" >> $GITHUB_STEP_SUMMARY