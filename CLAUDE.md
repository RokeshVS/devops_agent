# CLAUDE.md
# AWS DevOps Agent — Test Lab
# Flask → Docker → Terragrunt → ECS Fargate + RDS + CodePipeline + AWS DevOps Agent

You are an AWS DevOps engineer. Build this project top-to-bottom, completing each phase
before starting the next. Never hardcode secrets. Never create NAT Gateways. Ask only if
a dependency is truly ambiguous — otherwise proceed autonomously.

---

## FREE TIER GUARDRAILS — CHECK BEFORE EVERY RESOURCE

| Resource          | Config                                      | Why                        |
|-------------------|---------------------------------------------|----------------------------|
| RDS               | db.t3.micro, postgres 16, 20 GB gp2, no MAZ | 750 hr/month free          |
| ECS Fargate task  | 0.25 vCPU / 0.5 GB, desired_count = 1       | ~$0.01/hr — keep minimal   |
| NAT Gateway       | DO NOT CREATE                               | $0.045/hr — use IGW only   |
| CloudWatch Logs   | retention_in_days = 3 on every log group    | 5 GB free then charged     |
| CodeBuild         | BUILD_GENERAL1_SMALL                        | 100 free build-min/month   |
| DevOps Guru       | Scope to stack tags only, not all resources | Charged per resource/month |
| SNS               | 1 topic, email protocol                     | 1000 notifications free    |

---

## PHASE 0 — Directory Scaffold

Create this tree before writing any file:

```
.
├── CLAUDE.md
├── README.md
├── buildspec.yml
├── .devcontainer/
│   └── devcontainer.json
├── app/
│   ├── main.py
│   ├── requirements.txt
│   └── Dockerfile
├── runbooks/
│   ├── restart-ecs-task.ssm.yml
│   └── scale-ecs-service.ssm.yml
├── scenarios/
│   ├── 01_db_failure.sh
│   ├── 02_high_cpu.sh
│   ├── 03_bad_deploy.sh
│   ├── 04_memory_pressure.sh
│   └── 05_restore.sh
└── infra/
    ├── terragrunt.hcl
    ├── modules/
    │   ├── vpc/          → main.tf, variables.tf, outputs.tf
    │   ├── ecr/          → main.tf, variables.tf, outputs.tf
    │   ├── rds/          → main.tf, variables.tf, outputs.tf
    │   ├── ecs/          → main.tf, variables.tf, outputs.tf
    │   ├── cicd/         → main.tf, variables.tf, outputs.tf
    │   └── devops-agent/ → main.tf, variables.tf, outputs.tf
    └── live/
        ├── terragrunt.hcl
        ├── vpc/          → terragrunt.hcl
        ├── ecr/          → terragrunt.hcl
        ├── rds/          → terragrunt.hcl
        ├── ecs/          → terragrunt.hcl
        ├── cicd/         → terragrunt.hcl
        └── devops-agent/ → terragrunt.hcl
```

---

## PHASE 1 — Flask Application

### app/main.py

Flask app backed by PostgreSQL via psycopg2. Read ALL config from environment
variables. Crash on startup with a descriptive error if required vars are missing.

Endpoints:

| Method | Path               | Behaviour                                                        |
|--------|--------------------|------------------------------------------------------------------|
| GET    | /health            | DB ping → `{"status":"ok","db":"connected"}` or 500 on failure  |
| GET    | /items             | List all rows in `items` table                                   |
| POST   | /items             | `{"name":"..."}` → insert row, return created item              |
| GET    | /stress/cpu        | Burn CPU for 10 seconds (triggers CPU alarm in scenario 2)       |
| GET    | /stress/memory     | Allocate 300 MB in-process (triggers memory alarm in scenario 4) |
| GET    | /stress/slow-query | Run `SELECT pg_sleep(15)` (triggers DB latency alarm)            |

On startup: auto-create `items` table if not present.

Required env vars: `DB_HOST`, `DB_PORT` (default 5432), `DB_NAME`, `DB_USER`,
`DB_PASSWORD`, `APP_PORT` (default 8080).

### app/requirements.txt

```
flask==3.0.3
psycopg2-binary==2.9.9
gunicorn==22.0.0
```

### app/Dockerfile

Multi-stage build:
- Stage 1 `builder`: python:3.12-slim — install deps to /install
- Stage 2 `runtime`: python:3.12-slim — copy /install + main.py, create non-root
  user appuser (UID 1001), EXPOSE 8080
