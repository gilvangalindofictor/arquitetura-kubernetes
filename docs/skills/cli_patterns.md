# Skill: CLI Patterns

**Nota**: Aplicável a scripts de automação e ferramentas CLI para a plataforma (ex: scripts de FinOps, migrations, setup).

## Design Principles

1. **POSIX compliance** quando possível
2. **Idempotent**: rodar múltiplas vezes = mesmo resultado
3. **Verbose mode**: `-v` ou `--verbose` para debug
4. **Dry-run**: `-n` ou `--dry-run` para preview
5. **Help**: `-h` ou `--help` sempre disponível

## Structure (Bash)

```bash
#!/usr/bin/env bash
set -euo pipefail  # Exit on error, undefined vars, pipe fails

# Constants
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"

# Functions
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]

Description here.

OPTIONS:
  -h, --help      Show this help
  -v, --verbose   Verbose output
  -n, --dry-run   Dry run (no changes)
EOF
}

main() {
  # Parse args
  # Execute
  # Clean up
}

main "$@"
```

## Error Handling

```bash
# Trap errors
trap 'echo "Error on line $LINENO" >&2' ERR

# Check prerequisites
command -v terraform >/dev/null 2>&1 || {
  echo "terraform not found" >&2
  exit 1
}
```

## Logging

```bash
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[ERROR] $*" >&2; }
debug() { [[ ${VERBOSE:-0} -eq 1 ]] && echo "[DEBUG] $*"; }
```

---

_Skill v1.0 - Para scripts de automação_
