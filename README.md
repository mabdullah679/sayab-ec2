# sayab-ec2

A small Flask web app (a personalized greeting page) hardened for production and deployed to AWS EC2 with Terraform and GitHub Actions.

There is no separate requirements document; the behaviour is defined by `backend/app.py` and the tests in `tests/test_app.py`.

```
 browser --HTTP:80--> ALB (2 public subnets, 2 AZs)
                         | HTTP:8000, SG-to-SG only
                         v
            ASG (min=max=1) -> EC2 t4g.micro Spot, AL2023 arm64, IMDSv2
                               systemd -> gunicorn (2 workers) -> Flask
                               logs -> CloudWatch Logs   config <- SSM Parameter Store
                               access: SSM Session Manager (no port 22)

 git push / pull request -> GitHub Actions: ruff + pytest + terraform fmt/validate + gitleaks (no AWS)

 gh workflow run ci-deploy --ref prod-hardening   (workflow_dispatch = the only deploy trigger)
   -> OIDC (no AWS keys) -> upload release tarball to S3 -> terraform plan -> apply
   -> ASG instance refresh (launch new, then retire old) -> smoke test against the ALB URL
```

Not contained in this repo: an AWS account with the GitHub OIDC provider and the `portfolio-ci-boundary` IAM policy already present (the bootstrap step references both, it does not create them).

## Prerequisites

- Python 3.11 (3.9 cannot run the pinned gunicorn; CI and the instance use 3.11).
- To deploy: Terraform >= 1.10, AWS CLI with credentials for account 346208529954 in ap-southeast-2, `gh` CLI.
- Not needed on the host: Docker, Node, SSH keys.

## Run it

Locally:

```
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
cd backend && ../.venv/bin/python app.py        # http://127.0.0.1:5000
```

Deploy (pushes never deploy; only a manual workflow run does):

1. Bootstrap (local state, run by a human once): `terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap apply`. Creates the state bucket, the release bucket and the GitHub OIDC deploy role.
2. Run `gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening`.
3. The pipeline prints the URL in the `deploy` job (`terraform output url`) and the `smoke` job checks it.

Override: the GitHub trust policy only allows branch `prod-hardening`; change `github_branch` in `infra/bootstrap/main.tf` to deploy from another branch. If On-Demand vCPU quota is available, set `use_spot=false` in `infra/variables.tf`.

## Free hosting path: AWS Lambda + Function URL (added 2026-11-18, prepared, not deployed)

The same Flask app also runs on Lambda behind a Function URL, an additional path that leaves the EC2/ALB stack untouched. Adapter: `apig-wsgi` 2.20.0 (pure Python, one dependency, speaks Function URL payload v2, no layer or extension needed; Lambda Web Adapter was rejected because it needs a layer ARN and a gunicorn process for no gain here).

```
 browser --HTTPS--> Lambda Function URL (auth NONE, public demo) -> Lambda python3.12 arm64
                    handler lambda_handler.handler -> apig-wsgi -> Flask (backend/app.py)
                    logs -> CloudWatch Logs (7-day retention)   reserved concurrency = 5
```

Files: `backend/lambda_handler.py`, `scripts/build_lambda.sh` (builds `dist/lambda.zip` with app, `templates/`, `frontend/` and arm64 deps from `requirements-lambda.txt`), `infra/lambda/` (function, URL, logging-only IAM role, log group, outputs `url`; local state, no backend), tests `tests/test_lambda_handler.py` (14, Function URL v2 events) and `tests/test_lambda_zip.py` (3, plus 1 that runs only against a full build via `LAMBDA_ZIP`).

Deploy (owner runs this later; needs AWS credentials, none were used to prepare it):

```
bash scripts/build_lambda.sh
terraform -chdir=infra/lambda init && terraform -chdir=infra/lambda apply
curl "$(terraform -chdir=infra/lambda output -raw url)readyz"
```

Destroy: `terraform -chdir=infra/lambda destroy`. State is a local `terraform.tfstate` in `infra/lambda/` (gitignored); keep it until destroy, or the resources are orphaned.

