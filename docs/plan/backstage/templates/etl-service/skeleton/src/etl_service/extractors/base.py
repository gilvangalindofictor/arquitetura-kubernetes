"""Base Extractor — interface para todos os extractors do ETL."""
from abc import ABC, abstractmethod
from typing import Any, Iterator


class BaseExtractor(ABC):
    """Interface base para extractors do ETL ${{ values.name }}.

    Cada originadora deve ter seu próprio extractor que herda desta classe.
    """

    def __init__(self, config: dict[str, Any]) -> None:
        self.config = config

    @abstractmethod
    def extract(self) -> Iterator[dict[str, Any]]:
        """Itera sobre os registros da origem de dados.

        Yields:
            dict com os dados brutos de cada registro
        """
        ...

    @abstractmethod
    def validate(self) -> bool:
        """Valida a conexão/configuração antes de extrair.

        Returns:
            True se a conexão está OK
        """
        ...
