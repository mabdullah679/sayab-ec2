SAYAB-EC2 IN PLAIN WORDS

What this is
A tiny personalized greeting website. You type your name, press Enter, and it shows a greeting. The original was a hobby project that only ran by hand on one computer. It is now set up to run on Amazon's cloud (AWS) and to be deployed there by a manual button-press (a GitHub Actions run on the branch called prod-hardening). Pushing code alone never deploys it.

Why the repository was so big
Someone saved a whole home folder from a server into the repository by accident. That is about 11,200 files: download caches, bash history, and SSH keys. They have been removed from the current version and blocked from coming back. They are still in the old history. One of them is a private SSH key. It should be treated as stolen and replaced. The history was not rewritten.

What was fixed in the website
1. If you typed code as your name, the page would run it. That is a real security hole. It is fixed and a test proves it.
2. There was no limit on name length. Now it is 60 characters, and odd control characters are refused.
3. The stylesheet was never loaded, so the page was never styled. Fixed.
4. Added health check pages (/healthz and /readyz), safer browser headers, readable logs that never record the name, and 17 automatic tests. Each safety rule was deliberately broken once to check that its test noticed.

How it runs on AWS
A load balancer receives web traffic and passes it to one small server (a t4g.micro on Spot pricing). If the server dies or fails its health check, AWS starts a replacement. Nobody can log in over SSH. Access is through AWS Systems Manager. Logs go to CloudWatch, one setting is read from AWS Parameter Store, and there are two alarms.

How updates happen
Pushing code only runs the checks: style, the automatic tests, a syntax check of the setup files, and a scan for leaked passwords or keys in new commits. It never touches AWS, so it cannot deploy by accident. A deploy happens only when someone starts it by hand with: gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening. That run logs in to AWS without stored passwords, uploads the package, updates the setup, swaps in a new server before removing the old one, and tests the live address.

What went wrong on the way and how it was solved
1. The first deploy failed because the account is not allowed more than 8 virtual CPUs on regular servers and other projects were using all of them. Solved by using Spot servers, which have their own allowance and cost less. The catch is that AWS can take a Spot server back.
2. The next deploy started the server but the app would not start. The bootstrap built the Python environment in a temporary folder and then moved it, which broke it. It now builds in place.
3. Servers were missing the project tags. Fixed.
4. The 5xx alarm went off because of errors during the failed attempts above. It returned to OK by itself about an hour later, with no new errors in between.

What was checked on the live site (2026-10-20)
The health pages answered OK, the greeting worked, a script-tag name was shown as plain text, a too-long name was refused, and the safety headers were present. The automatic smoke test printed SMOKE PASSED.

What was NOT checked
Secure HTTPS (there is no domain or certificate, so it is plain HTTP), what happens when AWS takes back the Spot server, whether anyone receives the alarm emails (nobody is subscribed), and how the page looks in a real browser (only command-line tests were used).

Free hosting option on AWS Lambda (added 2026-11-18, LIVE since 2026-11-18)
The same website also runs on AWS Lambda, Amazon's pay-per-use code runner, with a public web address (a Function URL): https://hti5gehhgooawm33auws625esm0vbymx.lambda-url.ap-southeast-2.on.aws/ . It was deployed on 2026-11-18 into account 025066259864 (region ap-southeast-2). The old server setup (EC2 and load balancer) stays torn down since 2026-10-20. A small helper library (apig-wsgi) lets the same Flask code answer Lambda requests.
Files: backend/lambda_handler.py, scripts/build_lambda.sh (packs the app into dist/lambda.zip), requirements-lambda.txt, and the infra/lambda folder (the setup files). The setup is now split into three small parts (modules) under infra/lambda/modules: log_group (the log store, kept 7 days), exec_role (the Lambda's login with permission to write only its own logs), function_url (the function, its public address and the two permissions that make it public). A parent file, main.tf, joins them. A file called moved.tf tells Terraform that the old names now live inside the modules, so the already-running resources are renamed in its records and nothing is deleted or rebuilt.
Proof so far (offline only, no AWS contact): on a copy of the real records, a dry run showed all 7 resources as moved and "0 to add, 0 to change, 0 to destroy". Not yet proven: the real plan against AWS. The owner must run terraform plan once and see the same result before the next apply.
Tests: automatic checks of the module wiring (names, public address with no login, 7-day logs, concurrency default) run with bash scripts/tf_test.sh and in CI as the terraform-tests job, using pretend AWS so nothing real is touched.
To redeploy (owner runs, needs AWS login): bash scripts/build_lambda.sh, then terraform -chdir=infra/lambda init, then terraform -chdir=infra/lambda apply. To remove it (teardown): terraform -chdir=infra/lambda destroy.
WARNING about the records file: the Terraform records live only in infra/lambda/terraform.tfstate on the owner's laptop. They are not backed up and not stored remotely. If that file is lost, the live Lambda is orphaned and has to be imported or deleted by hand.
Why it is free: AWS gives every account 1 million Lambda requests and 400,000 GB-seconds of run time each month at no charge, with no expiry. This page needs only milliseconds per request, so the request count is the limit. Past that you pay a small amount per request. Logs are kept 7 days, and CloudWatch has its own small free allowance. These are published figures, not a bill, and were not checked against your account.
Parallel-run cap: this account allows only 10 Lambda runs at once in total and AWS requires 10 to stay unreserved, so a cap of 5 is refused (checked 2026-11-18). The setting reserved_concurrency now defaults to -1 (no cap) and can be overridden if the limit is raised.

Cost
Roughly 4.5 US cents an hour, about 1 dollar 10 a day, mostly the load balancer. This is an estimate from published prices, not a bill.

Status
It was checked live on 2026-10-20 and then deleted the same day to save money. Nothing is running now. After deletion every lookup for the load balancer, server, network, storage buckets, roles, logs, alarms and settings found nothing, and the web address stopped answering. One free AWS-owned helper role (AWSServiceRoleForAutoScaling) was left behind on purpose.

How to turn it back on
Step 1: terraform -chdir=infra/bootstrap init, then terraform -chdir=infra/bootstrap apply. This recreates the storage buckets and the deploy role.
Step 2: gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening. This runs the tests, builds the setup, deploys it and tests the live address.
