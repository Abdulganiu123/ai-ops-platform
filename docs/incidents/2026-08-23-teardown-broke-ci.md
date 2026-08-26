# Tearing down the infrastructure broke CI

**Date:** 2026-08-23
**Impact:** Every pull request failed at the credentials step. No production impact.
**Time to resolve:** ~30 minutes, most of it spent misreading the logs.

## What happened

After running `terraform destroy` to avoid idle costs overnight, the next pull
request failed. The `plan` job produced this:

    Run aws-actions/configure-aws-credentials@v4
    Assuming role with OIDC
    Assuming role with OIDC
    ... (twelve times)
    Error: Process completed with exit code 1

A second, cascading error followed from the summary step:

    tail: cannot open 'plan.txt' for reading: No such file or directory

## Root cause

`aws_iam_role.ci` — the role GitHub Actions assumes via OIDC — is defined in
`terraform/ci.tf`, inside the same configuration as the application resources.
`terraform destroy` removed it along with everything else.

CI was attempting to assume a role that no longer existed.

This is a **bootstrap ordering** defect. The CI role is not application
infrastructure; it is the credential that allows automation to exist at all.
Putting it in a configuration that gets destroyed regularly means routine
teardown silently removes CI's ability to authenticate.

The OIDC provider itself survived, because it is referenced as a `data` source
rather than a managed resource — a decision made earlier specifically to avoid
owning shared account-level infrastructure. That decision was correct, and the
same reasoning should have been applied to the role.

## Why the logs were unhelpful

Two separate problems compounded:

**The retry loop hid the error.** `aws-actions/configure-aws-credentials`
defaults `retry-max-attempts` to 12. Twelve identical "Assuming role with OIDC"
lines appeared before any error surfaced, and in a truncated log view the actual
message was easy to miss entirely.

**The cascading failure was louder than the real one.** The `Post plan to
summary` step runs with `if: always()`, so it executed after the plan step never
produced a file. Its error — a missing `plan.txt` — appeared last and read as
the primary failure. The real cause was several steps earlier.

## Resolution

Applied locally with developer credentials to recreate the role, then re-ran the
job. No code change was required.

    make package
    cd terraform && terraform apply
    terraform output ci_role_arn

The ARN was unchanged. The role name is deterministic (`devgen-ci`), so a
destroy and recreate produces an identical ARN — which is why it was never
stored in SSM, unlike the Guardrail id.

## Lessons

- **Bootstrap-tier infrastructure must not live in the tier it bootstraps.**
  The state bucket and the CI role both exist so that automation can run. They
  belong in a configuration applied once by a human, not one destroyed nightly.
- **Retry loops obscure root causes.** A default of 12 attempts is reasonable
  for transient failures and actively harmful for permanent ones. Set
  `retry-max-attempts: 2` so a misconfiguration fails fast and legibly.
- **`if: always()` steps can bury the real error.** A cleanup step that fails
  because an earlier step failed will be the last thing in the log, and
  therefore the first thing read. Guard such steps so they degrade quietly.
- **This failure had no unique symptom.** "Could not assume role" is the same
  message produced by a wrong trust policy, a missing secret, a deleted role,
  and a malformed sub claim. Distinguishing them requires checking whether the
  role exists, which no log will tell you.

## Follow-up

- [ ] Move `ci.tf` and the state bucket into a separate bootstrap configuration
      applied once, so teardown cannot remove CI's credentials
- [ ] Set `retry-max-attempts: 2` and `action-timeout-s` on all
      `configure-aws-credentials` steps
- [ ] Add a self-diagnosis job so devgen explains its own CI failures
