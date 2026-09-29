# URL Shortener with Click Analytics on AWS ECS

A URL shortener that records every click and reports on it, running as three services on Amazon ECS Fargate, provisioned with Terraform and deployed through GitHub Actions.
The API is released with blue/green deployments through CodeDeploy, and everything runs in private subnets that reach AWS through VPC endpoints, with no NAT gateway and no route to the internet.
The application code was provided by CoderCo. The containerisation, infrastructure, pipelines and the changes listed under Design Choices are mine.

### Project Overview

- **Terraform** provisions all AWS infrastructure, split into a bootstrap stack (state bucket, ECR, pipeline roles) and the main stack
- **Amazon ECS Fargate** runs three services in one cluster: a Python API, a Go worker and a Go dashboard
- **Blue/green deployments** through CodeDeploy for the API, with traffic shifted 10% a minute and automatic rollback
- **Rolling deployments with a circuit breaker** for the worker and dashboard, rolling back automatically on failure
- **Application Load Balancer** terminates HTTPS and routes by hostname to the API and dashboard
- **AWS WAF** filters traffic before it reaches the ALB: rate limiting plus AWS managed rule groups
- **Amazon RDS PostgreSQL** stores URLs and click analytics
- **Amazon ElastiCache Redis** caches short code lookups so redirects skip the database
- **Amazon SQS** queues click events between the API and the worker, with a dead-letter queue for failed messages
- **VPC endpoints** give private access to ECR, S3, CloudWatch Logs, SQS and Secrets Manager without a NAT gateway
- **AWS Secrets Manager** holds the database connection string, injected into containers at startup
- **GitHub OIDC** gives the pipelines short-lived AWS credentials, with separate least-privilege roles for releases and infrastructure
- **Multi-stage Docker builds**, with distroless images for the Go services
- **Grype, tfsec, tflint and pre-commit** scan images and Terraform before anything reaches AWS

## Architecture Diagram

<!-- TODO: architecture diagram -->

## Project Structure

```text
url-shortener-ecs/
├── .github/
│   ├── deploy/
│   │   └── appspec-api.yaml
│   └── workflows/
│       ├── build-deploy.yaml
│       ├── terraform-plan.yaml
│       ├── terraform-deploy.yaml
│       └── terraform-destroy.yaml
├── app/                      # Python API (FastAPI)
│   ├── src/
│   ├── tests/
│   ├── Dockerfile
│   └── requirements.txt
├── services/
│   ├── worker/               # Go: reads click events from SQS, writes analytics to Postgres
│   └── dashboard/            # Go: analytics API
├── bootstrap/                # state bucket, ECR repos, GitHub OIDC roles
├── infra/
│   ├── modules/
│   │   ├── vpc/  security/  rds/  redis/  sqs/
│   │   └── acm/  alb/  waf/  ecs/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── localstack/
│   └── init-sqs.sh
├── docker-compose.yml
├── .pre-commit-config.yaml
└── README.md
```

## Design Choices

### RDS PostgreSQL over DynamoDB

The API can run on either, but the worker and dashboard are written against Postgres, and the dashboard queries the API's own `urls` table with sums, ordering and time ranges. With DynamoDB, the API would write to one database while the dashboard read from another. Postgres was the only option that worked for all three services without rewriting two of them. The cost is a database that bills while idle and takes around 10 minutes to create.

### VPC Endpoints Instead of a NAT Gateway

The private subnets have no route to the internet at all. Tasks reach AWS through interface endpoints for ECR, CloudWatch Logs, SQS and Secrets Manager, plus a free gateway endpoint for S3, where ECR stores image layers. If a container were compromised, it couldn't reach anything outside AWS. At this size it costs more than a single NAT gateway (five endpoints across two AZs), so this is a security choice, not a cost saving.

### Blue/Green for the API, Rolling for the Worker and Dashboard

CodeDeploy can only shift traffic on a listener's default action, not on host or path rules, so only one service per listener can use it. The API gets it, because redirects are the path users hit. The dashboard uses a rolling deploy with a circuit breaker. The worker has no load balancer at all, so blue/green doesn't apply to it. It rolls with a circuit breaker and checks its own health, since its distroless image has no curl.

