# PostgreSQL Provider Configuration
# Connects to the RDS instance created in main.tf
# For local TF runs via port-forward, set postgresql_host_override = "localhost"
provider "postgresql" {
  host            = var.postgresql_host_override != null ? var.postgresql_host_override : aws_db_instance.postgresql.address
  port            = var.postgresql_port_override != null ? var.postgresql_port_override : aws_db_instance.postgresql.port
  username        = aws_db_instance.postgresql.username
  password        = var.master_password_override != null ? var.master_password_override : random_password.master.result
  sslmode         = "require"
  connect_timeout = 15
  superuser       = false
}

# -----------------------------------------------------------------------------
# GitLab Database + User
# -----------------------------------------------------------------------------

resource "random_password" "gitlab_user" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "postgresql_role" "gitlab_user" {
  name     = "gitlab_user"
  login    = true
  password = random_password.gitlab_user.result

  # BACEN BCB 85/2021 Art.6º §1º + LGPD Art.46 — Privilégios mínimos (least-privilege)
  # NOSUPERUSER: impede escalada de privilégios via superuser
  superuser       = false
  create_database = false
  create_role     = false
  replication     = false
  connection_limit = 10 # Limita blast radius em caso de comprometimento da credencial

  depends_on = [aws_db_instance.postgresql]
}

resource "postgresql_database" "gitlab" {
  name              = "gitlab"
  owner             = postgresql_role.gitlab_user.name
  encoding          = "UTF8"
  lc_collate        = "en_US.UTF-8"
  lc_ctype          = "en_US.UTF-8"
  connection_limit  = -1
  allow_connections = true

  depends_on = [postgresql_role.gitlab_user]
}

resource "postgresql_grant" "gitlab_user_database" {
  database    = postgresql_database.gitlab.name
  role        = postgresql_role.gitlab_user.name
  object_type = "database"
  # BACEN BCB 85/2021 Art.6º §1º — Downgrade de ALL para CONNECT+TEMPORARY (database-level)
  # CONNECT: permite conexão ao banco; TEMPORARY: permite tabelas temporárias (requerido por GitLab)
  # Privilégios de tabela/schema permanecem em postgresql_grant.*_schema (object_type="schema")
  privileges = ["CONNECT", "TEMPORARY"]
}

resource "postgresql_grant" "gitlab_user_schema" {
  database    = postgresql_database.gitlab.name
  role        = postgresql_role.gitlab_user.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["ALL"]
}

# -----------------------------------------------------------------------------
# Keycloak Database + User
# -----------------------------------------------------------------------------

resource "random_password" "keycloak_user" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secrets Manager — keycloak_user (fonte única de verdade; ESO lê daqui via aws-sm store)
# FIX: garante que SM sempre reflete a senha atual no RDS — evita drift com Vault
# Ver: docs/logbook/2026-02-19-post-up-investigation.md (STOP-AND-FIX Keycloak)
resource "aws_secretsmanager_secret" "keycloak_user_password" {
  name        = "${var.environment}/postgresql/keycloak-password"
  description = "Keycloak PostgreSQL user password (managed by Terraform — anti-drift)"

  tags = merge(var.common_tags, {
    Name    = "keycloak-postgresql-password"
    Service = "keycloak"
  })

  lifecycle {
    # Evitar recreação se o secret já existia manualmente antes do TF import
    ignore_changes = [name]
  }
}

resource "aws_secretsmanager_secret_version" "keycloak_user_password" {
  secret_id     = aws_secretsmanager_secret.keycloak_user_password.id
  secret_string = random_password.keycloak_user.result
}

resource "postgresql_role" "keycloak_user" {
  name     = "keycloak_user"
  login    = true
  password = random_password.keycloak_user.result

  # BACEN BCB 85/2021 Art.6º §1º + LGPD Art.46 — Privilégios mínimos (least-privilege)
  superuser        = false
  create_database  = false
  create_role      = false
  replication      = false
  connection_limit = 10

  depends_on = [aws_db_instance.postgresql]
}

resource "postgresql_database" "keycloak" {
  name              = "keycloak"
  owner             = postgresql_role.keycloak_user.name
  encoding          = "UTF8"
  lc_collate        = "en_US.UTF-8"
  lc_ctype          = "en_US.UTF-8"
  connection_limit  = -1
  allow_connections = true

  depends_on = [postgresql_role.keycloak_user]
}

resource "postgresql_grant" "keycloak_user_database" {
  database    = postgresql_database.keycloak.name
  role        = postgresql_role.keycloak_user.name
  object_type = "database"
  # BACEN BCB 85/2021 Art.6º §1º — Downgrade de ALL para CONNECT+TEMPORARY (database-level)
  privileges = ["CONNECT", "TEMPORARY"]
}

resource "postgresql_grant" "keycloak_user_schema" {
  database    = postgresql_database.keycloak.name
  role        = postgresql_role.keycloak_user.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["ALL"]
}

