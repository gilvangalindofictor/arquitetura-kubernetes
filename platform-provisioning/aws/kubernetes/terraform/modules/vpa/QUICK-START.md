# VPA Savings Calculator - Quick Start

## 🚀 One-Line Usage

```bash
./calculate-savings.sh
```

Output: `vpa-savings-report.txt`

## 📊 Common Commands

```bash
# Basic report
./calculate-savings.sh -o my-report.txt

# Verbose mode (see processing details)
./calculate-savings.sh -v

# JSON export (for automation)
./calculate-savings.sh -j -o savings.txt
# Creates: savings.txt + savings.json

# All options
./calculate-savings.sh -v -j -o /tmp/vpa-analysis.txt
```

## 📈 Expected Output

```
SUMMARY:
  Total Annual Savings: R$ 19,118.50
  Workloads with Savings: 8/12

Full report saved to: vpa-savings-report.txt
```

## ⚡ Quick Validation

```bash
# Check if script is executable
ls -l calculate-savings.sh

# Make executable if needed
chmod +x calculate-savings.sh

# Test help
./calculate-savings.sh -h

# Verify dependencies
command -v kubectl jq bc
```

## 🎯 Interpreting Results

| Field | Meaning |
|-------|---------|
| **CPU %** | Percentage reduction in CPU requests |
| **MEMORY %** | Percentage reduction in memory requests |
| **SAVINGS/YR** | Annual savings in USD |
| **BRL/YR** | Annual savings in BRL (6.0 exchange rate) |

### Example Row

```
WORKLOAD          NAMESPACE      CPU %    MEMORY %   SAVINGS/YR    BRL/YR
vault             vault-system   88.0%    74.8%      $201.45       R$1,208.70
```

**Translation**: Vault is using 88% more CPU and 75% more RAM than needed. Rightsizing would save R$ 1,208.70/year.

## 🔍 Troubleshooting

| Issue | Solution |
|-------|----------|
| "Cannot access cluster" | `kubectl cluster-info` |
| "VPA CRD not found" | `kubectl get vpa -A` |
| "Missing dependency: bc" | `apt-get install bc` or `brew install bc` |
| Script hangs | Run via: `timeout 120 ./calculate-savings.sh` |
| No savings shown | Wait 24-48h for VPA to collect metrics |

## 📝 Real Cluster Example (us-east-1 staging)

```bash
$ ./calculate-savings.sh

[INFO] Starting VPA Savings Analysis...
[✓] All pre-flight checks passed
[✓] Found 12 VPA objects
[INFO] Analyzing VPA recommendations...
[✓] Analysis complete

SUMMARY:
  Total Annual Savings: R$ 8,712.00
  Workloads with Savings: 8/12

Full report saved to: vpa-savings-report.txt
```

**Report Preview:**

```
WORKLOAD                  NAMESPACE                   CPU %     MEMORY %   SAVINGS/YR       BRL/YR
------------------------- -------------------- ------------ ------------ ------------ ------------
vault                     vault-system                97.0%        80.6% $  1,456.32 R$  8,737.92
redis                     data-services               54.0%        21.9% $     10.38 R$     62.28
...
```

## 🎓 Next Steps

1. **Review Report**: Check which workloads have highest savings
2. **Validate Recommendations**: Ensure VPA targets make sense for your workload
3. **Gradual Rollout**: Start with non-critical workloads
4. **Monitor**: Watch for OOMKilled or CPU throttling
5. **Iterate**: Re-run script monthly to track progress

## 📚 Full Documentation

See [SAVINGS-CALCULATOR.md](./SAVINGS-CALCULATOR.md) for:
- Detailed methodology
- Pricing calculations
- Integration examples
- Advanced use cases
- Troubleshooting guide

## 🔗 Related Files

- `calculate-savings.sh` - Main script (369 lines)
- `SAVINGS-CALCULATOR.md` - Full documentation
- `VALIDATION.md` - VPA validation guide
- `README.md` - VPA module overview

---

**Last Updated**: 2026-02-20
**Script Version**: v2
**Target Cluster**: EKS 1.34 (us-east-1)
