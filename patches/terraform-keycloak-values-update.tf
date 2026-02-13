// Snippet to update templatefile() args to include postgresql host/port for initContainer
// Add the following to modules/keycloak/main.tf where templatefile is called

/*
  templatefile(
    "${path.module}/values.yaml.tpl",
    {
      postgresql_host = var.postgresql_host,
      postgresql_port = var.postgresql_port,
      # ... existing template variables
    }
  )
*/

// Ensure `var.postgresql_host` and `var.postgresql_port` are declared in variables.tf and passed from environment.