- CMD: `gunicorn --bind 0.0.0.0:8080 --workers 2 main:app`
- Final image must be < 200 MB

---

## PHASE 2 — SSM Runbooks

### runbooks/restart-ecs-task.ssm.yml

SSM Automation document (schemaVersion: "0.3") that:
- Parameters: `ClusterName` (String), `ServiceName` (String), `Region` (String)
- Step 1 `ForceNewDeployment`: aws:executeAwsApi
  Service: ecs, Api: UpdateService
  Parameters: cluster={{ClusterName}}, service={{ServiceName}}, forceNewDeployment=true
- Step 2 `WaitForStable`: aws:waitForAwsResourceProperty
  Service: ecs, Api: DescribeServices
  PropertySelector: services[0].deployments[0].rolloutState
  DesiredValues: ["COMPLETED"]
  Timeout: 300
- Outputs: the new task ARN

This runbook is referenced by the DevOps Agent for automated incident remediation.
It is registered as an SSM Document in the devops-agent module.

### runbooks/scale-ecs-service.ssm.yml

SSM Automation document that:
- Parameters: `ClusterName`, `ServiceName`, `DesiredCount` (default "1"), `Region`
- Step 1 `UpdateDesiredCount`: aws:executeAwsApi → ecs:UpdateService
- Step 2 `WaitForStable`: same as above
- Outputs: updated service ARN

---

## PHASE 3 — Terragrunt Root

### infra/terragrunt.hcl

Single source of truth:
- S3 remote state bucket: `${local.project}-tfstate-${local.account_id}`
- DynamoDB lock table: `${local.project}-tflock`
- State key per module: `${path_relative_to_include()}/terraform.tfstate`
  → Each module gets its own independent state file
- Provider constraint: `aws ~> 5.0`, Terraform: `>= 1.7.0`

```hcl
locals {
  project    = "devops-agent-lab"
  region     = "us-east-1"
  account_id = get_aws_account_id()
}
```

### infra/live/terragrunt.hcl

Inherits root via find_in_parent_folders(). Sets:
```hcl
locals {
  region      = "us-east-1"
  environment = "dev"
  project     = "devops-agent-lab"
}
```

---

## PHASE 4 — Terraform Modules

Every module is fully self-contained. No module references terraform_remote_state.
Cross-module values flow only through dependency{} blocks in the live layer.
Tag every resource: `Project = var.project`, `Environment = var.environment`.
First line of every .tf file must be a comment: `# Creates: <what this file creates>`

---

### Module: vpc

Resources:
- `aws_vpc` CIDR 10.0.0.0/16, enable_dns_hostnames = true
- 2× public subnets 10.0.1.0/24, 10.0.2.0/24 across 2 AZs — ECS runs here
- 2× private subnets 10.0.10.0/24, 10.0.20.0/24 — RDS only, no internet route
- `aws_internet_gateway` + public route table with default route to IGW
- No NAT gateway under any circumstances

Variables: `project`, `environment`
Outputs: `vpc_id`, `public_subnet_ids` (list), `private_subnet_ids` (list)

---

### Module: ecr

Resources:
- `aws_ecr_repository` name `${project}-app`, MUTABLE, force_delete = true
- `aws_ecr_lifecycle_policy` keep last 3 images only

Variables: `project`, `environment`
Outputs: `repository_url`, `repository_name`, `repository_arn`

---

### Module: rds

Resources:
- `aws_db_subnet_group` using private subnets
- `aws_security_group` rds_sg: ingress 5432 from var.ecs_sg_id only, egress all
- `aws_db_instance`:
  - engine = "postgres", engine_version = "16.3"
  - instance_class = "db.t3.micro", allocated_storage = 20, storage_type = "gp2"
  - multi_az = false, publicly_accessible = false
  - skip_final_snapshot = true, deletion_protection = false
  - backup_retention_period = 0, apply_immediately = true
  - enabled_cloudwatch_logs_exports = ["postgresql"] — DevOps Agent reads these logs
- `aws_ssm_parameter` /${project}/${environment}/db_password, SecureString

Variables: `project`, `environment`, `vpc_id`, `private_subnet_ids`, `ecs_sg_id`,
           `db_name`, `db_username`, `db_password`
