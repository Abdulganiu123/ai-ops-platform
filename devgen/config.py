"""
Reads models.yaml.

Engineers choose a tier ("fast", "best"). This file turns a tier into the
actual model id or inference profile ARN, and looks up pricing.
"""

import os
from pathlib import Path

import yaml

CONFIG_FILE = Path(__file__).parent / "models.yaml"

with CONFIG_FILE.open() as f:
    _CONFIG = yaml.safe_load(f)


def tier_for_command(command):
    """Which tier a command uses when the engineer does not pick one."""
    return _CONFIG["command_tiers"].get(command, _CONFIG["fallback_tier"])


def resolve(command, tier=None, model=None):
    """
    Work out which model to actually call.

    Priority: explicit --model, then --tier, then the command's default tier.
    """
    if model:
        return model

    chosen_tier = tier or os.environ.get("DEVGEN_TIER") or tier_for_command(command)

    if chosen_tier not in _CONFIG["tiers"]:
        valid = ", ".join(_CONFIG["tiers"])
        raise ValueError(f"Unknown tier '{chosen_tier}'. Valid tiers: {valid}")

    return _CONFIG["tiers"][chosen_tier]["model"]


def all_tiers():
    """Every tier, as (name, model, description) tuples."""
    return [
        (name, entry["model"], entry["description"])
        for name, entry in _CONFIG["tiers"].items()
    ]


def price(model_id):
    """(input_rate, output_rate) per million tokens, or None if not listed."""
    base_model = model_id.removeprefix("us.")
    entry = _CONFIG["pricing"].get(base_model)

    if entry is None:
        return None

    return entry["input_per_million"], entry["output_per_million"]