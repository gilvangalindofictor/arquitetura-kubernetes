#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Script: validate-fase7.sh
# Description: Marco 2 Fase 7 - Test Applications End-to-End Validation
# Usage: ./validate-fase7.sh
# -----------------------------------------------------------------------------

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
print_header() { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}$1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

NAMESPACE="test-apps"
VALIDATION_ERRORS=0

# -----------------------------------------------------------------------------
# 1. Verificar Namespace
# -----------------------------------------------------------------------------
print_header "1. Checking Namespace"

if kubectl get namespace "$NAMESPACE" &> /dev/null; then
  print_success "Namespace '$NAMESPACE' exists"
else
  print_error "Namespace '$NAMESPACE' not found"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Verificar Pods Status
# -----------------------------------------------------------------------------
print_header "2. Checking Pods Status"

NGINX_READY=$(kubectl get pods -n "$NAMESPACE" -l app=nginx-test -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o True | wc -l || echo 0)
ECHO_READY=$(kubectl get pods -n "$NAMESPACE" -l app=echo-server -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o True | wc -l || echo 0)

if [ "$NGINX_READY" -eq 2 ]; then
  print_success "NGINX pods: 2/2 Ready"
else
  print_error "NGINX pods: $NGINX_READY/2 Ready"
  kubectl get pods -n "$NAMESPACE" -l app=nginx-test
  ((VALIDATION_ERRORS++))
fi

if [ "$ECHO_READY" -eq 2 ]; then
  print_success "Echo Server pods: 2/2 Ready"
else
  print_error "Echo Server pods: $ECHO_READY/2 Ready"
  kubectl get pods -n "$NAMESPACE" -l app=echo-server
  ((VALIDATION_ERRORS++))
fi

# -----------------------------------------------------------------------------
# 3. Verificar Services
# -----------------------------------------------------------------------------
print_header "3. Checking Services"

if kubectl get svc -n "$NAMESPACE" nginx-test &> /dev/null; then
  print_success "NGINX Service exists"
else
  print_error "NGINX Service not found"
  ((VALIDATION_ERRORS++))
fi

if kubectl get svc -n "$NAMESPACE" echo-server &> /dev/null; then
  print_success "Echo Server Service exists"
else
  print_error "Echo Server Service not found"
  ((VALIDATION_ERRORS++))
fi

# -----------------------------------------------------------------------------
# 4. Verificar Ingress e ALB
# -----------------------------------------------------------------------------
print_header "4. Checking Ingress and ALB Provisioning"

