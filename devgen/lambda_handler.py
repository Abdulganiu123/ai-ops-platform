"""
Lambda entry point for event-triggered diagnosis.

Two ways in:
  - a manual payload naming a log group
  - a CloudWatch Logs subscription filter, which sends matching lines directly

Either way, raw logs are read here, not carried in the request.
"""

import base64
import gzip
import json
import os
import time

import boto3

from devgen import config
from devgen.engine import run
from devgen.providers import get_provider

logs = boto3.client("logs")
sns = boto3.client("sns")

TOPIC_ARN = os.environ["ALERT_TOPIC_ARN"]
DEFAULT_MINUTES = 15
MAX_EVENTS = 200


def fetch_logs(log_group, minutes):
    """Read recent events from a CloudWatch log group."""
    start_ms = int((time.time() - minutes * 60) * 1000)
    resp = logs.filter_log_events(
        logGroupName=log_group,
        startTime=start_ms,
        limit=MAX_EVENTS,
    )
    return "\n".join(e["message"] for e in resp["events"])


def unpack_subscription(event):
    """
    CloudWatch Logs sends subscription data gzipped and base64 encoded.
    Returns (log_group, joined_messages).
    """
    raw = base64.b64decode(event["awslogs"]["data"])
    payload = json.loads(gzip.decompress(raw))
    messages = "\n".join(e["message"] for e in payload["logEvents"])
    return payload["logGroup"], messages


def handler(event, context):
    """Diagnose a failure and notify, unless there is nothing wrong."""
    if "awslogs" in event:
        log_group, text = unpack_subscription(event)
    else:
        log_group = event["log_group"]
        text = fetch_logs(log_group, event.get("minutes", DEFAULT_MINUTES))

    if not text.strip():
        return {"status": "no_logs", "log_group": log_group}

    provider_name, model_id = config.resolve("diagnose")
    provider = get_provider(provider_name, model_id)
    diagnosis = run("diagnose", provider, text)

    # Stay quiet when nothing is wrong, so a broad filter pattern
    # degrades to silence rather than to noise.
    if diagnosis.strip().upper().startswith("VERDICT: NO FAILURE"):
        return {"status": "no_failure", "log_group": log_group}

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject=f"devgen: {log_group}"[:100],
        Message=diagnosis,
    )
    return {"status": "notified", "log_group": log_group}