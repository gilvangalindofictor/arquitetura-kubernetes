"""Configurações do ETL ${{ values.name }} via Pydantic Settings."""
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Configurações carregadas de variáveis de ambiente."""

    # Ambiente
    app_env: str = "staging"
    log_level: str = "INFO"
    log_format: str = "json"

    # Banco de dados
{%- if values.databaseEnabled %}
    database_url: str
    database_password: str
    database_host: str = ""
    database_port: int = 5432
    database_name: str = ""
    database_user: str = ""
{%- endif %}

    # Redis
{%- if values.redisEnabled %}
    redis_url: str
    redis_password: str
    redis_host: str = ""
    redis_port: int = 6379
{%- endif %}

    # Keycloak
{%- if values.keycloakEnabled %}
    keycloak_client_secret: str
    keycloak_admin_password: str
    keycloak_realm: str = ""
    keycloak_auth_server_url: str = ""
    keycloak_client_id: str = ""
{%- endif %}

    # ETL
    etl_test_mode: bool = False
    etl_test_limit_records: int = 100
    etl_test_limit_pages: int = 3
    etl_worker_concurrency: int = 4
    etl_batch_size: int = 100

    # Observabilidade
    metrics_enabled: bool = True
    metrics_port: int = 9090
    metrics_path: str = "/metrics"
    otel_exporter_otlp_endpoint: str = ""
    otel_service_name: str = "${{ values.name }}"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


settings = Settings()
