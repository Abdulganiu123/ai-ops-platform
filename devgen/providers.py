"""
Model provider abstraction.

This is the ONLY module in devgen that talks to a model API directly.
Everything else calls provider.generate() and stays backend-agnostic.
"""

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass

try:
    import ollama
except ImportError:
    ollama = None

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
            error = exc.response["Error"]
            code = error["Code"]
            message = error.get("Message", "")
            raise RuntimeError(f"{code}: {message} {HINTS.get(code, '')}".strip()) from exc

        if resp.get("stopReason") == "guardrail_intervened":
            raise RuntimeError("Blocked by the devgen guardrail.")

        return LLMResponse(
            text=resp["output"]["message"]["content"][0]["text"],
            model_id=self.model_id,
            input_tokens=resp["usage"]["inputTokens"],
            output_tokens=resp["usage"]["outputTokens"],
        )   

class OllamaProvider(LLMProvider):
    """Calls a model running locally. Nothing leaves the machine."""

    def __init__(self, model_id, host="http://localhost:11434"):
        if ollama is None:
            raise RuntimeError(
                "The local tier needs the ollama package: pip install 'devgen[local]'"
            )
        self.model_id = model_id
        self.host = host
        self._client = ollama.Client(host=host)

    def generate(self, prompt, system="", max_tokens=1024):
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        try:
            resp = self._client.chat(
                model=self.model_id,
                messages=messages,
                options={"temperature": 0.2, "num_predict": max_tokens},
            )
        except Exception as exc:
            raise RuntimeError(
                f"Ollama call failed at {self.host}: {exc}. "
                f"Check Ollama is running (ollama serve - install: https://ollama.com) "
                f"and that '{self.model_id}' is pulled (ollama pull {self.model_id})."
            ) from exc

        return LLMResponse(
            text=resp["message"]["content"],
            model_id=self.model_id,
            input_tokens=resp.get("prompt_eval_count", 0),
            output_tokens=resp.get("eval_count", 0),
        )

def get_provider(provider_name, model_id):
    """Build the right provider for a name from models.yaml."""
    if provider_name == "ollama":
        return OllamaProvider(model_id)
    if provider_name == "bedrock":
        return BedrockProvider(model_id)
    raise ValueError(f"Unknown provider '{provider_name}' in models.yaml.")