"""
The engine. Every request goes through here, in the same order:
load the prompt template, scrub secrets, call the model, write the audit log.
"""

from pathlib import Path

from devgen import audit
from devgen.redact import redact

PROMPT_DIR = Path(__file__).parent / "prompts"


def load_prompt(name):
    """Read prompts/<name>.txt and return the text inside it."""
    path = PROMPT_DIR / f"{name}.txt"
    return path.read_text()


def run(command, provider, user_input):
    """Handle one request: load prompt, redact, call model, audit."""
    system_prompt = load_prompt(command)
    clean_input, removed = redact(user_input)

    try:
        response = provider.generate(prompt=clean_input, system=system_prompt)
    except Exception:
        # A blocked or failed call is the most important thing to log.
        audit.record(
            command=command,
            model_id=provider.model_id,
            input_tokens=0,
            output_tokens=0,
            redactions=removed,
            status="error",
        )
        raise

    audit.record(
        command=command,
        model_id=response.model_id,
        input_tokens=response.input_tokens,
        output_tokens=response.output_tokens,
        redactions=removed,
    )

    return response.text