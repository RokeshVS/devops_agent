#!/bin/bash

# SCENARIO : High CPU Spike
echo "=========================================="
echo "SCENARIO : CPU SPIKE"
echo "=========================================="
echo ""
echo "This scenario tests: Anomaly detection, on-demand report generation,"
echo "and chat-based SRE analysis."
echo ""

if [ -z "${TASK_IP:-}" ]; then
  echo "ERROR: TASK_IP environment variable not set"
  exit 1
fi

CLUSTER_NAME="devops-agent-lab-cluster"
ALARM_NAME="devops-agent-lab-ecs-cpu-high"

echo "Step 1: Starting CPU stress test (will run 3 rounds of 5 parallel requests)..."
echo ""

for round in $(seq 1 3); do
  echo "Round $round: Initiating 5 parallel /stress/cpu requests..."
  for i in $(seq 1 5); do
    curl -s "http://$TASK_IP:8080/stress/cpu" > /dev/null &
  done
  wait
  echo "Round $round: Complete"
  
  echo "Checking CPU alarm state..."
  ALARM_STATE=$(aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text)
  echo "  Alarm state: $ALARM_STATE"
  
  if [ "$ALARM_STATE" = "ALARM" ]; then
    echo "  ✓ Alarm triggered!"
    break
  fi
  
  echo "  Waiting 20 seconds before next round..."
  sleep 20
done
echo ""

echo "============================================"
echo "OBSERVATIONS:"
echo "============================================"
echo "OBSERVE: CloudWatch Dashboard devops-agent-lab-overview — CPU widget spiking"
echo "OBSERVE: CloudWatch alarm '$ALARM_NAME' should be in ALARM state"
echo ""

echo "============================================"
echo "TRY THESE DEVOPS AGENT CHAT PROMPTS:"
echo "============================================"
echo "1. 'My ECS CPU is spiking. Is this a real incident or an anomaly?'"
echo "2. 'What is the blast radius if the CPU stays at this level?'"
echo ""

echo "When done, run: ./scenarios/05_restore.sh"
