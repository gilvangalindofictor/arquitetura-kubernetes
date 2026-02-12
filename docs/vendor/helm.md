# Helm — trechos pinados


version: ~>2.17 (terraform provider)
source: https://registry.terraform.io/providers/hashicorp/helm/latest/docs
link: https://registry.terraform.io/providers/hashicorp/helm/latest/docs

Trechos úteis:

- Install: `helm install <release> <chart> --namespace <ns> --create-namespace`
- Upgrade: `helm upgrade --install <release> <chart> -f values.yaml`
- Rollback: `helm rollback <release> <revision>`

Notas: charts e apiVersions mudam entre versões do helm/k8s — checar compatibilidade.
