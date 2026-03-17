"""Testes unitários dos extractors."""
import pytest
from etl_service.extractors.base import BaseExtractor
from typing import Any, Iterator


class DummyExtractor(BaseExtractor):
    """Extractor dummy para testes."""

    def extract(self) -> Iterator[dict[str, Any]]:
        yield {"id": 1, "data": "test"}

    def validate(self) -> bool:
        return True


def test_base_extractor_interface():
    """Verifica que a interface base funciona."""
    extractor = DummyExtractor(config={})
    assert extractor.validate() is True
    records = list(extractor.extract())
    assert len(records) == 1
    assert records[0]["id"] == 1


def test_base_extractor_requires_config():
    """Verifica que o extractor recebe config."""
    config = {"timeout": 30, "max_retries": 3}
    extractor = DummyExtractor(config=config)
    assert extractor.config == config
