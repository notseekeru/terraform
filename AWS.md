# AWS SAA-C03 Portfolio Architecture: 3-Tier Fault-Tolerant Web App (Free Tier Compliant)

This document outlines the architecture, configuration strategy, and file structure for building a production-ready, enterprise-grade 3-Tier Web Application on AWS. It is designed to fit **100% within the AWS Free Tier** ($0.00/month) while teaching the exact networking, compute, and database concepts required for the **AWS Certified Solutions Architect - Associate (SAA-C03)** exam.

---

## 1. High-Level Architecture Diagram

```
                                [ Internet User ]
                                        │
                                        ▼ CNAME (DNS handled by Cloudflare)
                        ┌───────────────────────────────┐
                        │  Application Load Balancer    │
                        │      (Public Subnets)         │
                        └───────────────┬───────────────┘
                                        │
                ┌───────────────────────┴───────────────────────┐
                │ Security Group Route: Ingress port 80 only    │
                ▼                                               ▼
    ┌──────────────────────────────┐                ┌──────────────────────────────┐
    │       Public Subnet A        │                │       Public Subnet B        │
    │                              │                │                              │
    │   ┌──────────────────────┐   │                │   ┌──────────────────────┐   │
    │   │  EC2 App Instance    │   │                │   │  EC2 App Instance    │   │
    │   │     (t3.micro)       │   │                │   │     (t3.micro)       │   │
    │   └──────────┬───────────┘   │                │   └──────────┬───────────┘   │
    └──────────────┼───────────────┘                └──────────────┼───────────────┘
                   │                                               │
                   └───────────────────────┬───────────────────────┘
                                           │
                ┌──────────────────────────┴──────────────────────────┐
                │ Security Group Route: Ingress PostgreSQL (5432)     │
                ▼                                                     ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │                     Isolated Database Subnets (Private)                      │
    │                                                                              │
    │   ┌───────────────────────────┐                ┌───────────────────────────┐ │
    │   │    RDS PostgreSQL DB      │                │   Empty DB Subnet B       │ │
    │   │ (Single-AZ - db.t3.micro) │                │    (Prereq for RDS)       │ │
    │   └───────────────────────────┘                └───────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
```

## 2. Advanced Engineering Extensions (Free Tier)

To elevate this project from a standard exam setup to a high-fidelity platform engineering piece, we add three critical services. These include real-world engineering trade-offs:

### 1. CloudFront + S3 (Static Asset Offloading)

- **Status:** **Critical / Must-Have**
- **Engineering:** Host static frontend assets in a private S3 bucket, served globally via CloudFront with Origin Access Control (OAC).
- **Trade-off:** **Cache Latency.** Updates to files require manual invalidation or short TTLs. It adds complexity to your CI/CD pipeline but is essential for production performance.
- **Resume Value:** High (demonstrates CDN mastery).

### 2. CloudWatch Alarms + SNS (Monitoring)

- **Status:** **Highly Recommended**
- **Engineering:** Create CPU threshold alarms for the ASG that trigger SNS email notifications.
- **Trade-off:** **Alert Noise.** Over-sensitive alarms result in email spam during development; you must carefully tune thresholds.
- **Resume Value:** Medium-High (demonstrates SRE fundamentals).

### 3. SSM Parameter Store (Secrets)

- **Status:** **Recommended**
- **Engineering:** Inject database credentials at runtime via IAM Instance Profiles instead of hardcoded variables.
- **Trade-off:** **Rate Limiting.** Standard parameters are free but throttled at 40 req/sec. You must cache secrets on instances at startup to avoid API throttling.
- **Resume Value:** Medium (demonstrates production-grade security).

## 3. Core Differences: Paid Enterprise Spec vs. Free Tier Spec

