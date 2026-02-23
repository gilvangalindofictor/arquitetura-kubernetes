# VPA Savings Calculator

## Overview

The `calculate-savings.sh` script analyzes Vertical Pod Autoscaler (VPA) recommendations and calculates potential cost savings from rightsizing Kubernetes workloads.

## Features

- ✅ Analyzes all VPA objects across all namespaces
- ✅ Calculates annual cost savings in USD and BRL
- ✅ Compares current resource requests vs VPA recommendations
- ✅ Provides detailed breakdown by workload
- ✅ Supports JSON export for automation
- ✅ Configurable AWS pricing (us-east-1 t3 instances)
- ✅ Progress indicator and verbose mode

## Requirements

- `kubectl` configured and connected to EKS cluster
- VPA CRD installed in cluster
- `jq` for JSON parsing
- `bc` for decimal calculations

## Usage

### Basic Usage

```bash
./calculate-savings.sh
```

This will:
1. Analyze all VPA objects in the cluster
2. Calculate savings for each workload
3. Generate report: `vpa-savings-report.txt`

### Advanced Options

```bash
# Verbose mode
./calculate-savings.sh -v

# Custom output file
./calculate-savings.sh -o /path/to/report.txt

# Generate JSON output
./calculate-savings.sh -j -o my-report.txt
# Creates: my-report.json

# All options combined
./calculate-savings.sh -v -j -o /tmp/vpa-analysis.txt
```

### Help

```bash
./calculate-savings.sh -h
```

## How It Works

### 1. Data Collection

The script:
- Fetches all VPA objects from the cluster
- Retrieves VPA recommendations (uncappedTarget)
- Gets current resource requests from target workloads (Deployment/StatefulSet/DaemonSet)

### 2. Calculations

For each workload:

**CPU Savings** = (Current CPU - Target CPU) × $0.0416/vCPU/hour × 730 hours/month × 12 months

**Memory Savings** = (Current Memory - Target Memory) × $0.00456/GB/hour × 730 hours/month × 12 months

**Total Savings** = CPU Savings + Memory Savings

**BRL Savings** = Total Savings × 6.0 (exchange rate)

### 3. Resource Unit Parsing

The script handles Kubernetes resource formats:

**CPU**:
- `500m` → 0.5 cores
- `1` → 1 core
- `1.5` → 1.5 cores

**Memory**:
- `134217728` (bytes) → 0.125 GB
- `128Mi` → 0.125 GB
- `1Gi` → 1 GB
- `0.5Ti` → 512 GB

### 4. Filtering

Workloads are only included if:
- VPA recommendation exists (`status.recommendation`)
- Current resource requests are set (not empty `{}`)
- Savings > R$ 0 (positive cost reduction)

## Output Format

### Text Report

```
================================================================================
                    VPA SAVINGS ANALYSIS REPORT
================================================================================

Generated: 2026-02-20 18:33:55 -03
Cluster: arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod

Pricing Assumptions:
  - CPU Cost:    $0.0416 per vCPU/hour (us-east-1 t3)
  - Memory Cost: $0.00456 per GB/hour (us-east-1 t3)
  - Exchange Rate: 1 USD = 6.0 BRL

================================================================================

WORKLOAD                  NAMESPACE                   CPU %     MEMORY %   SAVINGS/YR       BRL/YR
------------------------- -------------------- ------------ ------------ ------------ ------------
vault                     vault-system                88.0%        74.8% $    201.45 R$  1,208.70
keycloak                  keycloak                    70.0%        60.0% $    152.30 R$    913.80
prometheus                monitoring                  65.0%        55.0% $    128.50 R$    771.00
...

================================================================================

SUMMARY
-------
Total Workloads Analyzed:        12
Workloads with Savings:          8
Total Annual Savings (USD):      $3,186.42
Total Annual Savings (BRL):      R$ 19,118.50

================================================================================
```

### JSON Report

When `-j` flag is used, creates `{output_file}.json`:

```json
{
    "generated_at": "2026-02-20T18:33:55-03:00",
    "cluster": "arn:aws:eks:us-east-1:891377105802:cluster/k8s-platform-prod",
    "summary": {
        "total_workloads": 12,
        "workloads_with_savings": 8,
        "total_savings_year_usd": 3186.42,
        "total_savings_year_brl": 19118.50
    }
}
```

## Pricing Configuration

Default pricing (us-east-1 t3 instances):

| Resource | Cost | Source |
|----------|------|--------|
| CPU | $0.0416/vCPU/hour | AWS t3 on-demand pricing |
| Memory | $0.00456/GB/hour | AWS t3 on-demand pricing |
| Exchange Rate | 6.0 USD→BRL | Configurable |

To modify pricing, edit the script constants:

```bash
readonly CPU_COST_PER_HOUR=0.0416        # $/vCPU/hour
readonly MEMORY_COST_PER_GB_HOUR=0.00456 # $/GB/hour
readonly BRL_EXCHANGE_RATE=6.0           # USD to BRL
```

## VPA Recommendation Types

The script uses `uncappedTarget` from VPA recommendations:

- **lowerBound**: Minimum recommended resources
- **target**: Capped recommendation (respects VPA policy min/max)
- **uncappedTarget**: Raw recommendation (most accurate)
- **upperBound**: Maximum recommended resources

## Common Scenarios

### Scenario 1: No Recommendations Yet

