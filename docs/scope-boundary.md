# Why devgen does not diagnose CI failures

Add to `docs/design.md`.

---

## Scope: what this tool deliberately does not cover

devgen diagnoses failures from CloudWatch log sources. It does **not** diagnose
GitHub Actions failures, and that boundary is deliberate rather than unfinished.

The tool earns its place through three things: governance over sensitive data,
correlation across sources no single vendor spans, and grounding in this
organisation's own incident history. CI logs score poorly on all three.

**They are not sensitive.** Build output contains dependency resolution, test
names, and compiler errors — not customer records. The redaction layer, the
Guardrail, and the audit trail solve a problem that is not acute here, so the
main differentiator contributes nothing.

**They are single-source and already owned.** CI logs live in GitHub, produced
by GitHub, alongside the diff and the pull request that caused them. There is no
correlation problem to solve, and GitHub Copilot has strictly more context than
devgen could: it sees the changed files, the PR discussion, and the repository
history. A tool receiving only piped log text would produce worse answers.

**The most common failure class is the one it cannot diagnose.** Authentication
failures are among the most frequent CI errors, and devgen requires AWS
credentials to run. When `configure-aws-credentials` fails, a devgen-based
diagnosis job cannot obtain credentials either. The tool is structurally unable
to explain the error most likely to need explaining.

A fourth, smaller problem: a diagnosis job running inside the same workflow run
as the failure it is diagnosing may find that GitHub has not yet finalised those
logs.

### Where the value actually is

| Source | Covered | Why |
|---|---|---|
| CloudWatch log groups | Yes | May contain customer data; no vendor spans them all |
| EKS, ECS, RDS, ALB, CloudTrail | Yes | One account-level filter, no per-source wiring |
| Terraform plan and apply output | Yes | Genuinely underserved by existing tools |
| GitHub Actions | No | Copilot has more context and no auth dependency |
| Kubernetes cluster state alone | Partly | k8sgpt is better at this in isolation; devgen adds cross-source correlation |

### The position, stated plainly

Use GitHub Copilot for CI failures. Use k8sgpt if the problem is confined to a
Kubernetes cluster. Use devgen where log data is sensitive, where a failure
spans several AWS services, or where the answer lies in a past incident that no
vendor has indexed.

A tool applied everywhere is harder to defend than a tool applied where it
uniquely fits. The decision not to cover CI was made after building a working
prototype of it, not instead of trying.
