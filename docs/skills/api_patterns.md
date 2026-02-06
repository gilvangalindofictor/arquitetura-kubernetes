# Skill: API Patterns

## Aplicabilidade

**Nota**: Este projeto é IaC/plataforma. APIs são internas (Kubernetes API, GitLab API, Harbor API, etc.). Este skill se aplica a futuras aplicações na plataforma.

## Padrões REST

**Nomenclatura**:
- Recursos: plural (`/users`, `/projects`)
- IDs: `/users/{id}`
- Ações: verbos HTTP (GET, POST, PUT, DELETE)

**Status Codes**:
- 200: Success
- 201: Created
- 204: No Content (delete)
- 400: Bad Request (validation)
- 401: Unauthorized
- 403: Forbidden
- 404: Not Found
- 500: Internal Server Error

**Pagination**:
```
GET /users?page=1&limit=20
Response:
{
  "data": [...],
  "meta": {
    "page": 1,
    "limit": 20,
    "total": 150
  }
}
```

## Authentication & Authorization

**Keycloak (OAuth 2.0 / OIDC)**:
- Token-based authentication
- JWT tokens
- Refresh tokens
- RBAC via Keycloak roles

**API Gateway (Kong - futuro)**:
- Rate limiting
- Authentication plugins
- Request/response transformation

## Regras Invioláveis

1. **NUNCA endpoint sem autenticação** (exceto explicitamente público)
2. **NUNCA expor stack trace em produção**
3. **NUNCA resposta sem tratamento de erro padronizado**

---

_Skill v1.0 - Para futuras aplicações na plataforma_
