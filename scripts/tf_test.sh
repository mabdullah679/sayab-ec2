#!/usr/bin/env bash
# Offline Terraform tests for infra/lambda (mock_provider, no AWS calls). Needs `terraform` >= 1.10 on PATH.
set -euo pipefail
cd "$(dirname "$0")/../infra/lambda"
terraform fmt -check -recursive
terraform init -backend=false -input=false
terraform validate
terraform test
for m in modules/*/; do
  terraform -chdir="$m" init -backend=false -input=false
  terraform -chdir="$m" test
done
