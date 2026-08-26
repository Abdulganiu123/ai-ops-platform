# Known limitations

**Diagnosis quality has a real ceiling.** Given a Terraform state-lock failure,
the tool correctly identified the verdict and cause, then recommended checking
bucket permissions — wrong, because `PreconditionFailed` is not a permissions
error. Treat output as a fast first draft. The prompt now requires quoting the
specific error line and stating a confidence level, which is prompt engineering
driven by an observed failure.

**No institutional memory yet.** The tool reasons from training data and
whatever you pipe in. It cannot answer "have we seen this before?" — that is
Phase 3.

**Log analysis fails when the log omits the relevant values.** See
[the OIDC incident](incidents/2026-08-oidc-trust-mismatch.md): an authentication
failure no amount of log analysis could resolve, because neither side of the
compared values appeared in the log. That class of problem needs live state
access, not better retrieval.

**No VPC endpoint.** PrivateLink for `bedrock-runtime` only affects traffic
originating inside the VPC. While `devgen` runs from a laptop or a GitHub-hosted
runner it would cost roughly $15/month and change nothing. It becomes relevant
in Phase 2, when the diagnose path runs as a Lambda inside the VPC.

**The state bucket is managed by the state that lives inside it.** Functional,
but `terraform destroy` cannot cleanly sequence its own state store. The standard
fix is a separate bootstrap configuration; noted rather than done.

**`ReadOnlyAccess` on the CI role is broader than ideal.** `terraform plan`
refreshes every managed resource, so enumerating each read action is brittle.
The role can only read, and `apply` remains manual.

**Self-reported confidence is weakly calibrated.** Given two lines of
`OOMKilled` output, both a 1B local model and Claude Haiku 4.5 answered
`CONFIDENCE: high` — but the log cannot distinguish an application memory
leak from an undersized limit, so neither had grounds for it. The smaller
model also gave Docker syntax for a Kubernetes context.

The `CONFIDENCE` field is still worth having; it just reads as a hint about
tone rather than a signal to act on. Treating it as a gate — auto-remediate
when confidence is high — would be unsafe.

## CI failures use the CLI, not the Lambda

GitHub Actions logs live in GitHub, not CloudWatch, so the pointer approach
cannot reach them. CI calls `devgen diagnose` directly from the runner, which
already has an IAM role. Shipping CI logs into CloudWatch purely to reuse the
Lambda would be building a pipeline to fit a tool.

## A note on AI-assisted debugging

Two failures during this build were diagnosed with AI assistance. In both cases
the suggestion correctly identified *where* to look and proposed a fix that would
have quietly widened the security posture — a wildcard resource ARN in place of a
scoped one, and a trust condition that would have broken pull-request runs.

The pattern is consistent: strong at locating the problem, weak at choosing the
constraint. That is not an argument against the tooling. It is the argument for
the human review step this repository is built around.

---