# -----------------------------------------------------------------------------
# SonarQube Database + User
# -----------------------------------------------------------------------------

resource "random_password" "sonarqube_user" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

# Secrets Manager — sonarqube_user (fonte única de verdade; ESO lê daqui via aws-sm store)
# FIX: garante que SM sempre reflete a senha atual no RDS — evita drift com Vault
# Ver: docs/logbook/2026-02-19-post-up-investigation.md (AVISO drift SonarQube)
resource "aws_secretsmanager_secret" "sonarqube_user_password" {
  name        = "${var.environment}/postgresql/sonarqube-password"
  description = "SonarQube PostgreSQL user password (managed by Terraform — anti-drift)"

  tags = merge(var.common_tags, {
    Name    = "sonarqube-postgresql-password"
    Service = "sonarqube"
  })

  lifecycle {
    # Evitar recreação se o secret já existia manualmente antes do TF import
    ignore_changes = [name]
  }
}

resource "aws_secretsmanager_secret_version" "sonarqube_user_password" {
  secret_id     = aws_secretsmanager_secret.sonarqube_user_password.id
  secret_string = random_password.sonarqube_user.result
}

resource "postgresql_role" "sonarqube_user" {
  name     = "sonarqube_user"
  login    = true
  password = random_password.sonarqube_user.result

  # BACEN BCB 85/2021 Art.6º §1º + LGPD Art.46 — Privilégios mínimos (least-privilege)
  superuser        = false
  create_database  = false
  create_role      = false
  replication      = false
  connection_limit = 100 # Elevated from 10 (2026-03-24) — SonarQube connection pooling requires higher limit

  depends_on = [aws_db_instance.postgresql]
}

resource "postgresql_database" "sonarqube" {
  name              = "sonarqube"
  owner             = postgresql_role.sonarqube_user.name
  encoding          = "UTF8"
  lc_collate        = "en_US.UTF-8"
  lc_ctype          = "en_US.UTF-8"
  connection_limit  = -1
  allow_connections = true

  depends_on = [postgresql_role.sonarqube_user]
}

resource "postgresql_grant" "sonarqube_user_database" {
  database    = postgresql_database.sonarqube.name
  role        = postgresql_role.sonarqube_user.name
  object_type = "database"
  # BACEN BCB 85/2021 Art.6º §1º — Downgrade de ALL para CONNECT+TEMPORARY (database-level)
  privileges = ["CONNECT", "TEMPORARY"]
}

resource "postgresql_grant" "sonarqube_user_schema" {
  database    = postgresql_database.sonarqube.name
  role        = postgresql_role.sonarqube_user.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["ALL"]
}

# -----------------------------------------------------------------------------
# BACEN BCB 85/2021 Art.6º §1º + LGPD Art.46 — DROP EXTENSION dblink
#
# dblink permite conexões cross-database arbitrárias, violando o princípio de
# isolamento de banco de dados e rastreabilidade de acesso. Deve ser removida.
#
# NOTA DE REDE: O provisioner local-exec requer acesso direto ao RDS na porta 5432.
# Em pipelines CI/CD sem port-forward ativo, este null_resource tem lifecycle
# ignore_changes=all — serve como documentação da intenção de compliance.
# EXECUÇÃO MANUAL (quando houver acesso de rede via kubectl port-forward):
#   kubectl port-forward svc/postgresql-external 5432:5432 -n default &
#   PGPASSWORD="<master_password>" psql -h 127.0.0.1 -U postgres_admin \
#     -d gitlab    -c 'DROP EXTENSION IF EXISTS dblink;'
#   PGPASSWORD="<master_password>" psql -h 127.0.0.1 -U postgres_admin \
#     -d keycloak  -c 'DROP EXTENSION IF EXISTS dblink;'
#   PGPASSWORD="<master_password>" psql -h 127.0.0.1 -U postgres_admin \
#     -d sonarqube -c 'DROP EXTENSION IF EXISTS dblink;'
# -----------------------------------------------------------------------------

resource "null_resource" "drop_dblink_gitlab" {
  triggers = {
    database   = postgresql_database.gitlab.name
    compliance = "BACEN-BCB85-2021-Art6-dblink-removal"
  }

  lifecycle {
    # ignore_changes=all: execução manual via kubectl port-forward (sem acesso direto ao RDS em CI/CD)
    ignore_changes = all
  }

  depends_on = [postgresql_database.gitlab]
}

resource "null_resource" "drop_dblink_keycloak" {
  triggers = {
    database   = postgresql_database.keycloak.name
    compliance = "BACEN-BCB85-2021-Art6-dblink-removal"
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [postgresql_database.keycloak]
}

resource "null_resource" "drop_dblink_sonarqube" {
  triggers = {
    database   = postgresql_database.sonarqube.name
    compliance = "BACEN-BCB85-2021-Art6-dblink-removal"
  }

  lifecycle {
    ignore_changes = all
  }

  depends_on = [postgresql_database.sonarqube]
}