```
[INFO] Analyzing VPA recommendations...
[DEBUG] Processing VPA 1/12: vault-system/vault
[DEBUG]   Skipping (no recommendation available)
```

**Cause**: VPA needs ~24-48 hours to collect metrics

**Solution**: Wait for VPA to gather data, then re-run script

### Scenario 2: No Current Requests

```
[DEBUG] Processing VPA 1/12: argocd/argocd-server
[DEBUG]   Skipping (no current resource requests)
```

**Cause**: Workload doesn't have `resources.requests` set

**Solution**: This is expected; VPA can't calculate savings without a baseline

### Scenario 3: Zero Savings

```
Total Annual Savings (BRL):      R$ 0.00
```

**Cause**:
- All workloads already rightsized
- VPA recommendations match current requests
- No workloads have both recommendations + current requests

**Solution**: Review VPA objects individually with `kubectl describe vpa -A`

## Integration with FinOps Workflow

### Monthly Savings Tracking

```bash
# Generate monthly report
./calculate-savings.sh -j -o reports/vpa-$(date +%Y-%m).txt

# Extract total savings for dashboard
jq '.summary.total_savings_year_brl' reports/vpa-$(date +%Y-%m).json
```

### CI/CD Pipeline

```bash
#!/bin/bash
# Check if VPA recommendations would save >R$ 10,000/year

./calculate-savings.sh -j -o /tmp/vpa-check.txt

savings=$(jq '.summary.total_savings_year_brl' /tmp/vpa-check.json)

if (( $(echo "$savings > 10000" | bc -l) )); then
    echo "⚠️  HIGH SAVINGS OPPORTUNITY: R$ $savings/year"
    echo "Consider implementing VPA updateMode: Auto"
    exit 1  # Fail pipeline to force review
fi
```

### Terraform Integration

Track savings in Terraform outputs:

```hcl
resource "null_resource" "vpa_savings_analysis" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = "${path.module}/calculate-savings.sh -j -o ${path.module}/vpa-savings.txt"
  }
}

data "local_file" "vpa_savings_json" {
  depends_on = [null_resource.vpa_savings_analysis]
  filename   = "${path.module}/vpa-savings.json"
}

output "vpa_annual_savings_brl" {
  value = jsondecode(data.local_file.vpa_savings_json.content).summary.total_savings_year_brl
}
```

## Troubleshooting

### Error: "Cannot access Kubernetes cluster"

```bash
# Verify kubectl context
kubectl config current-context

# Test cluster access
kubectl cluster-info
```

### Error: "VPA CRD not found in cluster"

```bash
# Check if VPA is installed
kubectl get crd verticalpodautoscalers.autoscaling.k8s.io

# Install VPA (if needed)
helm upgrade --install vpa fairwinds-stable/vpa \
  --namespace kube-system --version 4.4.6
```

### Error: "Missing required dependency: bc"

```bash
# Ubuntu/Debian
sudo apt-get install bc

# macOS
brew install bc

# Alpine
apk add bc
```

### Script Hangs

If the script hangs during execution:

```bash
# Run in background with timeout
timeout 120 ./calculate-savings.sh -o /tmp/vpa.txt || echo "Timed out after 120s"

# Check for stuck kubectl processes
ps aux | grep kubectl

# Kill stuck processes
pkill -f "kubectl.*vpa"
```

## Limitations

1. **Only analyzes first container**: Multi-container pods only analyze `containers[0]`
2. **On-demand pricing only**: Doesn't account for Spot or Reserved Instances
3. **Static exchange rate**: BRL exchange rate is hardcoded (6.0)
4. **No pod scaling factor**: Assumes 1 replica (doesn't multiply by replica count)
5. **T3 pricing only**: Doesn't account for other instance families

## Roadmap

- [ ] Multi-container support
- [ ] Replica count multiplication
- [ ] Dynamic exchange rate (API)
- [ ] Spot instance pricing
- [ ] HTML report generation
- [ ] Chart/graph output
- [ ] Historical trend tracking
- [ ] Slack/Teams notifications

## Examples

### Real Cluster Analysis (staging)

```bash
$ ./calculate-savings.sh -v

[INFO] Starting VPA Savings Analysis...
[INFO] Checking dependencies...
[✓] All pre-flight checks passed

[INFO] Collecting VPA data from cluster...
[✓] Found 12 VPA objects

[INFO] Analyzing VPA recommendations...
[DEBUG] Processing VPA 1/12: argocd/argocd-server
[DEBUG]   Skipping (no current resource requests)
[DEBUG] Processing VPA 2/12: data-services/rabbitmq
[DEBUG]   Skipping (no recommendation available)
[DEBUG] Processing VPA 3/12: data-services/redis
[DEBUG]   Current: CPU=0.050000 cores, Memory=0.062500 GB
[DEBUG]   Target:  CPU=0.023000 cores, Memory=0.048828 GB
[DEBUG] Processing VPA 4/12: vault-system/vault
[DEBUG]   Current: CPU=0.500000 cores, Memory=0.500000 GB
[DEBUG]   Target:  CPU=0.015000 cores, Memory=0.097656 GB
...
[✓] Analysis complete

SUMMARY:
  Total Annual Savings: R$ 8,712.00
  Workloads with Savings: 8/12

Full report saved to: vpa-savings-report.txt
```

## License

Internal use only - K8s Platform Remediation Project

## Author

DevOps Specialist Agent
Date: 2026-02-20