| Component               | Paid Enterprise Spec                         | Free Tier Guardrail Spec                        | Cost / Billing Reality                                                                             |
| :---------------------- | :------------------------------------------- | :---------------------------------------------- | :------------------------------------------------------------------------------------------------- |
| **Outbound Updates**    | Private subnets routing via **NAT Gateway**. | Public subnets with **Internet Gateway (IGW)**. | **Saves ~$33.00/mo.** WARNING: Public IPv4 addresses now cost $0.005/hr. Use `make destroy` daily. |
| **Database Redundancy** | RDS Multi-AZ PostgreSQL.                     | RDS Single-AZ (`t3.micro`/`t4g.micro`).         | **Saves ~$15.00/mo.** Single-AZ keeps you within the 750 free monthly RDS hours.                   |
| **Key Management**      | Customer Managed KMS ($1.00/mo).             | Default AWS Managed Key (`aws/rds`).            | **Saves ~$1.00/mo.** Managed keys have no flat fee.                                                |
| **Cost Protection**     | Enterprise Cost Explorer.                    | **AWS Zero-Spend Budget**.                      | **100% Free.** Fires SNS alert if charges > $1.00.                                                 |

## 4. Free Tier Guardrails

- **IPv4 Cost Awareness:** AWS now charges for every public IPv4 address. Ensure your EC2 instances in public subnets do _not_ receive public IPs; let the ALB handle all public traffic.
- **Zero-Spend Budget:** Create a budget in the AWS Console for $1.00. Set an alert to email your SNS topic. This is your only true safety net against configuration errors.
- **Instance Types:** Use `t4g.micro` (Graviton/ARM) where possible. It is newer, more performant, and fully included in the Free Tier.

## 5. Terraform Directory Layout (`infra/aws/`)

```text
infra/aws/
├── versions.tf      # AWS Provider (~> 5.0) + Cloudflare R2 remote state backend
├── provider.tf      # Configures AWS provider default tags and region
├── variables.tf     # Parameters (CIDR, t4g.micro instances, etc.)
├── vpc.tf           # VPC, Subnets, Route Tables, Internet Gateway (IGW)
├── security.tf      # Chained Security Groups & IAM instance profiles
├── compute.tf       # Launch Template, ASG, and Application Load Balancer
├── storage.tf       # Private S3 Bucket, CloudFront Distribution & OAC Policy
├── database.tf      # Single-AZ RDS PostgreSQL Instance & DB Subnet Group
├── monitoring.tf    # CloudWatch Alarms & SNS Topics
├── secrets.tf       # SSM Parameter Store definitions
└── outputs.tf       # ALB DNS endpoint & CloudFront URL for testing
```

## 5. Engineering Gotchas (The "Real World" Gaps)

- **Schema Seeding:** Terraform is for infrastructure, not application data. Prepare an `init.sql` script. Avoid `null_resource` provisioners (they cause state drift). Manage migrations via your application logic at startup.
- **Dynamic Endpoint Injection:** RDS hostnames are generated at runtime. Use Terraform’s `templatefile()` function to inject `aws_db_instance.address` into your EC2 User Data script. Do not hardcode connection strings.
- **IAM & SSM Startup Propagation Latency:** IAM Instance Profiles take a few seconds to attach during EC2 initialization. If your User Data script attempts to fetch secrets from SSM immediately on boot, it will fail with `AccessDenied`. Use `cloud-init` wait-modules or wrap your SSM fetch commands in a retry loop inside the User Data script.
- **ALB Health Check Mismatch:** If your app listens on `/` or port `3000`, ensure the ALB Target Group health check path matches the app route. Misconfigured health check paths cause the ASG to enter an infinite tear-down/re-create loop.
- **State & Tooling Versioning:** Always include a `.terraform-version` file in `infra/aws/`. Version drift between your local binary and the R2 state can cause cryptic state-lock or format errors.

## 6. Development Flow with Makefile

Once you decide to deploy, you can control the entire cycle safely from your CLI:

```bash
# 1. Initialize remote state in Cloudflare R2
make init MOD=aws

# 2. Preview the AWS architecture blueprint
make plan MOD=aws

# 3. Spin up the infrastructure
make apply MOD=aws

# 4. Burn it down cleanly when done studying to guarantee $0.00 spend
make destroy MOD=aws
```
