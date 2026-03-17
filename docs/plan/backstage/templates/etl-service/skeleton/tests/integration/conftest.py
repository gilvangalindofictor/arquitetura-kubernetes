"""Fixtures de integração — requer dependências reais."""
import os
import pytest


@pytest.fixture(scope="session")
def etl_test_mode():
    """Garante que testes de integração rodam em test mode."""
    return os.getenv("ETL_TEST_MODE", "false").lower() == "true"
