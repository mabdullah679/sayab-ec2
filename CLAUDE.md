# CLAUDE.md (sayab-ec2)

Global working rules: `~/.claude/CLAUDE.md` (read it; not copied here). This file is repo-specific only.

## Commands (ruff/pytest run locally 2026-11-18 on Python 3.12; CI uses 3.11; the terraform line runs in CI only, terraform is not installed on the owner machine)

```
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/ruff check . && .venv/bin/ruff format --check . && .venv/bin/pytest -q   # 17 passed
terraform -chdir=infra fmt -check -recursive && terraform -chdir=infra init -backend=false && terraform -chdir=infra validate
```

## Layout
Flask app in `backend/app.py`, static page in `frontend/`, tests in `tests/`, Terraform in `infra/` (stack) and `infra/bootstrap/` (one-time state bucket + OIDC role), pipeline in `.github/workflows/deploy.yml`.

## Conventions
- Feature branch + PR; never push to `master`. Pushes and PRs only run checks; deploy is `workflow_dispatch` on `prod-hardening` only.
- Pin third-party actions to full commit SHAs with a version comment.
- A guard change needs a test that was seen failing first (mutate, see red, reverse the exact edit).

## Do NOT
- Run `terraform apply`/`destroy` or any `aws` call from a session without the owner's explicit consent (the stack is torn down as of 2026-10-20).
- Rewrite history. A private SSH key (`.ssh/id_ed25519`) is in old history; the owner decides on rotation/history scrub.
- Re-track home-directory debris (`.ssh/`, `.npm/`, `.cache/`); CI fails if it appears.
