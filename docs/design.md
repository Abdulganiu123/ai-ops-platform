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

---

## Two entry points, one pipeline

The CLI reads from a pipe; the Lambda reads from an event. Both call the same
`engine.run()`, so redaction, prompts, and audit behave identically. Adding the
Lambda required no change to the pipeline itself.


## Guardrails against runaway cost

An account-level subscription filter watches every log group in the account.
Three controls bound the blast radius: a narrow filter pattern so healthy
operation costs nothing, `reserved_concurrent_executions = 2` so a log storm
cannot spawn parallel invocations, and an exclusion list so the delivery path
cannot trigger itself.

## Bootstrap tier is separate

`terraform/bootstrap/` holds the state bucket and the CI role, applied once by
a human with local state. The application configuration in `terraform/` holds
everything else and is destroyed and recreated freely.

The CI role is not application infrastructure — it is the credential that lets
automation exist. Keeping it in a configuration destroyed nightly meant routine
teardown silently broke the pipeline. The application config now looks the role
up with a `data` block and attaches only the policies it owns, so `destroy`
removes the attachment and never the role.

Both the bucket and the role carry `prevent_destroy`.