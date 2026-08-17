# Design decisions

## Tiers, not model ids

Engineers express intent (`fast`, `best`); the platform team owns what backs it.
Swapping the model behind a tier is a one-line reviewed change in
`devgen/models.yaml` that reaches everyone at once.

This also makes model deprecation — which happens on a schedule you do not
control — a config edit rather than a hunt through code.

## models.yaml is the single source of truth

Terraform reads the same file the application reads, via `yamldecode`. The IAM
invoke policy is derived from the tiers defined there, so adding a model to the
config and running `terraform apply` is what authorises it.

Two hand-maintained lists that must agree is a defect waiting to happen.

## Resource ids live in SSM, never in code

Terraform writes the Guardrail id to Parameter Store; the app reads it at
startup. Destroy and recreate the infrastructure and the tool picks up the new
id with no code change and no redeploy.

The same pattern will carry Phase 3's knowledge base id and Phase 4's MCP
endpoints.

## Provider abstraction from day one

`providers.py` is the only module that imports `boto3`. Everything else calls
`provider.generate()`. Adding an Ollama provider for sensitive log analysis in
Phase 2 is a new subclass, not a refactor.

## Flat Terraform, not modules

This deploys once, into one account. Wrapping a single-use configuration in a
module adds indirection for no benefit. Modules become right when a second
environment needs the same shape.

## Every tool version is pinned

Python, Terraform, and Checkov versions live in the workflow's `env` block, and
the Checkov CLI is invoked directly rather than through the marketplace action.

This came from experience: a local Checkov of 3.3.10 and a CI Checkov of 3.3.11
disagreed silently — the older version simply did not contain five of the checks,
so it reported a clean scan while CI failed. Anything that can change without a
corresponding commit will eventually break a build nobody caused.

## CI permissions were derived from failures, not guessed

The CI role started with `ReadOnlyAccess` and gained exactly the actions that
`terraform plan` actually demanded, scoped to specific ARNs. `ReadOnlyAccess`
turns out to omit some Bedrock read actions, which only surfaced by running it.

## Testing the central guarantee

The claim that credentials never reach the model cannot be tested against real
Bedrock — once the request leaves the machine, there is no way to inspect what
was in it.

`tests/test_engine.py` substitutes a fake provider that records what it was
handed:

```python
def test_secrets_never_reach_the_model():
    provider = FakeProvider()
    run("dockerfile", provider, "python AKIAIOSFODNN7EXAMPLE")
    assert "AKIAIOSFODNN7EXAMPLE" not in provider.received
```

Its real value is as a regression test. If someone later restructures
`engine.run()` and moves redaction after the model call, everything still
appears to work and every other test still passes. This one fails immediately.

Verified by breaking it on purpose: replacing the `redact()` call with a
pass-through makes this test fail while the three `redact.py` unit tests keep
passing. Redaction's own tests cannot detect that redaction is no longer being
*called*.

---

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

---

# A note on AI-assisted debugging

Two failures during this build were diagnosed with AI assistance. In both cases
the suggestion correctly identified *where* to look and proposed a fix that would
have quietly widened the security posture — a wildcard resource ARN in place of a
scoped one, and a trust condition that would have broken pull-request runs.

The pattern is consistent: strong at locating the problem, weak at choosing the
constraint. That is not an argument against the tooling. It is the argument for
the human review step this repository is built around.