What $0 means here (published free-tier figures, not an invoice, not verified against the account):
- Lambda always-free: 1,000,000 requests and 400,000 GB-seconds per month. At 256 MB that is about 1.6M seconds of execution; a request here takes milliseconds, so the 1M requests is the binding limit.
- Beyond that you pay per request and per GB-second. `reserved_concurrent_executions = 5` caps parallelism (extra requests get 429), which bounds but does not zero the spend. Function URLs have no charge of their own.
- CloudWatch Logs has its own free allowance (about 5 GB ingestion per month); the 7-day retention keeps storage small. Outbound data transfer has a free monthly allowance (about 100 GB, shared across the account).
- Not covered: a custom domain, WAF, or alarms (each would cost money or need extra setup). There is no rate limit besides the concurrency cap; a public URL can be hit by anyone.
- Risk to check before apply: reserving concurrency must leave the account's unreserved concurrency at 10 or more. A new or restricted account with a low Lambda concurrency quota can reject `reserved_concurrency = 5`; delete the `reserved_concurrent_executions` line or lower it. The org SCP/quota notes in the owner's memory were not consulted against this.
- This stack uses AWS provider `~> 6.0` (needs `invoked_via_function_url`); the EC2 stack stays on `~> 5.80`.

## What it does

| Action | Result |
| --- | --- |
| `GET /` | The name form (`frontend/index.html`) styled by `/static/styles.css` |
| `POST /submit` with `user_name=jane doe` | HTML greeting containing `Jane Doe` |
| `POST /submit` with a blank name | Greets `Guest` |
| `POST /submit` with HTML such as `<script>` | Output is escaped (previously reflected, a real XSS) |
| `POST /submit` with a name over 60 characters or with control characters | `400` JSON error |
| `POST /submit` with a body over 4096 bytes | `413` JSON error |
| `GET /healthz` | `{"status":"ok"}` (liveness) |
| `GET /readyz` | `{"status":"ready"}`, or `503` if the frontend files are missing (used by the ALB health check) |

## Interface

| Method | Path | Auth |
| --- | --- | --- |
| GET | `/` | none |
| GET | `/static/<file>` | none |
| POST | `/submit` (form field `user_name`) | none |
| GET | `/healthz`, `/readyz` | none |

Config (env, on the instance from SSM Parameter Store `/pf-sayab-ec2/config/*`): `MAX_BODY_BYTES` (default 4096), `FRONTEND_DIR`, `HOST`, `PORT` (dev server only).
Every response carries `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` and a `Content-Security-Policy`. Access logs are one JSON line per request; the submitted name is never logged.

## Tests

```
pip install -r requirements-dev.txt
ruff check . && ruff format --check . && pytest -q
```

17 tests in `tests/test_app.py` plus 14 Lambda handler tests and 4 zip tests (`tests/test_lambda_*.py`; 34 pass and 1 is skipped without `LAMBDA_ZIP`); no external services needed. Each guard (length limit, control-character check, HTML escaping, body-size limit, readiness check, security header) was mutated and its test watched fail before the exact edit was reversed. The original app fails 13 of these 17 (it was reproduced reflecting `<script>alert(1)</script>`, accepting a 100 KB name, and serving no stylesheet).

## Layout

| Path | Role |
| --- | --- |
| `backend/app.py` | Flask app factory, validation, health endpoints, headers, JSON logs |
| `backend/templates/greeting.html` | Escaped greeting page |
| `frontend/` | `index.html`, `styles.css` |
| `tests/` | pytest suite |
| `requirements.txt`, `requirements-dev.txt`, `pyproject.toml` | Pinned runtime/dev deps, ruff/pytest config |
| `infra/main.tf`, `variables.tf`, `versions.tf`, `outputs.tf` | VPC, SGs, ALB, ASG, launch template, IAM, SSM, CloudWatch |
| `infra/scripts/user_data.sh.tftpl` | Idempotent instance bootstrap (install, systemd unit, CloudWatch agent) |
| `backend/lambda_handler.py`, `scripts/build_lambda.sh`, `requirements-lambda.txt`, `infra/lambda/` | Lambda free path (see above) |
| `infra/bootstrap/main.tf` | One-time state bucket, release bucket, OIDC deploy role |
| `.github/workflows/deploy.yml` | CI/CD pipeline (actions pinned to commit SHAs) |
| `CLAUDE.md` | Repo-specific notes for AI coding sessions |
| `scripts/smoke.sh` | Post-deploy checks against a URL |

