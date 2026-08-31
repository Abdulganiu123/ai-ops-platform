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


## The filter pattern bounds what the tool can see

Diagnosis is triggered by a CloudWatch subscription filter matching `ERROR`,
`Exception`, or `FATAL`. Failures that do not use those words are invisible to
it, and many Kubernetes failures do not: `CrashLoopBackOff`, `OOMKilled`,
`ImagePullBackOff`, `FailedScheduling`, `Evicted`, and readiness probe failures
all describe real outages without containing any of the three keywords.

This was found by testing a crash-looping pod log against the filter. It
produced no invocation, which was correct behaviour and the wrong outcome.

Widening the pattern helps but does not solve it — the list of failure phrases
is open-ended, and every added keyword increases invocation cost.

The structural fix is to trigger from signals rather than text. A CloudWatch
alarm on restart count or error rate fires because a metric moved, independent
of log wording, and the same function can then fetch and diagnose the relevant
logs. Keyword matching is a reasonable first pass; it is not a monitoring
strategy.

## The automated path is CloudWatch-only

`lambda_handler.py` fetches logs from CloudWatch. Organisations shipping logs
to Elasticsearch, Datadog, or Splunk have no automated path — the subscription
filter that triggers diagnosis is a CloudWatch feature.

The CLI is unaffected. Anything that can print logs to stdout can pipe into
`devgen diagnose`, which is the advantage of a pipeline tool over a service:
no per-source connector is required.

Extending the automated path would mean one fetcher per source behind a common
interface, with the triggering event naming which to use — the same shape as
the provider abstraction. Not built, because there is one log source here and
no second one to test against.

---