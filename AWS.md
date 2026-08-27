# AWS SAA-C03 Portfolio Architecture: 3-Tier Fault-Tolerant Web App (Free Tier Compliant)

This document outlines the architecture, configuration strategy, and file structure for building a production-ready, enterprise-grade 3-Tier Web Application on AWS. It is designed to fit **100% within the AWS Free Tier** ($0.00/month) while teaching the exact networking, compute, and database concepts required for the **AWS Certified Solutions Architect - Associate (SAA-C03)** exam.

---

## 1. High-Level Architecture Diagram

```text
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

---

## 2. Advanced Engineering Extensions (Free Tier)

To elevate this project from a standard exam setup to a high-fidelity platform engineering piece, we add three critical services:

### 1. CloudFront + S3 (Static Asset Offloading)

* **Status:** **Critical / Must-Have**
* **Engineering:** Host static frontend assets in a private S3 bucket, served globally via CloudFront with Origin Access Control (OAC).
* **Trade-off:** **Cache Latency.** Updates to files require manual invalidation or short TTLs.
* **Resume Value:** High (demonstrates CDN mastery).

### 2. CloudWatch Alarms + SNS (Monitoring)

* **Status:** **Highly Recommended**
* **Engineering:** Create CPU threshold alarms for the ASG that trigger SNS email notifications.
* **Trade-off:** **Alert Noise.** Over-sensitive alarms result in email alerts during development.
* **Resume Value:** Medium-High (demonstrates SRE fundamentals).

### 3. SSM Parameter Store (Secrets)

* **Status:** **Recommended**
* **Engineering:** Inject database credentials at runtime via IAM Instance Profiles instead of hardcoded variables.
* **Trade-off:** **Rate Limiting.** Standard parameters are free but throttled at 40 req/sec. Cache secrets on boot.
* **Resume Value:** Medium (demonstrates production-grade security).

---

## 3. Core Differences: Paid Enterprise Spec vs. Free Tier Spec

| Component | Paid Enterprise Spec | Free Tier Guardrail Spec | Cost / Billing Reality |
| --- | --- | --- | --- |
| **Outbound Updates** | Private subnets routing via **NAT Gateway**. | Public subnets routing via **Internet Gateway (IGW)**. | **Saves ~$33.00/mo.** Auto-assigned public IPs leverage 750 free in-use IPv4 hours/month. Use `make destroy` daily. |
| **Database Redundancy** | RDS Multi-AZ PostgreSQL. | RDS Single-AZ (`db.t3.micro`). | **Saves ~$15.00/mo.** Single-AZ stays within the 750 free monthly RDS hours. |
| **Key Management** | Customer Managed KMS ($1.00/mo). | Default AWS Managed Key (`aws/rds`). | **Saves ~$1.00/mo.** Managed keys have no flat monthly fee. |
| **Cost Protection** | Enterprise Cost Explorer. | **AWS Zero-Spend Budget**. | **100% Free.** Fires SNS alert if charges exceed $1.00. |

---

## 4. Free Tier Guardrails

* **IPv4 Management:** App instances in public subnets receive auto-assigned public IPv4 addresses to pull packages directly via the Internet Gateway without needing an expensive NAT Gateway.
* **Zero-Spend Budget:** Provision an `aws_budgets_budget` resource set to $1.00 USD with SNS email alerts as an automated safety net against unintended charges.
* **Compute Optimization:** Defaults to `t3.micro` for general Free Tier safety, with `variables.tf` structured to allow optional ARM/Graviton (`t4g.micro`) deployment.

---

## 5. Terraform Directory Layout (`infra/aws/`)

```text
infra/aws/
├── versions.tf      # AWS Provider (~> 5.0) + Cloudflare R2 remote state backend
├── provider.tf      # Configures AWS provider default tags and region
├── variables.tf     # Parameters (CIDR, t3.micro instances, etc.)
├── vpc.tf           # VPC, Subnets, Route Tables, Internet Gateway (IGW)
├── security.tf      # Chained Security Groups & IAM instance profiles
├── compute.tf       # Launch Template, ASG, and Application Load Balancer
├── storage.tf       # Private S3 Bucket, CloudFront Distribution & OAC Policy
├── database.tf      # Single-AZ RDS PostgreSQL Instance & DB Subnet Group
├── monitoring.tf    # CloudWatch Alarms, SNS Topics, & AWS Zero-Spend Budget
├── secrets.tf       # SSM Parameter Store definitions
└── outputs.tf       # ALB DNS endpoint & CloudFront URL for testing

```

---

## 6. Engineering Gotchas (The "Real World" Gaps)

* **Schema Seeding:** Manage database schema initialization via application startup routines rather than Terraform `null_resource` provisioners to prevent state drift.
* **Dynamic Endpoint Injection:** RDS hostnames are generated at runtime. Use Terraform’s `templatefile()` function to inject `aws_db_instance.address` into your EC2 User Data script.
* **IAM & SSM Startup Propagation Latency:** IAM Instance Profiles take a few seconds to propagate during EC2 initialization. Ensure your User Data script includes retry loops or `cloud-init` waits when fetching SSM parameter values.
* **ALB Health Check Mismatch:** Match the ALB Target Group health check path to the exact route exposed by your web app to prevent the Auto Scaling Group from entering continuous replacement loops.
* **State & Tooling Versioning:** Include a `.terraform-version` file in `infra/aws/` to keep your local CLI aligned with remote Cloudflare R2 state locks.
* **Inline HCL vs. Public Modules:** Avoid public modules (`terraform-aws-modules/vpc`) in this specific repository to maintain explicit visibility over resource provisioning, prevent hidden billing side-effects (e.g., implicit NAT Gateways/KMS creation), and keep R2 remote state locks lean. Modularization should be deferred to shared enterprise module registries.
- **Single-AZ to Multi-AZ RDS Strategy:** RDS is explicitly deployed Single-AZ to remain within the 750 free monthly RDS hours. However, zero-downtime failover is pre-architected: the `aws_db_subnet_group` spans multiple AZs, allowing instant conversion to a Multi-AZ standby pair simply by setting `multi_az = true` on `aws_db_instance`.

---

## 7. Development Flow with Makefile

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