Outputs: `db_endpoint`, `db_port`, `db_name`, `db_username`, `db_password_ssm_arn`,
         `db_instance_id`, `rds_sg_id`

---

### Module: ecs

Resources:

1. `aws_security_group` ecs_sg:
   Ingress 8080 from 0.0.0.0/0. Egress all (ECR pull, RDS, SSM, CloudWatch).

2. `aws_iam_role` ecs_task_execution_role:
   Managed: AmazonECSTaskExecutionRolePolicy.
   Inline: ssm:GetParameters on db_password SSM param ARN.
   Inline: logs:CreateLogGroup.

3. `aws_iam_role` ecs_task_role:
   Inline: cloudwatch:PutMetricData (for custom health metrics).
   Inline: logs:CreateLogStream, logs:PutLogEvents on /ecs/${project}.

4. `aws_cloudwatch_log_group` /ecs/${project}, retention_in_days = 3

5. `aws_ecs_cluster` ${project}-cluster, Container Insights DISABLED (costs money)

6. `aws_ecs_task_definition`:
   FARGATE, awsvpc, cpu = "256", memory = "512".
   Container name MUST be "app" — CodePipeline imagedefinitions.json requires this.
   Image: ${ecr_repository_url}:latest.
   Port 8080. Env: DB_HOST, DB_PORT, DB_NAME, DB_USER, APP_PORT.
   Secret: DB_PASSWORD from SSM param ARN.
   Log driver: awslogs → /ecs/${project}.

7. `aws_ecs_service`:
   FARGATE, desired_count = 1, assign_public_ip = true.
   minimum_healthy_percent = 0, maximum_percent = 100, force_new_deployment = true.

8. CloudWatch Alarms (DevOps Agent uses these to detect and correlate incidents):

   `aws_cloudwatch_metric_alarm` ecs_cpu_high:
   namespace=AWS/ECS, metric=CPUUtilization, dimensions ClusterName+ServiceName.
   threshold=70, period=60, evaluation_periods=2, statistic=Average.
   comparison=GreaterThanThreshold, alarm_actions=[var.sns_topic_arn].

   `aws_cloudwatch_metric_alarm` ecs_memory_high:
   metric=MemoryUtilization, threshold=80, same config as above.

   `aws_cloudwatch_metric_alarm` health_endpoint_errors:
   namespace=App/HealthCheck, metric=ErrorCount (from log metric filter).
   threshold=1, period=60, evaluation_periods=1.
   treat_missing_data="notBreaching", alarm_actions=[var.sns_topic_arn].

Variables: `project`, `environment`, `vpc_id`, `public_subnet_ids`,
           `ecr_repository_url`, `db_endpoint`, `db_port`, `db_name`,
           `db_username`, `db_password_ssm_arn`, `sns_topic_arn`
Outputs: `ecs_cluster_name`, `ecs_cluster_arn`, `ecs_service_name`, `ecs_sg_id`,
         `task_definition_arn`, `task_execution_role_arn`, `task_role_arn`

---

### Module: cicd

GitHub → CodeBuild (build + push to ECR) → ECS (rolling deploy).

Resources:

1. `aws_s3_bucket` artifacts:
   Name: ${project}-cicd-artifacts-${data.aws_caller_identity.current.account_id}.
   force_destroy = true. Block all public access.

2. `aws_iam_role` codepipeline_role:
   s3 read/write on artifacts bucket. codebuild:StartBuild, BatchGetBuilds.
   ecs: RegisterTaskDefinition, DescribeServices, UpdateService.
   iam:PassRole on task execution role ARN.

3. `aws_iam_role` codebuild_role:
   ecr: GetAuthorizationToken, BatchCheckLayerAvailability, PutImage,
        InitiateLayerUpload, UploadLayerPart, CompleteLayerUpload.
   logs: CreateLogGroup, CreateLogStream, PutLogEvents.
   s3: GetObject, PutObject on artifacts bucket.
   ecs: RegisterTaskDefinition.

4. `aws_cloudwatch_log_group` /codebuild/${project}, retention = 3 days

5. `aws_codebuild_project`:
   BUILD_GENERAL1_SMALL, aws/codebuild/standard:7.0, privileged_mode = true.
   Env vars: ECR_REPO_URL, AWS_DEFAULT_REGION, ECS_CLUSTER, ECS_SERVICE.
   Buildspec type = CODEPIPELINE (reads buildspec.yml from repo root).

