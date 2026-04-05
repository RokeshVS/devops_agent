# AWS DevOps Agent Test Lab

A comprehensive test lab demonstrating AWS DevOps Agent capabilities through a Flask application deployed on ECS Fargate with RDS PostgreSQL, automated via Terragrunt and CodePipeline. This project exercises incident detection, anomaly detection, deployment correlation, on-demand SRE tasks, runbook execution, and report generation.

## Prerequisites

| Tool       | Version    | Install                      |
|------------|------------|------------------------------|
| terraform  | >= 1.7.0   | `brew install terraform`     |
| terragrunt | >= 0.55.0  | `brew install terragrunt`    |
| awscli     | >= 2.x     | `brew install awscli`        |
| docker     | >= 24      | https://docs.docker.com      |
| jq         | any        | `brew install jq`            |

## One-Time Setup

1. **Configure AWS credentials**
   ```bash
   aws configure
   # Enter your AWS Access Key ID and Secret Access Key
   ```

2. **Fork/clone this repository**
   ```bash
   git clone <your-repo-url>
   cd aws_devops_agent
   ```

3. **Set environment variables**
   ```bash
   export TF_VAR_db_password="YourStrongPassword123!"
   export TF_VAR_github_owner="your-github-username"
   export TF_VAR_github_repo="your-repo-name"
   export TF_VAR_alert_email="your-email@example.com"
   export AWS_REGION="us-east-1"
   export PROJECT="devops-agent-lab"
   ```

## Deploy

```bash
# Set all secrets and config via env vars — NEVER in code
export TF_VAR_db_password="StrongPass123!"
export TF_VAR_github_owner="your-github-org"
export TF_VAR_github_repo="your-repo-name"
export TF_VAR_alert_email="you@example.com"
export AWS_REGION="us-east-1"
export PROJECT="devops-agent-lab"

# 1. Independent base resources
cd infra/live/vpc && terragrunt apply && cd -
cd infra/live/ecr && terragrunt apply && cd -

# 2. Create SNS topic first (ecs module needs sns_topic_arn for alarms)
cd infra/live/devops-agent && \
  terragrunt apply --target=aws_sns_topic.devops_alerts && cd -

# 3. Build and push initial image (ECS task def needs a resolvable image)
ECR_URL=$(cd infra/live/ecr && terragrunt output -raw repository_url && cd -)
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL
docker build -t $ECR_URL:latest ./app
docker push $ECR_URL:latest

# 4. ECS (needs vpc, ecr, sns_topic_arn)
cd infra/live/ecs && terragrunt apply && cd -

# 5. RDS (needs vpc, ecs sg_id) — takes ~5 minutes
cd infra/live/rds && terragrunt apply && cd -

# 6. CI/CD pipeline (needs ecr, ecs)
cd infra/live/cicd && terragrunt apply && cd -

# 7. DevOps Agent full setup (needs ecs, rds, cicd outputs)
cd infra/live/devops-agent && terragrunt apply && cd -

# 8. MANUAL: Authorize GitHub connection
echo "Go to AWS Console → Developer Tools → Connections"
echo "Find '${PROJECT}-github' → click 'Update pending connection' → authorize GitHub"
read -p "Press ENTER after completing GitHub authorization: "

# 9. MANUAL: Confirm SNS subscription email
echo "Check inbox for $TF_VAR_alert_email — click 'Confirm subscription'"
read -p "Press ENTER after confirming SNS email subscription: "

# 10. Get task IP and smoke-test
CLUSTER="${PROJECT}-cluster"
TASK_ARN=$(aws ecs list-tasks --cluster $CLUSTER --query 'taskArns[0]' --output text)
ENI_ID=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK_ARN \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text)
TASK_IP=$(aws ec2 describe-network-interfaces --network-interface-ids $ENI_ID \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)

echo "Task IP: $TASK_IP"
curl -s http://$TASK_IP:8080/health
echo ""
echo "Deployment complete. Export TASK_IP=$TASK_IP before running scenario scripts."
```

## Test Scenarios

| Script                | What It Breaks                          | DevOps Agent Feature Tested                    |
|-----------------------|-----------------------------------------|------------------------------------------------|
| `01_db_failure.sh`    | Revokes ECS→RDS SG rule                 | Incident detection + config change correlation |
| `02_high_cpu.sh`      | Saturates CPU for 30s                   | Anomaly detection + on-demand report generation |
| `03_bad_deploy.sh`    | Pushes a crash-on-start image           | Deployment failure correlation + rollback      |
| `04_memory_pressure.sh`| Allocates 300MB in 512MB task          | Proactive insight + rightsizing recommendation  |
| `05_restore.sh`       | Restores all of the above               | Post-incident summary + preventive advice      |

**Running scenarios:**
```bash
# Make scripts executable
chmod +x scenarios/*.sh

# Set TASK_IP from deployment output, then:
export TASK_IP="<public-ip-from-deployment>"

# Run any scenario
./scenarios/01_db_failure.sh
# Follow on-screen instructions and chat prompts

# Restore environment
./scenarios/05_restore.sh
```

## DevOps Agent Chat Prompts to Try

1. "Why is my ECS service returning health check failures?"
2. "What infrastructure changes happened in the last 30 minutes?"
3. "Create a custom chart of ECS CPU and memory for the last 2 hours"
4. "Generate a post-incident report and share it"
5. "What was the last stable deployment before the service broke?"
6. "Roll back my ECS service to the previous task definition"
7. "What is the optimal memory configuration for this task based on usage data?"
8. "Is this CPU spike a real incident or a known anomaly?"
9. "What can we do to prevent this class of incident from happening again?"
10. "Is the service fully healthy now? Summarize everything that happened today."

## Destroy

```bash
# Destroy in reverse dependency order
cd infra/live/devops-agent && terragrunt destroy && cd -
cd infra/live/cicd         && terragrunt destroy && cd -
cd infra/live/rds          && terragrunt destroy && cd -
cd infra/live/ecs          && terragrunt destroy && cd -
cd infra/live/ecr          && terragrunt destroy && cd -
cd infra/live/vpc          && terragrunt destroy && cd -

# Remove Terragrunt remote state backend (Terraform does not manage these)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rb s3://devops-agent-lab-tfstate-$ACCOUNT_ID --force
aws dynamodb delete-table --table-name devops-agent-lab-tflock --region us-east-1
echo "All resources destroyed."
```

## Cost Estimate (24-hour test run)

| Resource                         | Cost                              |
|----------------------------------|-----------------------------------|
| ECS Fargate (0.25vCPU / 0.5GB)   | ~$0.24                            |
| RDS db.t3.micro                  | ~$0.00 (within 750hr free tier)   |
| CodeBuild (< 5 min builds)       | ~$0.00 (within 100min free tier)  |
| DevOps Guru (ECS + RDS, 1 day)   | ~$0.01–$0.10                     |
| CloudWatch / SNS / S3 / misc     | ~$0.00–$0.05                     |
| **TOTAL**                        | **< $0.50 for a full test day**   |

---

**Target:** AWS Free Tier  
**Features Exercised:** Incident detection, anomaly detection, deployment correlation, on-demand SRE tasks, runbook execution, report generation  
*Last updated: 2026-04-02*
