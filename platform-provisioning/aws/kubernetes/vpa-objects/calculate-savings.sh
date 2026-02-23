#!/bin/bash
# VPA Rightsizing Savings Calculator
# Run after 30 days of VPA metric collection

set -e

echo "💰 VPA Rightsizing Savings Analysis"
echo "===================================="
echo ""
echo "📊 Analyzing VPA recommendations for 12 critical workloads..."
echo ""

# Export current state
EXPORT_FILE="/tmp/vpa-analysis-$(date +%Y%m%d-%H%M%S).json"
kubectl get vpa -A -o json > "$EXPORT_FILE"
echo "✅ Exported VPA data to: $EXPORT_FILE"
echo ""

# Function to calculate CPU difference
calc_cpu_diff() {
    local current="$1"
    local target="$2"

    # Convert to millicores
    current_m=$(echo "$current" | sed 's/m$//' | sed 's/$/000/' | sed 's/000m$//')
    target_m=$(echo "$target" | sed 's/m$//' | sed 's/$/000/' | sed 's/000m$//')

    diff=$((target_m - current_m))
    echo "$diff"
}

# Function to calculate memory difference
calc_mem_diff() {
    local current="$1"
    local target="$2"

    # Convert to Mi
    current_mi=$(echo "$current" | sed 's/Gi/*1024/; s/Mi//; s/G/*1024/' | bc 2>/dev/null || echo "0")
    target_mi=$(echo "$target" | sed 's/Gi/*1024/; s/Mi//; s/G/*1024/' | bc 2>/dev/null || echo "0")

    diff=$((target_mi - current_mi))
    echo "$diff"
}

echo "📈 VPA Recommendations Summary:"
echo "==============================="
echo ""

# Priority 0 - Critical
echo "🔴 P0 - CRITICAL WORKLOADS:"
echo "-------------------------"

for vpa in vault-system:vault keycloak:keycloak gitlab-staging:gitlab-webservice monitoring:prometheus; do
    ns=$(echo "$vpa" | cut -d: -f1)
    name=$(echo "$vpa" | cut -d: -f2)

    echo ""
    echo "  [$name @ $ns]"

    # Get current resources
    current=$(kubectl get vpa "$name" -n "$ns" -o jsonpath='{.spec.resourcePolicy.containerPolicies[0]}' 2>/dev/null)

    # Get VPA recommendation
    target=$(kubectl get vpa "$name" -n "$ns" -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' 2>/dev/null)

    if [ -z "$target" ]; then
        echo "    ⚠️  No recommendations yet (still collecting data)"
    else
        target_cpu=$(echo "$target" | jq -r '.cpu // "N/A"')
        target_mem=$(echo "$target" | jq -r '.memory // "N/A"')

        echo "    Recommended: CPU=$target_cpu, Memory=$target_mem"

        # Get current pod resources for comparison
        pod_selector=""
        case "$name" in
            vault) pod_selector="app.kubernetes.io/name=vault" ;;
            keycloak) pod_selector="app.kubernetes.io/name=keycloakx" ;;
            gitlab-webservice) pod_selector="app=webservice" ;;
            prometheus) pod_selector="app.kubernetes.io/name=prometheus" ;;
        esac

        if [ -n "$pod_selector" ]; then
            current_resources=$(kubectl get pods -n "$ns" -l "$pod_selector" -o jsonpath='{.items[0].spec.containers[0].resources.requests}' 2>/dev/null || echo "{}")
            current_cpu=$(echo "$current_resources" | jq -r '.cpu // "N/A"')
            current_mem=$(echo "$current_resources" | jq -r '.memory // "N/A"')

            echo "    Current:     CPU=$current_cpu, Memory=$current_mem"

            # Calculate change percentage
            if [ "$target_cpu" != "N/A" ] && [ "$current_cpu" != "N/A" ]; then
                if [[ "$target_cpu" < "$current_cpu" ]]; then
                    echo "    💡 Opportunity: DOWNSIZE CPU (save resources)"
                elif [[ "$target_cpu" > "$current_cpu" ]]; then
                    echo "    ⚡ Action needed: UPSIZE CPU (improve performance)"
                else
                    echo "    ✅ Optimal: Current sizing is appropriate"
                fi
            fi
        fi
    fi
done

echo ""
echo ""

# Priority 1 - Important
echo "🟡 P1 - IMPORTANT WORKLOADS:"
echo "--------------------------"