6. `aws_codeconnections_connection`:
   provider_type = "GitHub", name = "${project}-github".
   NOTE: Status will be PENDING after apply. User must authorize in AWS Console.

7. `aws_codepipeline`:
   Stage Source: GitHub V2 via codeconnections, output artifact "SourceOutput".
   Stage Build: CodeBuild project, input SourceOutput, output "BuildOutput".
   Stage Deploy: ECS action provider, input BuildOutput (imagedefinitions.json),
                 cluster = var.ecs_cluster_name, service = var.ecs_service_name.

Variables: `project`, `environment`, `ecr_repository_url`, `ecs_cluster_name`,
           `ecs_service_name`, `task_execution_role_arn`, `github_owner`,
           `github_repo`, `github_branch` (default "main")
Outputs: `pipeline_name`, `pipeline_arn`, `codebuild_project_name`,
         `github_connection_arn`

---

### Module: devops-agent

Sets up AWS DevOps Guru (the service powering AWS DevOps Agent) and all supporting
observability infrastructure.

Resources:

1. `aws_sns_topic` devops_alerts:
   Name: ${project}-devops-alerts.
   Used by both CloudWatch alarms (in ecs module) and DevOps Guru notifications.

2. `aws_sns_topic_subscription` email_alert:
   protocol = "email", endpoint = var.alert_email.
   NOTE: User must confirm the subscription email before alerts work.

3. `aws_devopsguru_resource_collection`:
   Scope to tagged resources only — keeps monitoring cost bounded to this stack.
   ```hcl
   tags {
     app_boundary_key = "Project"
     tag_values       = [var.project]
   }
   ```

4. `aws_devopsguru_notification_channel`:
   sns { topic_arn = aws_sns_topic.devops_alerts.arn }

5. `aws_devopsguru_service_integration`:
   ops_center { opt_in_status = "ENABLED" }
   This creates OpsCenter OpsItems per insight so incidents can be tracked
   and assigned as work items — directly testable in the console.

6. `aws_ssm_document` restart_ecs_task:
   name = "${project}-restart-ecs-task", document_type = "Automation".
   content = file("${path.module}/../../runbooks/restart-ecs-task.ssm.yml").

7. `aws_ssm_document` scale_ecs_service:
   name = "${project}-scale-ecs-service", document_type = "Automation".
   content = file("${path.module}/../../runbooks/scale-ecs-service.ssm.yml").

8. `aws_cloudwatch_log_metric_filter` error_count:
   Log group: /ecs/${project}. Filter pattern: "[ERROR]".
   Metric: namespace=App/HealthCheck, name=ErrorCount, value=1.
   This feeds the health_endpoint_errors alarm in the ecs module.

9. `aws_cloudwatch_dashboard` overview:
   Name: ${project}-overview. Six widgets:
   a. ECS CPUUtilization line chart (3 hr window)
   b. ECS MemoryUtilization line chart
   c. RDS DatabaseConnections
   d. RDS FreeStorageSpace
   e. App/HealthCheck ErrorCount (from metric filter above)
   f. Text widget: direct link to DevOps Guru Insights console

Variables: `project`, `environment`, `ecs_cluster_name`, `ecs_service_name`,
           `db_instance_id`, `alert_email`, `pipeline_name`
Outputs: `sns_topic_arn`, `dashboard_url`, `restart_runbook_arn`,
         `scale_runbook_arn`, `devops_guru_collection_id`

---

## PHASE 5 — Live Layer Wiring

Each infra/live/<module>/terragrunt.hcl must include root via find_in_parent_folders()
and declare dependency{} blocks for cross-module data. Use mock_outputs on deps that
have circular potential.

Dependency chain:
```
vpc           → no deps
ecr           → no deps
devops-agent  → first pass (SNS topic only): no deps
ecs           → vpc, ecr, devops-agent (sns_topic_arn)
rds           → vpc, ecs (ecs_sg_id)
cicd          → ecr, ecs
devops-agent  → full apply: ecs, rds, cicd
```

Mock outputs to break circular deps:
```hcl
# In live/ecs/terragrunt.hcl, devops-agent dep:
mock_outputs = { sns_topic_arn = "arn:aws:sns:us-east-1:000000000000:mock" }
mock_outputs_allowed_terraform_commands = ["validate", "plan"]

# In live/rds/terragrunt.hcl, ecs dep:
mock_outputs = { ecs_sg_id = "sg-00000000" }
mock_outputs_allowed_terraform_commands = ["validate", "plan"]
```

