# CLAUDE.md (sayab-ec2)

Global working rules: `~/.claude/CLAUDE.md` (read it; not copied here). This file is repo-specific only.

## Commands (ruff/pytest run locally 2026-11-18 on Python 3.12; CI uses 3.11; the terraform line runs in CI only, terraform is not installed on the owner machine)

```
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/pytest -q   # 34 passed, 1 skipped
terraform -chdir=infra fmt -check -recursive && terraform -chdir=infra init -backend=false && terraform -chdir=infra validate
```
Lambda zip (full, needs PyPI): `bash scripts/build_lambda.sh && LAMBDA_ZIP=dist/lambda.zip .venv/bin/pytest -q tests/test_lambda_zip.py`; Lambda terraform check: `terraform -chdir=infra/lambda fmt -check && terraform -chdir=infra/lambda init -backend=false && terraform -chdir=infra/lambda validate` (validated 2026-11-18 via the hashicorp/terraform:1.12.2 docker image, provider 6.73.0).

## Layout
Flask app in `backend/app.py`, static page in `frontend/`, tests in `tests/`, Terraform in `infra/` (stack) and `infra/bootstrap/` (one-time state bucket + OIDC role), pipeline in `.github/workflows/deploy.yml`. Free Lambda path (apig-wsgi, Function URL): `backend/lambda_handler.py`, `scripts/build_lambda.sh`, `infra/lambda/` (local state, provider ~> 6.0, separate from the EC2 stack): parent `main.tf` + `modules/{log_group,exec_role,function_url}` + `moved.tf` (old flat addresses -> module addresses; keep it until every state has been applied with this layout). Offline tests: `bash scripts/tf_test.sh` (native `terraform test`, mock_provider; CI job `terraform-tests`). `reserved_concurrency` defaults to -1: account Lambda limit is 10 and AWS requires >=10 unreserved, so 5 is rejected (2026-11-18). LIVE: applied by the owner 2026-11-18 (account 025066259864, ap-southeast-2, https://hti5gehhgooawm33auws625esm0vbymx.lambda-url.ap-southeast-2.on.aws/); the EC2/ALB stack in `infra/` stays torn down. State is local on the owner's laptop (`infra/lambda/terraform.tfstate`, gitignored), NOT backed up; teardown = `terraform -chdir=infra/lambda destroy`. Deploy/destroy commands and $0 limits are in README.md.

## Conventions
- Feature branch + PR; never push to `master`. Pushes and PRs only run checks; deploy is `workflow_dispatch` on `prod-hardening` only.
- Pin third-party actions to full commit SHAs with a version comment.
- A guard change needs a test that was seen failing first (mutate, see red, reverse the exact edit).

## Do NOT
- Run `terraform apply`/`destroy` or any `aws` call from a session without the owner's explicit consent (the EC2 stack is torn down as of 2026-10-20; the Lambda stack in `infra/lambda/` is LIVE, so never touch or move its `terraform.tfstate`; experiment on a copy only).
- Rewrite history. A private SSH key (`.ssh/id_ed25519`) is in old history; the owner decides on rotation/history scrub.
- Re-track home-directory debris (`.ssh/`, `.npm/`, `.cache/`); CI fails if it appears.
