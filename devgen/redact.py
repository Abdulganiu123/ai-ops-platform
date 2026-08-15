"""
Local credential scrub.

Bedrock Guardrails handles PII server-side and is configured in Terraform.
This file covers only what Guardrails cannot: credentials that must never
leave this machine, because Guardrails redacts after the data reaches AWS.

Keep this list short.
"""

import re

PATTERNS = {
    "AWS_KEY": r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b",
    "PRIVATE_KEY": r"-----BEGIN[ A-Z]*PRIVATE KEY-----[\s\S]*?-----END[ A-Z]*PRIVATE KEY-----",
    "TOKEN": r"\bghp_[A-Za-z0-9]{36,}\b|\bxox[baprs]-[A-Za-z0-9-]{10,}\b",
    "SECRET": r"(?i)\b(?:password|secret|token|api[_-]?key)\s*[:=]\s*\S+",
    "EMAIL": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b",
}


def redact(text):
    """Remove credentials. Returns (clean_text, how_many_were_removed)."""
    if not text:
        return "", 0

    removed = 0
    for label, pattern in PATTERNS.items():
        text, found = re.subn(pattern, f"[REDACTED_{label}]", text)
        removed += found

    return text, removed