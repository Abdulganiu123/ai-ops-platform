"""
Model provider abstraction.

This is the ONLY module in devgen that talks to a model API directly.
Everything else calls provider.generate() and stays backend-agnostic.
"""

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

GUARDRAIL_PARAM = "/devgen/guardrail"

HINTS = {
    "AccessDeniedException": (
        "Either the model is not enabled in Bedrock console -> Model access, "
        "or the caller's IAM policy does not allow bedrock:InvokeModel on it."
    ),
    "ValidationException": "Check the model id in devgen/models.yaml.",
}


@dataclass
class LLMResponse:
    """Uniform return shape from any provider."""
    text: str
    model_id: str
    input_tokens: int
    output_tokens: int


class LLMProvider(ABC):
    """Contract every provider must satisfy."""
    @abstractmethod
    def generate(self, prompt, system="", max_tokens=1024):
        ...


class BedrockProvider(LLMProvider):
    """Calls Bedrock via the Converse API with the guardrail applied."""

    def __init__(self, model_id, region="us-east-1"):
        self.model_id = model_id
        self._client = boto3.client(
            "bedrock-runtime",
            region_name=region,
            config=Config(read_timeout=300, retries={"max_attempts": 3}),
        )
        # Terraform writes the guardrail id to SSM. No id lives in code.
        ssm = boto3.client("ssm", region_name=region)
        try:
            param = ssm.get_parameter(Name=GUARDRAIL_PARAM)
        except ClientError as exc:
            raise RuntimeError(
                f"No guardrail found at {GUARDRAIL_PARAM} in {region}. "
                "Run 'terraform apply' in the terraform folder."
            ) from exc
        self._guardrail = json.loads(param["Parameter"]["Value"])

    def generate(self, prompt, system="", max_tokens=1024):
        kwargs = {
            "modelId": self.model_id,
            "messages": [{"role": "user", "content": [{"text": prompt}]}],
            "inferenceConfig": {"maxTokens": max_tokens, "temperature": 0.2},
            "guardrailConfig": {
                "guardrailIdentifier": self._guardrail["id"],
                "guardrailVersion": self._guardrail["version"],
            },
        }
        # System prompt carries house standards; kept separate from user input.
        if system:
            kwargs["system"] = [{"text": system}]

        try:
            resp = self._client.converse(**kwargs)
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            raise RuntimeError(f"{code}. {HINTS.get(code, '')}") from exc

        if resp.get("stopReason") == "guardrail_intervened":
            raise RuntimeError("Blocked by the devgen guardrail.")

        return LLMResponse(
            text=resp["output"]["message"]["content"][0]["text"],
            model_id=self.model_id,
            input_tokens=resp["usage"]["inputTokens"],
            output_tokens=resp["usage"]["outputTokens"],
        )   