# OIDC trust mismatch blocked the Terraform plan job

**Date:** 2026-08-14
**Impact:** The `plan` job failed on every pull request. No production impact.
**Time to resolve:** ~2 hours

## What happened

The GitHub Actions `plan` job could not assume the `devgen-ci` AWS role.
Every run failed at the credentials step with:

    Not authorized to perform sts:AssumeRoleWithWebIdentity

## Root cause

Two separate defects, found in sequence.

1. `github_repo` in `terraform.tfvars` held a full URL rather than
   `owner/name`, producing a trust condition of
   `repo:https://github.com/OWNER/REPO:*`. This can never match.

2. After fixing that, it still failed. GitHub issues an immutable `sub`
   claim for repositories created after 2026-07-15, embedding numeric
   owner and repository ids:

       repo:OWNER@141291216/REPO@1334741436:pull_request

   The trust policy expected `repo:OWNER/REPO:*`. No owner/name pattern
   can match the immutable form, because the ids sit between the names.

## Resolution

Set the trust condition to the immutable form with a wildcard only on
the trailing segment, which varies by trigger (`pull_request`,
`ref:refs/heads/main`, `ref:refs/tags/*`).

The numeric ids are permanent and survive renames. That is the purpose
of the format: the old `owner/name` form could be hijacked by deleting a
repo and re-registering the name.

## How it was diagnosed

The CI log contained neither the trust policy nor the token claims, so
no amount of log analysis could resolve it. The diagnosis required
fetching both sides:

    aws iam get-role --role-name devgen-ci \
      --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'

and decoding the live token in a workflow step:

    curl -sSf -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com"

## Lessons

- Log analysis has a hard ceiling. When a log omits the values being
  compared, no model can diagnose it. This is the case for live state
  access (MCP) rather than better retrieval.
- A variable whose format matters needs a `validation` block. The
  description said "owner/name" and nothing enforced it.
- Keep the OIDC claim-decoding step available. It turns an opaque auth
  failure into a one-line comparison.