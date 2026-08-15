from devgen.redact import redact


def test_removes_aws_key():
    text, count = redact("key is AKIAIOSFODNN7EXAMPLE here")
    assert "AKIAIOSFODNN7EXAMPLE" not in text
    assert count == 1


def test_removes_password():
    text, count = redact("password=hunter2secret")
    assert "hunter2secret" not in text
    assert count == 1


def test_leaves_normal_text_alone():
    text, count = redact("FROM python:3.12-slim")
    assert text == "FROM python:3.12-slim"
    assert count == 0