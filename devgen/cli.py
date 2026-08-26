"""
Command line interface.

Reads terminal arguments and passes them to the engine.
No business logic lives here.
"""

import click

from devgen import config
from devgen.engine import run
from devgen.providers import get_provider
import subprocess
import sys

# Logs can be enormous and we pay per token. Keep the tail - errors live there.
MAX_LOG_CHARS = 40000

CONTEXT_SETTINGS = {
    "help_option_names": ["-h", "--help"],
    "max_content_width": 100,
}


def execute(command, user_input, tier, model, debug):
    """Resolve the provider, run the request, return the text."""
    try:
        provider_name, model_id = config.resolve(command, tier, model)
        provider = get_provider(provider_name, model_id)
        return run(command, provider, user_input)
    except Exception as exc:
        if debug:
            raise
        raise click.ClickException(str(exc)) from exc


@click.group(context_settings=CONTEXT_SETTINGS, no_args_is_help=True)
@click.version_option(package_name="devgen")
def cli():
    """
    devgen - generate and review DevOps files using AI.

    Every command scrubs credentials before calling the model and writes
    an audit record to ~/.devgen/audit.log.

    \b
    Examples:
      devgen dockerfile --lang python
      devgen dockerfile --lang go --tier best
      devgen tiers

    You do not need to know model ids. Pick a tier - 'fast', 'balanced'
    or 'best' - and the platform team's config decides what runs.
    """


@cli.command()
@click.option(
    "--lang",
    required=True,
    metavar="LANGUAGE",
    help="Programming language, e.g. python, go, node, java.",
)
@click.option(
    "--tier",
    metavar="TIER",
    help="Quality tier: fast, balanced or best. Run 'devgen tiers' to see them.",
)
@click.option(
    "--model",
    metavar="MODEL_ID",
    help="Escape hatch: call a specific model id or profile ARN directly.",
)
@click.option(
    "--debug",
    is_flag=True,
    help="Show the full Python traceback instead of a short error.",
)
def dockerfile(lang, tier, model, debug):
    """
    Generate a Dockerfile for a language.

    Applies the house rules in devgen/prompts/dockerfile.txt - pinned base
    image, non-root user, dependencies installed before app code.

    \b
    Examples:
      devgen dockerfile --lang python
      devgen dockerfile --lang go --tier best > Dockerfile
    """
    click.echo(execute("dockerfile", lang, tier, model, debug))


@cli.command()
def tiers():
    """Show the available quality tiers."""
    for name, provider, model_id, description in config.all_tiers():
        click.echo(f"{name:10} {description}")
        click.echo(f"{'':10} -> {provider}: {model_id}")


if __name__ == "__main__":
    cli()

@cli.command()
@click.option("--pod", metavar="POD", help="Kubernetes pod name. Runs kubectl logs for you.")
@click.option("--lines", default=200, show_default=True, help="How many log lines to read.")
@click.option("--tier", metavar="TIER", help="Quality tier. Run 'devgen tiers' to see them.")
@click.option("--model", metavar="MODEL_ID", help="Escape hatch: a specific model id.")
@click.option("--debug", is_flag=True, help="Show the full Python traceback.")
def diagnose(pod, lines, tier, model, debug):
    """
    Explain why something failed.

    \b
    Examples:
      kubectl logs checkout-7d9f | devgen diagnose
      devgen diagnose --pod checkout-7d9f
      terraform apply 2>&1 | devgen diagnose
    """
    if pod:
        result = subprocess.run(
            ["kubectl", "logs", f"--tail={lines}", pod],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            raise click.ClickException(result.stderr.strip())
        logs = result.stdout
    else:
        logs = sys.stdin.read()

    if not logs.strip():
        raise click.ClickException("No logs given. Pipe logs in or use --pod.")

    click.echo(execute("diagnose", logs[-MAX_LOG_CHARS:], tier, model, debug))    