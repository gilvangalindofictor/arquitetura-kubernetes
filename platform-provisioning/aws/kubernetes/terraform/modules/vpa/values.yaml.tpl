# VPA Helm Chart Values
# Fairwinds VPA v4.4.6 — Recommendation Mode Only

recommender:
  enabled: ${recommender_enabled}
  extraArgs:
    storage: prometheus
    prometheus-address: "${prometheus_address}"

updater:
  enabled: ${updater_enabled}

admissionController:
  enabled: ${admission_controller_enabled}