Secrets via env vars (never in code):
```hcl
# live/rds/terragrunt.hcl
inputs = { db_password = get_env("TF_VAR_db_password") }

# live/cicd/terragrunt.hcl
inputs = {
  github_owner = get_env("TF_VAR_github_owner")
  github_repo  = get_env("TF_VAR_github_repo")
}

# live/devops-agent/terragrunt.hcl
inputs = { alert_email = get_env("TF_VAR_alert_email") }
```

---

## PHASE 6 — buildspec.yml (project root)

```yaml
version: 0.2

phases:
  pre_build:
    commands:
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REPO_URL
      - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-7)
  build:
    commands:
      - docker build -t $ECR_REPO_URL:$IMAGE_TAG -t $ECR_REPO_URL:latest ./app
  post_build:
    commands:
      - docker push $ECR_REPO_URL:$IMAGE_TAG
      - docker push $ECR_REPO_URL:latest
      - printf '[{"name":"app","imageUri":"%s"}]' $ECR_REPO_URL:$IMAGE_TAG > imagedefinitions.json

artifacts:
  files:
    - imagedefinitions.json
```

---

## PHASE 7 — Test Scenarios

Each scenario script must:
- Start with `set -euo pipefail`
- Print a header describing what the scenario tests
- Print what to observe in the AWS DevOps Agent / DevOps Guru console
- Print exact chat prompts to try in the DevOps Agent chat interface
- Point to 05_restore.sh for cleanup

---

### scenarios/01_db_failure.sh — Database Connectivity Failure

What this tests: DevOps Agent detects a DB connectivity incident, correlates the
alarm with the CloudTrail security group change, identifies root cause, and suggests
remediation via the restart runbook.

Script steps:
1. Read ECS_SG_ID and RDS_SG_ID from AWS CLI (use describe-security-groups filtering
   by tag Project=devops-agent-lab)
2. Revoke the ECS → RDS ingress rule:
   `aws ec2 revoke-security-group-ingress --group-id $RDS_SG_ID --protocol tcp --port 5432 --source-group $ECS_SG_ID`
3. Sleep 30 seconds
4. Loop: call `curl -sf http://$TASK_IP:8080/health` 10 times, print each result
5. Echo:
   "OBSERVE: DevOps Guru console → Insights → new Reactive Insight should appear"
   "OBSERVE: OpsCenter should have a new OpsItem for this incident"
   "TRY IN DEVOPS AGENT CHAT:"
   "  1. 'Why is my ECS service returning health check failures?'"
   "  2. 'What infrastructure changes happened in the last 30 minutes?'"
   "  3. 'Show me the correlation between the CloudWatch alarm and recent AWS events'"
   "  4. 'Run the restart-ecs-task runbook for my service'"
6. Echo: "Run ./scenarios/05_restore.sh when done"

---

### scenarios/02_high_cpu.sh — CPU Spike

What this tests: Anomaly detection (Proactive Insight), on-demand report generation,
and chat-based SRE analysis.

Script steps:
1. Get TASK_IP via describe-tasks + describe-network-interfaces
2. Run 5 parallel curl calls to /stress/cpu in background, repeat 3 rounds:
   `for i in $(seq 5); do curl -s http://$TASK_IP:8080/stress/cpu & done; wait`
3. Between rounds, poll the CPU alarm state:
   `aws cloudwatch describe-alarms --alarm-names devops-agent-lab-ecs-cpu-high`
4. When alarm enters ALARM state, echo:
   "OBSERVE: CloudWatch Dashboard devops-agent-lab-overview — CPU widget spiking"
   "TRY IN DEVOPS AGENT CHAT:"
   "  1. 'My ECS CPU is spiking. Is this a real incident or an anomaly?'"
   "  2. 'What is the blast radius if the CPU stays at this level?'"
   "  3. 'Create a custom chart of ECS CPU and memory for the last 2 hours'"
   "  4. 'Generate a summary report of application health and share it'"
   "  5. 'Should I scale horizontally or vertically for this workload?'"

---

### scenarios/03_bad_deploy.sh — Broken Deployment

What this tests: Deployment failure correlation across CodePipeline + ECS, rollback
suggestion via chat, and runbook execution from the Agent.

