# Kubernetes (kubectl) — trechos pinados

version: ~>2.35 (terraform provider)
source: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs
link: https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs

Trechos úteis:

- Ver pods: `kubectl get pods -n <ns> -o wide`
- Events: `kubectl get events -n <ns> --sort-by='.lastTimestamp'`
- Logs: `kubectl logs <pod> -n <ns> --tail=200` — use `-c` para container específico

HPA/VPA: confirmar apiVersion e fields antes de aplicar (dependente da versão do cluster).