## Design decisions

- **Release tarball in S3 instead of `git clone` on the instance.** The repository history is about 190 MB (see below); cloning it at boot would be slow and would pull a private key onto the box. The instance downloads a ~7 KB tarball keyed by commit SHA.
- **ALB + ASG of 1 rather than a lone instance with an Elastic IP.** The ALB gives a stable DNS name, a health check that actually exercises `/readyz`, and lets the ASG replace the instance with launch-before-terminate (observed: zero 5xx during the final refresh). It costs about 2.5 cents an hour; an Elastic IP would need user-data association and gives no health-based replacement.
- **Spot.** The account's On-Demand "Standard" vCPU quota (8) was fully used by other instances (the first launch failed with `VcpuLimitExceeded`); Spot has its own quota and is cheaper. The trade-off is that AWS can reclaim the instance; the ASG then replaces it (about 2-4 minutes of downtime with one instance).
- **No NAT gateway.** Instances sit in public subnets with a security group that only accepts port 8000 from the ALB; outbound is limited to 80/443. No SSH, access is SSM Session Manager.
- **Plain HTTP only.** No domain or certificate exists, so there is no HTTPS listener. The page collects only a first name, but this is not production-grade transport security.
- **venv built in its final path.** An earlier bootstrap built it in a temp directory and renamed it; the shebang pointed at the old path and systemd failed with 203/EXEC. A `.complete` marker now makes half-built installs get redone.
- **Why the repo was 190 MB.** It tracked an entire EC2 home directory: about 11,200 files (npm cache, pip cache, virtualenv wheels, `.bash_history`, `.ssh/`). This branch untracks them and `.gitignore` blocks them; CI fails if they reappear. The files are still in git history. The history contains a private SSH key (`.ssh/id_ed25519`); treat it as compromised and rotate it. History was not rewritten.

## Deployed on AWS

Verified live on 2026-10-20 (account 346208529954, region ap-southeast-2) through GitHub Actions run 39395015892, then torn down the same day to save cost. The stack is not running now.

What was observed while it was live, by curl against the ALB (`http://pf-sayab-ec2-alb-<id>.ap-southeast-2.elb.amazonaws.com`):

- `GET /healthz` returned `200 {"status":"ok"}` with the security headers and `Server: gunicorn`; `GET /readyz` returned `{"status":"ready"}`.
- `POST /submit user_name=jane doe` returned the greeting containing `Jane Doe`.
- `scripts/smoke.sh` printed `SMOKE PASSED` (healthz, form, stylesheet, greeting, XSS escaped, overlong name 400, security headers).
- The instance was a t4g.micro Spot instance with IMDSv2 required and an encrypted 8 GiB gp3 volume; JSON access logs reached the `/pf-sayab-ec2/app` log group.

Never established: HTTPS, Spot reclaim behaviour, alarm delivery (the SNS topic had no subscribers), and browser rendering.

Resources (28 in `infra/`, all `pf-sayab-ec2-*`, tagged `project=portfolio`, `repo=sayab-ec2`, `managed-by=terraform`): VPC, 2 subnets, internet gateway, route table and associations, 2 security groups and 5 rules, ALB, target group, listener, launch template, ASG, instance role/profile/policies, SSM parameter, log group, SNS topic, 2 alarms. Bootstrap added 2 S3 buckets and the deploy role. Cost while up was about US$0.045 per hour (estimate from published prices, not an invoice).

Teardown, done 2026-10-20: `terraform -chdir=infra destroy -var release_key=unused`, then `terraform -chdir=infra/bootstrap destroy`. Afterwards, direct lookups for the ALB, target group, ASG, launch template, instances, VPC, security groups, S3 buckets, IAM roles and profiles, log groups, alarms, SNS topics and SSM parameters all returned 0, and the URL no longer responded. The AWS-managed service-linked role `AWSServiceRoleForAutoScaling` (created on first use) was left in place; it is shared and free.

Rebuild:

```
terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap apply   # recreates state bucket, release bucket, deploy role
gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening          # tests, plan, apply, smoke test
```