### Host-Based Routing

The API has a catch-all `/{short_id}` route, so sending dashboard paths like `/top` on the same hostname would clash with short codes. The API is served on `go.` and the dashboard on `dashboard.`, both covered by one ACM certificate.

### Redis as a Redirect Cache

The provided API didn't use Redis. I added a cache in front of the short code lookup, because a short code always maps to the same URL. Redis is optional: if it's slow or down, the API falls back to Postgres after half a second instead of failing the redirect.

### SQS with a Dead-Letter Queue

The API publishes a click event and redirects straight away, and the worker writes the analytics in the background. Messages are only deleted after a successful write, so a crash never loses a click. After 5 failed attempts, a message moves to the dead-letter queue instead of retrying forever.

### Secrets Manager for the Database URL

Terraform generates the password and stores the full connection string as a secret. ECS injects it as an environment variable at startup, so it never appears in the repo, the task definition or the logs. The password does sit in Terraform state, which is why the state bucket is private, encrypted and versioned.

### Separate Roles for Releases and Infrastructure

The release pipeline can only push images and roll out task definitions. The Terraform pipeline can build the stack but has an explicit deny on editing either pipeline role, so it can't grant itself more access. Both authenticate with OIDC, so there are no stored AWS keys.

### Changes to the Provided App

- Implemented the worker's SQS polling and message deletion (the provided code was a stub)
- Added the Redis cache to the API
- Added a `-healthcheck` flag to the worker so ECS can check a container with no shell or curl
- Wrote all three Dockerfiles and added `go.sum` files

### Demo Trade-offs

Single-AZ RDS, one Redis node, one task per service, no deletion protection. These keep costs down for a stack I rebuild often. For production I'd run Multi-AZ RDS, a Redis replica, at least two tasks per service and CloudWatch alarms for rollback.

## Running the Application Locally

### Requirements

- Docker
- Docker Compose (v2)
- A free LocalStack account for the auth token (LocalStack stands in for SQS)

### Setup Environment Variables

Create a `.env` file in the project root:

```bash
touch .env
```

Add the following variable:

```
LOCALSTACK_AUTH_TOKEN=your-token
```

### Start the Application

From the project root, run:

```bash
docker compose up --build
```

The services will be available at:

```
API:        http://localhost:8080
Dashboard:  http://localhost:8081
```

Try it:

```bash
curl -X POST localhost:8080/shorten -H "Content-Type: application/json" -d '{"url":"https://example.com"}'
curl -i localhost:8080/<short_code>
curl localhost:8081/summary
```

### Stop the Application

```bash
docker compose down
```

## CI/CD Workflows

- **Build and Deploy**: builds all three images, scans them with Grype, pushes to ECR, then deploys the API through CodeDeploy and the worker and dashboard as rolling updates

<!-- TODO: screenshot -->

- **Terraform Plan**: runs on pull requests that change `infra/`, with fmt, validate, tflint, tfsec and a plan

<!-- TODO: screenshot -->

- **Terraform Deploy**: applies the reviewed plan on merge to `main`

<!-- TODO: screenshot -->

- **Terraform Destroy**: manual, and only runs if you type "destroy"

<!-- TODO: screenshot -->

### Deployment Workflow

1. Open a pull request. Pre-commit hooks have already checked formatting, validity and secrets locally
2. If `infra/` changed, Terraform Plan runs, and the plan appears in the job summary for review
3. Merge to `main`. Infrastructure changes go through Terraform Deploy, and app changes go through Build and Deploy
4. Each image is built, scanned and pushed to ECR, tagged with the commit SHA
5. The pipeline takes the live task definition, swaps in the new image and registers it
6. **API:** CodeDeploy starts the new version beside the old one, shifts traffic 10% a minute, and keeps the old version for 5 minutes. A failure sends traffic straight back to the old version
7. **Worker and dashboard:** ECS replaces tasks one at a time. If new tasks fail their health checks, the circuit breaker rolls back to the last working version
8. A smoke test checks both `/healthz` endpoints through the real domain. A failed deploy or smoke test turns the pipeline red

## Screenshots

<!-- TODO: ECS services running, blue/green traffic shift in CodeDeploy, rollback, end-to-end curl -->