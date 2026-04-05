#!/bin/bash
set -euo pipefail

# SCENARIO 4: Memory Pressure
echo "=========================================="
echo "SCENARIO 4: MEMORY PRESSURE"
echo "=========================================="
echo ""
echo "This scenario tests: Proactive insight generation, rightsizing recommendation,"
echo "and observability-driven SRE advice."
echo ""

if [ -z "${TASK_IP:-}" ]; then
  echo "ERROR: TASK_IP environment variable not set"
  exit 1
fi

CLUSTER_NAME="devops-agent-lab-cluster"
ALARM_NAME="devops-agent-lab-ecs-memory-high"
SERVICE_NAME="devops-agent-lab-dev-svc"

echo "Step 1: Triggering memory allocation (300 MB in 512 MB task)..."
curl -s "http://$TASK_IP:8080/stress/memory" > /dev/null || echo "Request may have timed out"
echo "Done"
echo ""

echo "Step 2: Polling memory utilization every 15 seconds for 3 minutes..."
END_TIME=$(($(date +%s) + 180))

while [ $(date +%s) -lt $END_TIME ]; do
  MEMORY_UTIL=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/ECS \
    --metric-name MemoryUtilization \
    --dimensions Name=ClusterName,Value=$CLUSTER_NAME Name=ServiceName,Value=$SERVICE_NAME \
    --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average \
    --query 'Datapoints[-1].Average' \
    --output text 2>/dev/null || echo "N/A")
  
  ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text)
  
  printf "Memory: %s%% | Alarm: %s\n" "${MEMORY_UTIL:--}" "$ALARM_STATE"
  
  if [ "$ALARM_STATE" = "ALARM" ]; then
    echo "Memory alarm triggered!"
    break
  fi
  
  sleep 15
done
echo ""

echo "============================================"
echo "OBSERVATIONS:"
echo "============================================"
echo "OBSERVE: MemoryUtilization alarm firing in CloudWatch"
echo "OBSERVE: CloudWatch Dashboard devops-agent-lab-overview — Memory widget elevated"
echo "OBSERVE: DevOps Guru may display Proactive Insight about memory"
echo ""

echo "============================================"
echo "TRY THESE DEVOPS AGENT CHAT PROMPTS:"
echo "============================================"
echo "1. 'My ECS task is consuming excessive memory. Should I scale up or optimize?'"
echo "2. 'What is the optimal memory configuration for this task based on usage data?'"
echo "3. 'Show me a memory utilization trend for the last 24 hours'"
echo "4. 'Generate an incident report for the memory event that just occurred'"
echo ""

echo "When done, run: ./scenarios/05_restore.sh"
