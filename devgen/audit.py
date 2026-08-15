"""
Audit log: one JSON line per model call.

Metadata only - never the prompt or the response. Logging the content
would write sensitive text to a second place and undo the redaction.
"""

import getpass
import json
from datetime import datetime, timezone
from pathlib import Path

from devgen import config

LOG_FILE = Path.home() / ".devgen" / "audit.log"


def estimate_cost(model_id, input_tokens, output_tokens):
    """Rough USD cost of one call. Returns 0.0 if the model has no price listed."""
    rates = config.price(model_id)

    if rates is None:
        return 0.0

    input_rate, output_rate = rates
    cost = (input_tokens / 1_000_000) * input_rate
    cost += (output_tokens / 1_000_000) * output_rate
    return round(cost, 8)


def record(command, model_id, input_tokens, output_tokens, redactions=0, status="success"):
    """Append one line to the audit log. Returns the event so tests can check it."""
    event = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "user": getpass.getuser(),
        "command": command,
        "status": status,
        "model_id": model_id,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "cost_usd": estimate_cost(model_id, input_tokens, output_tokens),
        "redactions": redactions,
    }

    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with LOG_FILE.open("a") as f:
        f.write(json.dumps(event) + "\n")

    return event