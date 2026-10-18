# URL Shortener with Click Analytics on AWS ECS

A URL shortener that tracks every click, running as three services on Amazon ECS Fargate. The infrastructure is built with Terraform and deployed through GitHub Actions, with blue/green releases for the API and no NAT gateway.
The application code was provided by CoderCo. The containerisation, infrastructure, pipelines and the changes listed below are mine.

### Project Overview

- **Terraform** provisions all AWS infrastructure
- **Amazon ECS Fargate** runs three services: a Python API, a Go worker and a Go dashboard
- **Blue/green deployments** through CodeDeploy for the API, with automatic rollback
- **Application Load Balancer** routes HTTPS traffic by hostname, with **AWS WAF** in front
- **Amazon RDS PostgreSQL** stores URLs and click analytics
- **Amazon ElastiCache Redis** caches redirects
- **Amazon SQS** carries click events from the API to the worker, with a dead-letter queue
- **VPC endpoints** give private access to AWS services without a NAT gateway
- **AWS Secrets Manager** holds the database connection string
- **GitHub OIDC** gives the pipelines AWS access with no long-lived keys
- **Multi-stage Docker builds**, scanned with Grype before deploy
- **A simple frontend page** for shortening links in the browser

## Architecture Diagram

![Architecture](screenshots/url-shortener-architecture.png)

## Project Structure

```text
url-shortener-ecs/
├── .github/workflows/     # build-deploy, terraform plan/deploy/destroy
├── app/                   # Python API and frontend page
├── services/
│   ├── worker/            # Go: SQS click events -> Postgres
│   └── dashboard/         # Go: analytics API
├── bootstrap/             # state bucket, ECR repos, GitHub OIDC roles
├── infra/                 # main stack, split into modules
├── docker-compose.yml
└── README.md
```

## Design Choices

### RDS PostgreSQL over DynamoDB

The worker and dashboard are written against Postgres and query the same tables as the API, so Postgres was the only option that worked for all three services without rewriting two of them. The trade-off is a database that costs money even when idle.

### VPC Endpoints Instead of a NAT Gateway

The private subnets have no route to the internet. Tasks reach AWS services through VPC endpoints instead. At this size that costs more than one NAT gateway, so it's a security choice rather than a saving.

### Blue/Green for the API, Rolling for the Rest

CodeDeploy can only shift traffic for one service per listener, so the API gets blue/green because it's what users hit. The worker and dashboard use rolling deploys with a circuit breaker that rolls back on failure.

### Subdomains of an Existing Domain

The API runs on `go.trackance.co.uk` and the dashboard on `dashboard.trackance.co.uk`. These are subdomains of a domain I already own from my previous project, which avoids paying for a new domain and hosted zone. Changing the `domain_name` variable would move it to a new domain.

### Viewing Click Analytics

The dashboard is a JSON API, so it has no home page. Analytics are available at:

- [`/summary`](https://dashboard.trackance.co.uk/summary): total URLs and clicks
- `/url/<short_code>`: stats for one link, e.g. `https://dashboard.trackance.co.uk/url/ab12cd34`

Clicks can also be viewed in CloudWatch Logs, where each service has its own log group and the worker logs every click it processes. The links only work while the stack is deployed.

### Changes to the Provided App

- Implemented the worker's SQS polling
- Added Redis caching to the API
- Added a health check to the worker
- Added a simple frontend page
- Wrote all three Dockerfiles

### Trade-offs

Single-AZ RDS, one Redis node and one task per service keep costs down. For production I'd run Multi-AZ RDS, at least two tasks per service and CloudWatch alarms for faster rollback.

## Running the Application Locally

### Requirements

- Docker and Docker Compose
- A free LocalStack auth token (LocalStack stands in for SQS)

### Setup Environment Variables

Create a `.env` file in the project root:

```
LOCALSTACK_AUTH_TOKEN=your-token
```

### Start the Application

```bash
docker compose up --build
```

- Frontend and API: http://localhost:8080
- Dashboard: http://localhost:8081/summary

### Stop the Application

```bash
docker compose down
```

## CI/CD Workflows

- **Build and Deploy**: tests, builds and scans the images, pushes to ECR, then deploys

<!-- screenshot -->

- **Terraform Plan**: runs on pull requests that change `infra/`

<!-- screenshot -->

- **Terraform Deploy**: applies infrastructure changes on merge to `main`

<!-- screenshot -->

- **Terraform Destroy**: manual teardown

<!-- screenshot -->

### Deployment Workflow

1. A pull request runs the tests, and the Terraform plan if `infra/` changed
2. Merging to `main` builds, scans and pushes the new images to ECR
3. **API:** CodeDeploy starts the new version beside the old one and shifts traffic 10% a minute. If the new version fails its health check, traffic stays on the old one and the deploy rolls back
4. **Worker and dashboard:** tasks are replaced one at a time, with automatic rollback on failure
5. A smoke test checks both services through the real domain

### Rollback Test

I deployed an API version with a failing health check. CodeDeploy sent it 0% of traffic, timed out after 60 minutes and rolled back automatically, while the live site returned 200 throughout.

<!-- rollback screenshots -->

## Screenshots

<!-- frontend, dashboard summary, ECS services running -->