NGINX_ALB=$(kubectl get ingress -n "$NAMESPACE" nginx-test-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
ECHO_ALB=$(kubectl get ingress -n "$NAMESPACE" echo-server-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [ -n "$NGINX_ALB" ]; then
  print_success "NGINX ALB provisioned: $NGINX_ALB"
else
  print_warning "NGINX ALB not yet provisioned (aguardar 2-3 minutos)"
  kubectl get ingress -n "$NAMESPACE" nginx-test-ingress
  ((VALIDATION_ERRORS++))
fi

if [ -n "$ECHO_ALB" ]; then
  print_success "Echo Server ALB provisioned: $ECHO_ALB"
else
  print_warning "Echo Server ALB not yet provisioned (aguardar 2-3 minutos)"
  kubectl get ingress -n "$NAMESPACE" echo-server-ingress
  ((VALIDATION_ERRORS++))
fi

# -----------------------------------------------------------------------------
# 5. Testar HTTP Endpoints
# -----------------------------------------------------------------------------
print_header "5. Testing HTTP Endpoints"

if [ -n "$NGINX_ALB" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$NGINX_ALB" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    print_success "NGINX HTTP responding ($HTTP_CODE - redirect to HTTPS expected)"
  else
    print_error "NGINX HTTP failed (HTTP $HTTP_CODE)"
    ((VALIDATION_ERRORS++))
  fi
else
  print_warning "Skipping NGINX HTTP test (ALB not provisioned)"
fi

if [ -n "$ECHO_ALB" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$ECHO_ALB/health" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "200" ]; then
    print_success "Echo Server HTTP responding ($HTTP_CODE)"
  else
    print_error "Echo Server HTTP failed (HTTP $HTTP_CODE)"
    ((VALIDATION_ERRORS++))
  fi
else
  print_warning "Skipping Echo Server HTTP test (ALB not provisioned)"
fi

# -----------------------------------------------------------------------------
# 6. Testar HTTPS/TLS Endpoints
# -----------------------------------------------------------------------------
print_header "6. Testing HTTPS/TLS Endpoints"

if [ -n "$NGINX_ALB" ]; then
  HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$NGINX_ALB" 2>/dev/null || echo "000")
  if [ "$HTTPS_CODE" = "200" ]; then
    print_success "NGINX HTTPS responding (200 OK)"
  else
    print_error "NGINX HTTPS failed (HTTP $HTTPS_CODE)"
    ((VALIDATION_ERRORS++))
  fi
else
  print_warning "Skipping NGINX HTTPS test (ALB not provisioned)"
fi

if [ -n "$ECHO_ALB" ]; then
  HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "https://$ECHO_ALB/health" 2>/dev/null || echo "000")
  if [ "$HTTPS_CODE" = "200" ]; then
    print_success "Echo Server HTTPS responding (200 OK)"
  else
    print_error "Echo Server HTTPS failed (HTTP $HTTPS_CODE)"
    ((VALIDATION_ERRORS++))
  fi
else
  print_warning "Skipping Echo Server HTTPS test (ALB not provisioned)"
fi

# -----------------------------------------------------------------------------
# 7. Verificar Certificados TLS (Cert-Manager)
# -----------------------------------------------------------------------------
print_header "7. Checking Cert-Manager Certificates"

NGINX_CERT_READY=$(kubectl get certificate -n "$NAMESPACE" nginx-test-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")
ECHO_CERT_READY=$(kubectl get certificate -n "$NAMESPACE" echo-server-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "NotFound")

if [ "$NGINX_CERT_READY" = "True" ]; then
  print_success "NGINX TLS Certificate: Ready"
elif [ "$NGINX_CERT_READY" = "NotFound" ]; then
  print_warning "NGINX TLS Certificate: Not created yet (aguardar)"
else
  print_warning "NGINX TLS Certificate: $NGINX_CERT_READY (normal se usando selfsigned-issuer)"
fi

if [ "$ECHO_CERT_READY" = "True" ]; then
  print_success "Echo Server TLS Certificate: Ready"
elif [ "$ECHO_CERT_READY" = "NotFound" ]; then
  print_warning "Echo Server TLS Certificate: Not created yet (aguardar)"
else
  print_warning "Echo Server TLS Certificate: $ECHO_CERT_READY (normal se usando selfsigned-issuer)"
fi

# -----------------------------------------------------------------------------
# 8. Verificar ServiceMonitors (Prometheus)
# -----------------------------------------------------------------------------
print_header "8. Checking Prometheus ServiceMonitors"

if kubectl get servicemonitor -n "$NAMESPACE" nginx-test &> /dev/null; then
  print_success "NGINX ServiceMonitor exists"
else
  print_error "NGINX ServiceMonitor not found"
  ((VALIDATION_ERRORS++))
fi

if kubectl get servicemonitor -n "$NAMESPACE" echo-server &> /dev/null; then
  print_success "Echo Server ServiceMonitor exists"
else
  print_error "Echo Server ServiceMonitor not found"
  ((VALIDATION_ERRORS++))
fi

# -----------------------------------------------------------------------------
# 9. Verificar Network Policies
# -----------------------------------------------------------------------------
print_header "9. Checking Network Policies"

NP_COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" 2>/dev/null | grep -c "allow-" || echo 0)
if [ "$NP_COUNT" -gt 0 ]; then
  print_success "Network Policies applied ($NP_COUNT policies)"
  kubectl get networkpolicy -n "$NAMESPACE"
else
  print_warning "No Network Policies found in namespace"
fi

# -----------------------------------------------------------------------------
# 10. Resumo e Comandos Manuais
# -----------------------------------------------------------------------------
print_header "10. Validation Summary"

if [ $VALIDATION_ERRORS -eq 0 ]; then
  print_success "Todas as validações passaram! ✅"
else
  print_warning "$VALIDATION_ERRORS validação(ões) falharam ou estão pendentes"
fi

echo ""
print_info "Endpoints ALB:"
if [ -n "$NGINX_ALB" ]; then
  echo "  NGINX:       https://$NGINX_ALB"
fi
if [ -n "$ECHO_ALB" ]; then
  echo "  Echo Server: https://$ECHO_ALB"
fi

echo ""
print_info "Comandos Manuais de Teste:"
if [ -n "$NGINX_ALB" ]; then
  echo "  # Testar NGINX"
  echo "  curl -k https://$NGINX_ALB"
  echo ""
fi
if [ -n "$ECHO_ALB" ]; then
  echo "  # Testar Echo Server (JSON response)"
  echo "  curl -k https://$ECHO_ALB | jq"
  echo ""
fi

echo "  # Ver métricas do NGINX no Prometheus"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090"
echo "  # Abrir http://localhost:9090 e executar query: nginx_connections_active{namespace=\"$NAMESPACE\"}"
echo ""

echo "  # Ver logs no Loki via Grafana"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo "  # Abrir http://localhost:3000 → Explore → Loki → {namespace=\"$NAMESPACE\"}"
echo ""

if [ $VALIDATION_ERRORS -eq 0 ]; then
  exit 0
else
  exit 1
fi
