# devgen fabricated a failure from healthy logs

**Date:** 2026-08-21
**Impact:** One incorrect diagnosis emailed from the Lambda. No production impact.
**Severity:** Low impact, high significance — the failure mode is silent.

## What happened

The first end-to-end test of the `diagnose` Lambda was invoked against the
`/aws/bedrock/devgen` log group:

    aws lambda invoke --function-name devgen-diagnose \
      --payload '{"log_group":"/aws/bedrock/devgen","minutes":60}' ...

The function executed successfully, produced an audit record, and emailed a
diagnosis:

    VERDICT: INFRA
    EVIDENCE: "Permissions are correctly set for Amazon Bedrock logs."
    CAUSE: The log indicates that permissions for Amazon Bedrock logs are
           correctly set, suggesting that the issue is not related to
           permissions but rather to some other environmental or dependency
           failure.
    NEXT STEP: Investigate network connectivity and the status of Amazon
               Bedrock services.
    CONFIDENCE: medium

There was no failure. That log group holds Bedrock model invocation metadata —
a record of successful API calls. Nothing in it describes an error.

Note the internal contradiction: the response states permissions are correct,
then concludes something else must have failed. It reasoned from the absence of
a problem to the existence of one.

## Root cause

`devgen/prompts/diagnose.txt` offered three verdicts: `REAL BUG`, `FLAKY`, and
`INFRA`. All three are failure classifications. The prompt provided no way to
report that nothing was wrong, so the model was structurally required to choose
a failure type regardless of input.

The guard in `cli.py` only rejects *empty* input:

    if not logs.strip():
        raise click.ClickException("No logs given.")

Healthy logs are not empty, so they passed straight through.

This is a prompt design defect, not a model defect. Given a forced choice among
three failure types, producing a failure type is correct behaviour.

## Resolution

Added a fourth verdict and an explicit instruction to use it:

    - NO FAILURE: the log shows normal operation, nothing to diagnose

    - If the log contains no error, exception, or failure, answer
      VERDICT: NO FAILURE and stop. Do not invent a problem.

## Why this matters more than the impact suggests

Every other failure in this project announced itself — a stack trace, a non-zero
exit code, a denied API call. This one returned HTTP 200, wrote a clean audit
record, and delivered a confident, well-formatted, entirely fabricated answer.

The planned trigger for this function is a CloudWatch Logs subscription filter.
Had the filter pattern been slightly too broad, the function would have emailed
plausible diagnoses of non-existent problems on a schedule, and the only signal
would have been engineers gradually learning to ignore it.

## Lessons

- **A classifier needs a null option.** Any prompt offering a fixed set of
  categories must include one meaning "none of these apply", or it will always
  return a category.
- **Test the negative case.** The tool was tested against real failures and
  against empty input. It was never tested against a healthy log, which is the
  most common input an automatic trigger will ever see.
- **Confident output is not evidence of correct output.** The response carried
  `CONFIDENCE: medium` while being entirely fabricated. Self-reported confidence
  from a model is weakly calibrated and must not be used as a gate for
  automated action.
- **Silent failures deserve more attention than loud ones.** Everything about
  this run looked healthy from the outside.

## Follow-up

- [ ] Add a test asserting `NO FAILURE` is returned for a log with no errors
- [ ] Keep the subscription filter pattern narrow (`ERROR`, `Exception`,
      `FATAL`) rather than streaming an entire log group
- [ ] Consider having the Lambda suppress notification entirely when the
      verdict is `NO FAILURE`, so a broad filter degrades to silence rather
      than to noise
