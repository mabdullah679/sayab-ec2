# sayab-ec2

A small Flask web app (a "welcome" page that greets a visitor by name) hardened for production and deployed to AWS EC2 with Terraform and GitHub Actions.

There is no separate requirements document; the behaviour is defined by `backend/app.py` and the tests in `tests/test_app.py`.

```
 browser --HTTP:80--> ALB (2 public subnets, 2 AZs)
                         | HTTP:8000, SG-to-SG only
                         v
            ASG (min=max=1) -> EC2 t4g.micro Spot, AL2023 arm64, IMDSv2
                               systemd -> gunicorn (2 workers) -> Flask
                               logs -> CloudWatch Logs   config <- SSM Parameter Store
                               access: SSM Session Manager (no port 22)

 git push prod-hardening
   -> GitHub Actions: ruff + pytest + terraform fmt/validate
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

Deploy (once, then on every push to `prod-hardening`):

1. Bootstrap (local state, run by a human once): `terraform -chdir=infra/bootstrap init && terraform -chdir=infra/bootstrap apply`. Creates the state bucket, the release bucket and the GitHub OIDC deploy role.
2. Push to `prod-hardening`, or run `gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening`.
3. The pipeline prints the URL in the `deploy` job (`terraform output url`) and the `smoke` job checks it.

Override: the GitHub trust policy only allows branch `prod-hardening`; change `github_branch` in `infra/bootstrap/main.tf` to deploy from another branch. If On-Demand vCPU quota is available, set `use_spot=false` in `infra/variables.tf`.

## What it does

| Action | Result |
| --- | --- |
| `GET /` | The name form (`frontend/index.html`) styled by `/static/styles.css` |
| `POST /submit` with `user_name=ayesha asim` | HTML greeting containing `Ayesha Asim` |
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

17 tests in `tests/test_app.py`; no external services needed. Each guard (length limit, control-character check, HTML escaping, body-size limit, readiness check, security header) was mutated and its test watched fail before the exact edit was reversed. The original app fails 13 of these 17 (it was reproduced reflecting `<script>alert(1)</script>`, accepting a 100 KB name, and serving no stylesheet).

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
| `infra/bootstrap/main.tf` | One-time state bucket, release bucket, OIDC deploy role |
| `.github/workflows/deploy.yml` | CI/CD pipeline |
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

Verified 2026-10-20 in account 346208529954, region ap-southeast-2, through GitHub Actions run 39395015892 (jobs test, terraform-checks, deploy, smoke all green; the deploy authenticated with OIDC, no stored keys).

URL pattern: `http://pf-sayab-ec2-alb-<id>.ap-southeast-2.elb.amazonaws.com` (the live one was `http://pf-sayab-ec2-alb-1381512978.ap-southeast-2.elb.amazonaws.com`).

Observed by curl against the ALB:

- `GET /healthz` returned `200 {"status":"ok"}` with the security headers above and `Server: gunicorn`.
- `GET /readyz` returned `{"status":"ready"}`.
- `POST /submit user_name=ayesha asim` returned the greeting containing `Ayesha Asim`.
- `scripts/smoke.sh` printed `SMOKE PASSED` (healthz, form, stylesheet, greeting, XSS escaped, overlong name 400, security headers).

Observed in AWS: the running instance is a t4g.micro Spot instance with IMDSv2 required (`HttpTokens=required`), an encrypted 8 GiB gp3 volume, and a log stream `<instance-id>/app` in `/pf-sayab-ec2/app` containing the JSON access logs.

Not established: HTTPS, Spot reclaim behaviour (never triggered), the SNS alarm topic delivering to anyone (it has no subscribers), and visual rendering in a browser (curl only; the page was not opened in a browser).

Resources (28 managed by `infra/`, all named `pf-sayab-ec2-*` and tagged `project=portfolio`, `repo=sayab-ec2`, `managed-by=terraform`): VPC, 2 subnets, internet gateway, route table + 2 associations, 2 security groups + 5 rules, ALB, target group, listener, launch template, ASG, instance role + profile + 2 managed-policy attachments + inline policy, SSM parameter, log group (14-day retention), SNS topic, 2 CloudWatch alarms. Bootstrap adds 2 S3 buckets, their config, and the deploy role.

Cost (estimate from published on-demand/Spot prices, not an invoice): about US$0.045 per hour, roughly $1.1 per day, dominated by the ALB (~$0.025-0.034) and three public IPv4 addresses (~$0.015).

Teardown (to stop cost), in this order:

```
terraform -chdir=infra destroy -var release_key=unused     # needs the pf-sayab-ec2-tfstate bucket
terraform -chdir=infra/bootstrap destroy                    # last: state + release buckets, deploy role
```

Rebuild with one command after step 1 of "Run it" exists: `gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening`.
