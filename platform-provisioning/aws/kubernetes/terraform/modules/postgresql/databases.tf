# PostgreSQL Provider Configuration
# Connects to the RDS instance created in main.tf
provider "postgresql" {
  host            = aws_db_instance.postgresql.address
  port            = aws_db_instance.postgresql.port
  username        = aws_db_instance.postgresql.username
  password        = random_password.master.result
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
  privileges  = ["ALL"]
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

resource "postgresql_role" "keycloak_user" {
  name     = "keycloak_user"
  login    = true
  password = random_password.keycloak_user.result

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
  privileges  = ["ALL"]
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

resource "postgresql_role" "sonarqube_user" {
  name     = "sonarqube_user"
  login    = true
  password = random_password.sonarqube_user.result

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
  privileges  = ["ALL"]
}

resource "postgresql_grant" "sonarqube_user_schema" {
  database    = postgresql_database.sonarqube.name
  role        = postgresql_role.sonarqube_user.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["ALL"]
}
