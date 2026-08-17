# Security model

Four controls, each doing a different job. They are deliberately not redundant.

## 1 · Local credential scrub

`devgen/redact.py` — four regex patterns covering AWS keys, private keys,
GitHub and Slack tokens, and assignment-shaped secrets (`password=`,
`api_key:`). Runs before the network call, so these values never leave the
machine.

Deliberately small. Bedrock Guardrails handles PII far better — it is ML-based
and context-aware, where regex is not. This file covers only the gap Guardrails
structurally cannot: Guardrails redacts *after* the payload reaches AWS.

Regex is good at credentials, which have fixed prefixes and lengths, and bad at
personal data. A phone pattern misfires on version strings; an SSN pattern
matches any nine-digit correlation id. Over-redaction breaks the tool — a
diagnosis is worthless if every identifier in the log has been mangled.

Measured against real `terraform plan` output: 4 matches across 78 lines, all
email addresses, zero false positives. Account ids, ARNs, bucket names, and
resource types were left intact.

## 2 · Bedrock Guardrail

`terraform/guardrail.tf` — a dozen PII entity types plus content filters
including `PROMPT_ATTACK`.

The action split is the design decision worth noting:

- **`BLOCK`** for credentials (AWS keys, passwords). If one arrives here, layer 1
  failed and the right response is a loud stop, not a quiet mask.
- **`ANONYMIZE`** for personal data (names, emails, addresses, IPs). These appear
  incidentally in logs and should not halt a diagnosis.

`PROMPT_ATTACK` matters specifically for a log-analysis tool. An attacker can
submit a form field containing injection text, which then lands in your logs.
When an engineer later pipes that log through `devgen diagnose`, the tool is
feeding attacker-controlled text to a model.

## 3 · IAM least privilege

`terraform/iam.tf` — the invoke policy is derived from `devgen/models.yaml`
using `yamldecode`. Point a tier at an unapproved model and the call fails with
`AccessDeniedException`. Authorisation requires a Terraform change, which
requires a pull request.

CI authenticates via GitHub OIDC. No AWS access keys are stored anywhere; the
runner receives a token valid for minutes, scoped by a trust condition to this
repository's immutable numeric id.

## 4 · Audit trail

Two records, deliberately:

| | Bedrock invocation log | `audit.py` |
|---|---|---|
| Written by | AWS | The application |
| Model and token counts | Yes | Yes |
| Which subcommand ran | No | Yes |
| Which engineer ran it | No | Yes |
| How many redactions fired | No | Yes |
| Works for non-Bedrock providers | No | Yes |

The AWS-side record is tamper-resistant and outside the application's control,
which is what an auditor wants. The application-side record carries business
context. Overlapping token counts let you cross-check one against the other.

## What is deliberately not logged

`text_data_delivery_enabled = false` on Bedrock invocation logging, and
`audit.py` stores metadata only — never the prompt or the response.

If a credential slipped past layer 1, the Guardrail would catch it before the
model saw it. But with content logging enabled, Bedrock would *also* write the
original pre-guardrail prompt into CloudWatch. You would have protected the
model and leaked into your own logging system. Metadata only means that copy is
never created.

## Security scanning

Checkov runs on every push, pinned to a specific version. Findings were triaged
rather than blanket-suppressed:

| Finding | Decision |
|---|---|
| CKV_AWS_158 — log group not KMS encrypted | **Fixed.** Customer-managed key with rotation, scoped by encryption context |
| CKV2_AWS_61 — no S3 lifecycle rule | **Fixed.** Versioning without expiry accumulates state versions indefinitely |
| CKV_AWS_18 — no S3 access logging | Skipped. Requires a second bucket that would fail the same checks |
| CKV_AWS_144 — no cross-region replication | Skipped. DR beyond scope for a single-account project |
| CKV_AWS_145 — S3 not KMS encrypted | Skipped. SSE-S3 is enabled; state holds no customer data |
| CKV2_AWS_62 — no event notifications | Skipped. Requires an SNS/SQS/Lambda target |
| CKV2_AWS_34 — SSM parameter not SecureString | Skipped. A Guardrail id is an identifier, not a credential |

Every skip is an inline `# checkov:skip=` comment carrying its reason, so the
decision sits next to the code it applies to and appears in the CI output.

## Threat model boundaries

**Not covered:** traffic from a laptop to AWS traverses the public internet.
TLS protects it from passive interception, but an enterprise TLS-inspection
proxy would see the payload in plaintext. Local redaction limits what is exposed
at that point; eliminating the hop entirely requires Direct Connect or a VPN,
which is out of scope.

**Not covered:** in the Phase 2 Lambda design, the hop from a log source to the
function. The mitigation is architectural rather than another redaction layer —
callers pass a pointer (log group, job id) and the function fetches the logs
itself using its own IAM role, so the raw payload never crosses a new boundary.