Script steps:
1. Save the current task definition ARN:
   `PREVIOUS_TASK_DEF=$(aws ecs describe-services ... --query services[0].taskDefinition)`
2. Create a broken image — overwrite CMD in Dockerfile temporarily:
   `sed -i 's|CMD \[.*\]|CMD ["python", "-c", "import sys; sys.exit(1)"]|' app/Dockerfile`
3. Build and push broken image with tag "broken-$(date +%s)":
   `docker build -t $ECR_URL:broken-$(date +%s) ./app && docker push ...`
4. Force ECS to use the broken image via update-service with new task definition
   (register a new task def with the broken image tag)
5. Wait 90 seconds, then poll ECS service events:
   `aws ecs describe-services --query services[0].events[0:5]`
6. Echo:
   "OBSERVE: ECS service shows 0/1 running tasks"
   "OBSERVE: CodePipeline may also show failure if triggered via git push"
   "TRY IN DEVOPS AGENT CHAT:"
   "  1. 'My latest deployment broke the service. What failed?'"
   "  2. 'What was the last stable task definition before this deployment?'"
   "  3. 'Roll back my ECS service to the previous task definition'"
   "  4. 'Correlate the deployment timeline with the service health drop'"
7. Restore: re-register previous task def and force new deployment with $PREVIOUS_TASK_DEF
8. Restore Dockerfile: `git checkout -- app/Dockerfile`

---

### scenarios/04_memory_pressure.sh — Memory Pressure

What this tests: Proactive insight generation (warning before OOM), rightsizing
recommendation, and observability-driven SRE advice.

Script steps:
1. Get TASK_IP
2. Call /stress/memory once (allocates 300 MB in a 512 MB task)
3. Poll MemoryUtilization every 15 seconds for 3 minutes:
   `aws cloudwatch get-metric-statistics --namespace AWS/ECS --metric-name MemoryUtilization ...`
4. Print current % each poll cycle
5. When alarm state is ALARM, echo:
   "OBSERVE: MemoryUtilization alarm firing in CloudWatch"
   "TRY IN DEVOPS AGENT CHAT:"
   "  1. 'My ECS task is consuming excessive memory. Should I scale up or optimize?'"
   "  2. 'What is the optimal memory configuration for this task based on usage data?'"
   "  3. 'Show me a memory utilization trend for the last 24 hours'"
   "  4. 'Generate an incident report for the memory event that just occurred'"
6. Echo: "Run ./scenarios/05_restore.sh to force-restart the container"

---

### scenarios/05_restore.sh — Full Environment Restore

Restores environment to known-good state after any scenario.

Script steps:
1. Re-authorize RDS SG ingress from ECS SG (fixes scenario 01):
   `aws ec2 authorize-security-group-ingress --group-id $RDS_SG_ID --protocol tcp --port 5432 --source-group $ECS_SG_ID`
   (Use --cli-input-json if rule already exists — catch the duplicate error gracefully)
2. Force new ECS deployment (fixes scenarios 02, 03, 04):
   `aws ecs update-service --cluster devops-agent-lab-cluster --service devops-agent-lab-dev-svc --force-new-deployment`
3. Wait for stability:
   `aws ecs wait services-stable --cluster devops-agent-lab-cluster --services devops-agent-lab-dev-svc`
4. Curl /health and print result
5. Echo:
   "Environment restored."
   "DevOps Guru insights should close automatically within 5-10 minutes"
   "TRY IN DEVOPS AGENT CHAT:"
   "  'Is the service fully healthy now? Give me a post-incident summary'"
   "  'What can we do to prevent this class of incident from happening again?'"

---

## PHASE 8 — Deployment Order

The agent executes these commands during initial deploy:

