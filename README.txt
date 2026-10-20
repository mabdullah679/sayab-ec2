SAYAB-EC2 IN PLAIN WORDS

What this is
A tiny personalized greeting website. You type your name, press Enter, and it shows a greeting. The original was a hobby project that only ran by hand on one computer. It is now set up to run on Amazon's cloud (AWS) and to update itself whenever new code is pushed to the branch called prod-hardening.

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
Pushing to prod-hardening makes GitHub run the tests, build a small package, log in to AWS without any stored passwords, upload the package, run Terraform to update the setup, swap in a new server before removing the old one, and then test the live address.

What went wrong on the way and how it was solved
1. The first deploy failed because the account is not allowed more than 8 virtual CPUs on regular servers and other projects were using all of them. Solved by using Spot servers, which have their own allowance and cost less. The catch is that AWS can take a Spot server back.
2. The next deploy started the server but the app would not start. The bootstrap built the Python environment in a temporary folder and then moved it, which broke it. It now builds in place.
3. Servers were missing the project tags. Fixed.
4. The 5xx alarm went off because of errors during the failed attempts above. It returned to OK by itself about an hour later, with no new errors in between.

What was checked on the live site (2026-10-20)
The health pages answered OK, the greeting worked, a script-tag name was shown as plain text, a too-long name was refused, and the safety headers were present. The automatic smoke test printed SMOKE PASSED.

What was NOT checked
Secure HTTPS (there is no domain or certificate, so it is plain HTTP), what happens when AWS takes back the Spot server, whether anyone receives the alarm emails (nobody is subscribed), and how the page looks in a real browser (only command-line tests were used).

Cost
Roughly 4.5 US cents an hour, about 1 dollar 10 a day, mostly the load balancer. This is an estimate from published prices, not a bill.

Status
It was checked live on 2026-10-20 and then deleted the same day to save money. Nothing is running now. After deletion every lookup for the load balancer, server, network, storage buckets, roles, logs, alarms and settings found nothing, and the web address stopped answering. One free AWS-owned helper role (AWSServiceRoleForAutoScaling) was left behind on purpose.

How to turn it back on
Step 1: terraform -chdir=infra/bootstrap init, then terraform -chdir=infra/bootstrap apply. This recreates the storage buckets and the deploy role.
Step 2: gh workflow run ci-deploy -R mabdullah679/sayab-ec2 --ref prod-hardening. This runs the tests, builds the setup, deploys it and tests the live address.
