from devgen.engine import run
from devgen.providers import LLMResponse


class FakeProvider:
    """Stands in for Bedrock so tests never call AWS."""

    model_id = "fake-model"

    def __init__(self):
        self.received = None

    def generate(self, prompt, system="", max_tokens=1024):
        self.received = prompt
        return LLMResponse(
            text="ok",
            model_id=self.model_id,
            input_tokens=1,
            output_tokens=1,
        )


def test_secrets_never_reach_the_model():
    provider = FakeProvider()
    run("dockerfile", provider, "python AKIAIOSFODNN7EXAMPLE")
    assert "AKIAIOSFODNN7EXAMPLE" not in provider.received