for vpa in harbor-system:harbor-core harbor-system:harbor-jobservice monitoring:grafana argocd:argocd-server; do
    ns=$(echo "$vpa" | cut -d: -f1)
    name=$(echo "$vpa" | cut -d: -f2)

    target=$(kubectl get vpa "$name" -n "$ns" -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' 2>/dev/null)

    if [ -n "$target" ]; then
        target_cpu=$(echo "$target" | jq -r '.cpu // "N/A"')
        target_mem=$(echo "$target" | jq -r '.memory // "N/A"')
        echo "  [$name @ $ns]: CPU=$target_cpu, Memory=$target_mem"
    else
        echo "  [$name @ $ns]: ⚠️  No recommendations yet"
    fi
done

echo ""
echo ""

# Priority 2 - Desirable
echo "🟢 P2 - DESIRABLE WORKLOADS:"
echo "--------------------------"

for vpa in gitlab-staging:gitlab-sidekiq gitlab-staging:gitlab-gitaly monitoring:loki-write monitoring:tempo-ingester; do
    ns=$(echo "$vpa" | cut -d: -f1)
    name=$(echo "$vpa" | cut -d: -f2)

    target=$(kubectl get vpa "$name" -n "$ns" -o jsonpath='{.status.recommendation.containerRecommendations[0].target}' 2>/dev/null)

    if [ -n "$target" ]; then
        target_cpu=$(echo "$target" | jq -r '.cpu // "N/A"')
        target_mem=$(echo "$target" | jq -r '.memory // "N/A"')
        echo "  [$name @ $ns]: CPU=$target_cpu, Memory=$target_mem"
    else
        echo "  [$name @ $ns]: ⚠️  No recommendations yet"
    fi
done

echo ""
echo ""

# Summary statistics
echo "📊 COLLECTION STATUS:"
echo "===================="

total_vpas=12
vpas_with_data=$(kubectl get vpa -A -o json | jq '[.items[] | select(.status.recommendation != null)] | length')
vpas_without_data=$((total_vpas - vpas_with_data))

echo "  Total VPAs configured: $total_vpas"
echo "  VPAs with recommendations: $vpas_with_data"
echo "  VPAs still collecting: $vpas_without_data"
echo ""

if [ "$vpas_with_data" -ge 8 ]; then
    echo "  ✅ Collection progress: GOOD (≥8/12 have data)"
    echo "     Ready for analysis phase"
elif [ "$vpas_with_data" -ge 4 ]; then
    echo "  ⚠️  Collection progress: PARTIAL (4-7/12 have data)"
    echo "     Wait for more workloads to generate recommendations"
else
    echo "  ❌ Collection progress: INSUFFICIENT (<4/12 have data)"
    echo "     Need more time for metric collection (minimum 7 days recommended)"
fi

echo ""
echo ""

echo "💡 NEXT STEPS:"
echo "============="
echo "  1. Review exported data: cat $EXPORT_FILE | jq ."
echo "  2. Compare recommendations vs current configs"
echo "  3. Calculate node savings potential:"
echo "     - Downsize recommendations → free capacity"
echo "     - Upsize recommendations → allocate capacity"
echo "  4. Update Terraform/Helm values with new resource configs"
echo "  5. Apply changes in staging → validate → production"
echo "  6. Measure actual savings and update MEMORY.md"
echo ""
echo "🎯 TARGET SAVINGS: R$ 8.712/year (VPA rightsizing component)"
echo ""

# Generate CSV for analysis
CSV_FILE="/tmp/vpa-recommendations-$(date +%Y%m%d).csv"
echo "namespace,vpa_name,container,current_cpu,current_mem,target_cpu,target_mem,lower_cpu,lower_mem,upper_cpu,upper_mem" > "$CSV_FILE"

kubectl get vpa -A -o json | jq -r '.items[] |
  .metadata.namespace as $ns |
  .metadata.name as $name |
  (.status.recommendation.containerRecommendations // []) | .[] |
  [
    $ns,
    $name,
    .containerName,
    "N/A",
    "N/A",
    .target.cpu // "N/A",
    .target.memory // "N/A",
    .lowerBound.cpu // "N/A",
    .lowerBound.memory // "N/A",
    .upperBound.cpu // "N/A",
    .upperBound.memory // "N/A"
  ] | @csv' >> "$CSV_FILE"

echo "📄 CSV export: $CSV_FILE"
echo "   (Import into spreadsheet for detailed analysis)"
echo ""
