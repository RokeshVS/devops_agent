#!/bin/bash

# SCENARIO : Database Connectivity Failure
echo "=========================================="
echo "SCENARIO : DATABASE CONNECTIVITY FAILURE"
echo "=========================================="
echo ""
echo "This scenario tests: DevOps Agent detects DB connectivity incident,"
echo "correlates the alarm with the security group change, and suggests remediation."
echo ""

if [ -z "${TASK_IP:-}" ]; then
  echo "ERROR: TASK_IP environment variable not set"
  exit 1
fi

echo "Step 1: Finding ECS and RDS security groups..."
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

echo "ECS Security Group: $ECS_SG_ID"
echo "RDS Security Group: $RDS_SG_ID"
echo ""

echo "Step 2: Revoking ECS → RDS ingress rule (port 5432)..."
aws ec2 revoke-security-group-ingress \
  --group-id "$RDS_SG_ID" \
  --protocol tcp \
  --port 5432 \
  --source-group "$ECS_SG_ID" || echo "Rule already revoked or doesn't exist"
echo "Done"
echo ""

echo "Step 3: Waiting 30 seconds for metrics to update..."
sleep 30
echo "Done"
echo ""

echo "Step 4: Testing /health endpoint (expecting failures)..."
for i in $(seq 1 10); do
  echo "  Attempt $i: $(curl -s -w '%{http_code}' -o /dev/null http://$TASK_IP:8080/health || echo 'FAILED')"
  sleep 3
done
echo ""

echo "============================================"
echo "TRY THESE DEVOPS AGENT CHAT PROMPTS:"
echo "============================================"
echo "1. 'Why is my ECS service returning health check failures?'"
echo "2. 'What infrastructure changes happened in the last 30 minutes?'"

echo "When done, run: ./scenarios/restore.sh"
