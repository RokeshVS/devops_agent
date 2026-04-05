#!/bin/bash
set -euo pipefail

# SCENARIO 3: Broken Deployment
echo "=========================================="
echo "SCENARIO 3: BROKEN DEPLOYMENT"
echo "=========================================="
echo ""
echo "This scenario tests: Deployment failure correlation across CodePipeline + ECS,"
echo "rollback suggestion via chat, and runbook execution from the Agent."
echo ""

CLUSTER_NAME="devops-agent-lab-cluster"
SERVICE_NAME="devops-agent-lab-dev-svc"
ECR_URL=$(aws ecr describe-repositories \
  --query "Repositories[?contains(repositoryName, 'app')].repositoryUri" \
  --output text | head -n1)

echo "Step 1: Saving current task definition..."
PREVIOUS_TASK_DEF=$(aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --query 'services[0].taskDefinition' \
  --output text)
echo "  Current task definition: $PREVIOUS_TASK_DEF"
echo ""

echo "Step 2: Creating and pushing a broken Docker image..."
BROKEN_TAG="broken-$(date +%s)"
cd app
sed -i.bak 's|CMD \["gunicorn".*|CMD ["python", "-c", "import sys; sys.exit(1)"]|' Dockerfile
docker build -t "$ECR_URL:$BROKEN_TAG" .
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin "$ECR_URL"
docker push "$ECR_URL:$BROKEN_TAG"
echo "  Pushed broken image: $ECR_URL:$BROKEN_TAG"
cd -
echo ""

echo "Step 3: Registering new task definition with broken image..."
CURRENT_TASK_DEF_FULL=$(aws ecs describe-task-definition \
  --task-definition "$PREVIOUS_TASK_DEF" \
  --query 'taskDefinition' \
  --output json)

BROKEN_TASK_DEF=$(echo "$CURRENT_TASK_DEF_FULL" | jq \
  ".containerDefinitions[0].image = \"$ECR_URL:$BROKEN_TAG\"" | \
  jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' | \
  aws ecs register-task-definition --cli-input-json file:///dev/stdin)

BROKEN_TASK_DEF_ARN=$(echo "$BROKEN_TASK_DEF" | jq -r '.taskDefinition.taskDefinitionArn')
echo "  Registered broken task definition: $BROKEN_TASK_DEF_ARN"
echo ""

echo "Step 4: Forcing ECS service to use broken image..."
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --task-definition "$BROKEN_TASK_DEF_ARN" \
  --force-new-deployment > /dev/null
echo "  Done"
echo ""

echo "Step 5: Waiting 90 seconds for deployment to fail..."
sleep 90
echo "Done"
echo ""

echo "Step 6: Checking service events..."
echo ""
aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" \
  --query 'services[0].events[0:5]' \
  --output table
echo ""

echo "============================================"
echo "OBSERVATIONS:"
echo "============================================"
echo "OBSERVE: ECS service shows runningCount < desiredCount"
echo "OBSERVE: Service events show deployment failures"
echo "OBSERVE: CodePipeline may also show failure if triggered"
echo ""

echo "============================================"
echo "TRY THESE DEVOPS AGENT CHAT PROMPTS:"
echo "============================================"
echo "1. 'My latest deployment broke the service. What failed?'"
echo "2. 'What was the last stable task definition before this deployment?'"
echo "3. 'Roll back my ECS service to the previous task definition'"
echo "4. 'Correlate the deployment timeline with the service health drop'"
echo ""

echo "============================================"
echo "RESTORING..."
echo "============================================"
echo ""

echo "Step 7: Rolling back to previous task definition..."
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --task-definition "$PREVIOUS_TASK_DEF" \
  --force-new-deployment > /dev/null
echo "  Done"
echo ""

echo "Step 8: Restoring Dockerfile..."
cd app
mv Dockerfile.bak Dockerfile || git checkout -- Dockerfile
cd -
echo "  Done"
echo ""

echo "Service will stabilize shortly. When fully restored, you can proceed"
echo "to the next scenario or run: ./scenarios/05_restore.sh"
