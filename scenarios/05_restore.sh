#!/bin/bash

# SCENARIO 5: Environment Restore
echo "=========================================="
echo "SCENARIO 5: ENVIRONMENT RESTORE"
echo "=========================================="
echo ""
echo "This scenario restores the environment to known-good state"
echo "after running any of the other test scenarios."
echo ""

CLUSTER_NAME="devops-agent-lab-cluster"
SERVICE_NAME="devops-agent-lab-dev-svc"

echo "Step 1: Re-authorizing RDS SG ingress from ECS SG..."
ECS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=devops-agent-lab" \
           "Name=tag:Name,Values=*ecs-sg*" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

RDS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=devops-agent-lab" \
           "Name=tag:Name,Values=*rds-sg*" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Attempt to authorize; ignore if already exists
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG_ID" \
  --protocol tcp \
  --port 5432 \
  --source-group "$ECS_SG_ID" 2>/dev/null || echo "  (Rule already authorized)"
echo "Done"
echo ""

echo "Step 2: Force new ECS deployment to restart all tasks..."
aws ecs update-service \
  --cluster "$CLUSTER_NAME" \
  --service "$SERVICE_NAME" \
  --force-new-deployment > /dev/null
echo "Done"
echo ""

echo "Step 3: Waiting for service to stabilize (up to 300 seconds)..."
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services "$SERVICE_NAME" || echo "  (Timeout or error; waiting 30 seconds...)" && sleep 30
echo "Done"
echo ""

echo "Step 4: Health check..."
if [ -z "${TASK_IP:-}" ]; then
  echo "  TASK_IP not set; skipping health check"
else
  HEALTH=$(curl -s -w "%{http_code}" -o /dev/null "http://$TASK_IP:8080/health" || echo "000")
  if [ "$HEALTH" = "200" ]; then
    echo "  ✓ Health check passed (HTTP 200)"
  else
    echo "  ! Health check returned HTTP $HEALTH (may still be healing)"
  fi
fi
echo ""

echo "============================================"
echo "TRY THESE DEVOPS AGENT CHAT PROMPTS:"
echo "============================================"
echo "1. 'Is the service fully healthy now? Give me a post-incident summary'"
echo "2. 'What can we do to prevent this class of incident from happening again?'"
echo ""