```bash
# Set all secrets and config via env vars — NEVER in code
export TF_VAR_db_password="StrongPass123!"      # replace with real strong password
export TF_VAR_github_owner="your-github-org"
export TF_VAR_github_repo="your-repo-name"
export TF_VAR_alert_email="you@example.com"
export AWS_REGION="us-east-1"
export PROJECT="devops-agent-lab"

# 1. Independent base resources
cd infra/live/vpc && terragrunt apply  && cd -
cd infra/live/ecr && terragrunt apply  && cd -

# 2. Create SNS topic first (ecs module needs sns_topic_arn for alarms)
cd infra/live/devops-agent && \
  terragrunt apply  --target=aws_sns_topic.devops_alerts && cd -

# 3. Build and push initial image (ECS task def needs a resolvable image)
ECR_URL=$(cd infra/live/ecr && terragrunt output -raw repository_url)
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL
docker build -t $ECR_URL:latest ./app
docker push $ECR_URL:latest

# 4. ECS (needs vpc, ecr, sns_topic_arn)
cd infra/live/ecs && terragrunt apply  && cd -

# 5. RDS (needs vpc, ecs sg_id) — takes ~5 minutes
cd infra/live/rds && terragrunt apply  && cd -

# 6. CI/CD pipeline (needs ecr, ecs)
cd infra/live/cicd && terragrunt apply  && cd -

# 7. DevOps Agent full setup (needs ecs, rds, cicd outputs)
cd infra/live/devops-agent && terragrunt apply  && cd -

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

---

## PHASE 9 — Teardown

```bash
# Destroy in reverse dependency order
cd infra/live/devops-agent && terragrunt destroy  && cd -
cd infra/live/cicd         && terragrunt destroy  && cd -
cd infra/live/rds          && terragrunt destroy  && cd -
cd infra/live/ecs          && terragrunt destroy  && cd -
cd infra/live/ecr          && terragrunt destroy  && cd -
cd infra/live/vpc          && terragrunt destroy  && cd -

# Remove Terragrunt remote state backend (Terraform does not manage these)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rb s3://devops-agent-lab-tfstate-$ACCOUNT_ID --force
aws dynamodb delete-table --table-name devops-agent-lab-tflock --region us-east-1
echo "All resources destroyed."
```

---

## PHASE 10 — README.md

Generate README.md at the project root containing exactly these sections, no more:

1. One paragraph: what this project is, what AWS DevOps Agent features it exercises.

2. Prerequisites table:
   Tool | Version | Install
   terraform | >= 1.7.0 | brew install terraform
   terragrunt | >= 0.55 | brew install terragrunt
   awscli | >= 2.x | brew install awscli
   docker | >= 24 | docs.docker.com
   jq | any | brew install jq

3. One-time setup steps (numbered list, not table):
   - Configure AWS credentials: aws configure
   - Fork/clone the repo
   - Set env vars (TF_VAR_db_password, TF_VAR_github_owner, TF_VAR_github_repo, TF_VAR_alert_email)

4. Deploy commands (exact copy of Phase 8 code block)

5. Scenarios table:
   Script | What It Breaks | DevOps Agent Feature Tested
   01_db_failure.sh | Revokes ECS→RDS SG rule | Incident detection + config change correlation
   02_high_cpu.sh | Saturates CPU for 30s | Anomaly detection + on-demand report generation
   03_bad_deploy.sh | Pushes a crash-on-start image | Deployment failure correlation + rollback suggestion
   04_memory_pressure.sh | Allocates 300MB in 512MB task | Proactive insight + rightsizing recommendation
   05_restore.sh | Restores all of the above | Post-incident summary + preventive advice

6. DevOps Agent prompts to try (numbered, one per line, no sub-bullets):
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

7. Destroy commands (exact copy of Phase 9 code block)

8. Cost estimate table (rough 24-hour test run):
   Resource | Cost
   ECS Fargate (0.25vCPU / 0.5GB × 24h) | ~$0.24
   RDS db.t3.micro × 24h | ~$0.00 (within 750hr free tier)
   CodeBuild (< 5 min builds) | ~$0.00 (within 100min free tier)
   DevOps Guru (ECS + RDS, 1 day) | ~$0.01–$0.10
   CloudWatch / SNS / S3 / misc | ~$0.00–$0.05
   TOTAL | < $0.50 for a full test day

---

## Coding Standards

- HCL: every .tf file starts with `# Creates: <description>`
- Python: PEP-8, all DB calls in try/except, log all errors to stdout
- Bash: `set -euo pipefail` at the top of every scenario script
- No hardcoded secrets anywhere — TF_VAR_* env vars + SSM only
- All resource names: `${project}-${environment}-<resource>` or `${project}-<resource>`
- State isolation: 6 modules = 6 separate .tfstate files in S3 — verify after deploy

---

*Target: AWS Free Tier | DevOps Agent features: incident detection, anomaly detection,
deployment correlation, on-demand SRE tasks, runbook execution, report generation*
*Last updated: 2026-04-02*