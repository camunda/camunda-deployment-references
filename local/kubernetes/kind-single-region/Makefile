# Camunda 8 on Kind - Local Development
# ======================================
#
# IMPORTANT: SECONDARY_STORAGE must be set before running init targets.
#            There is no default value - you must choose one:
#              - elasticsearch: Full platform with Optimize
#              - postgres: RDBMS-only mode (lighter, no Optimize)
#
# Quick start:
#   SECONDARY_STORAGE=postgres make domain.init      # PG-only with TLS (recommended)
#   SECONDARY_STORAGE=postgres make no-domain.init   # PG-only with port-forward
#   SECONDARY_STORAGE=elasticsearch make domain.init # Full platform with TLS
#
# Scripts in ./procedure/ can be run independently after sourcing environment.
#

SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

# Configuration
CLUSTER_NAME ?= camunda-platform-local
CAMUNDA_NAMESPACE ?= camunda
CAMUNDA_RELEASE_NAME ?= camunda
CERT_DIR ?= .certs
# SECONDARY_STORAGE has no default - must be explicitly set to 'elasticsearch' or 'postgres'

export CLUSTER_NAME CAMUNDA_NAMESPACE CAMUNDA_RELEASE_NAME CERT_DIR SECONDARY_STORAGE

# Paths
PROCEDURE_DIR := ./procedure

# =============================================================================
# Help
# =============================================================================

.PHONY: help
help:
	@echo "Camunda 8 on Kind - Local Development"
	@echo ""
	@echo "IMPORTANT: Set SECONDARY_STORAGE before running init targets."
	@echo "           Valid values: elasticsearch, postgres"
	@echo ""
	@echo "Quick start (postgres, no Elasticsearch, no Optimize):"
	@echo "  SECONDARY_STORAGE=postgres make domain.init      # With TLS (mkcert)"
	@echo "  SECONDARY_STORAGE=postgres make no-domain.init   # With port-forward"
	@echo ""
	@echo "Quick start (elasticsearch — full platform with Optimize):"
	@echo "  SECONDARY_STORAGE=elasticsearch make domain.init      # With TLS"
	@echo "  SECONDARY_STORAGE=elasticsearch make no-domain.init   # With port-forward"
	@echo ""
	@echo "Main workflows:"
	@echo "  make domain.init        Full initialization with TLS (requires SECONDARY_STORAGE)"
	@echo "  make domain.clean       Full cleanup"
	@echo "  make no-domain.init     Full initialization with port-forward (requires SECONDARY_STORAGE)"
	@echo "  make no-domain.clean    Full cleanup"
	@echo ""
	@echo "Infrastructure only (bring your own Camunda values):"
	@echo "  make domain.infra       Setup infra with TLS (no Camunda)"
	@echo "  make no-domain.infra    Setup infra without TLS (no Camunda)"
	@echo ""
	@echo "Individual commands:"
	@echo "  make cluster.create           Create Kind cluster"
	@echo "  make cluster.delete           Delete Kind cluster"
	@echo "  make ingress.deploy           Deploy Contour ingress controller"
	@echo "  make operators.deploy-domain       Deploy operators (domain mode)"
	@echo "  make operators.deploy-no-domain    Deploy operators (no-domain mode)"
	@echo "  make hosts.add                Add /etc/hosts entries (domain mode)"
	@echo "  make hosts.add-keycloak       Add Keycloak host entry (no-domain mode)"
	@echo "  make hosts.remove             Remove /etc/hosts entries (domain mode)"
	@echo "  make hosts.remove-keycloak    Remove Keycloak host entry"
	@echo "  make certs.generate           Generate TLS certificates"
	@echo "  make identity-secrets.create  Create identity secrets"
	@echo "  make camunda.deploy-domain    Deploy Camunda (domain mode)"
	@echo "  make camunda.deploy-no-domain Deploy Camunda (no-domain mode)"
	@echo "  make camunda.wait             Wait for Camunda pods to be ready"
	@echo "  make camunda.uninstall        Uninstall Camunda"
	@echo ""
	@echo "Utilities:"
	@echo "  make status             Show cluster status"
	@echo "  make port-forward       Start port-forwarding"
	@echo "  make get-password       Get Camunda admin password"
	@echo "  make get-keycloak-password  Get Keycloak admin credentials"

# =============================================================================
# Full workflows
# =============================================================================

.PHONY: domain.init
domain.init: cluster.create ingress.deploy coredns.config hosts.add certs.generate certs.create-secret certs.create-ca-configmap operators.deploy-domain identity-secrets.create camunda.deploy-domain camunda.wait
	@( \
		PASSWORD=$$($(PROCEDURE_DIR)/get-password.sh); \
		echo ""; \
		echo "✓ Domain setup complete! (secondary storage: $(SECONDARY_STORAGE))"; \
		echo "  Access: https://camunda.example.com"; \
		echo "  Credentials: admin / $$PASSWORD"; \
		if [[ "$(SECONDARY_STORAGE)" == "postgres" ]]; then \
			echo "  Note: Optimize is disabled in postgres mode"; \
		fi; \
		echo ""; \
		echo "  Keycloak admin credentials: make get-keycloak-password"; \
	)

.PHONY: domain.clean
domain.clean: camunda.uninstall cluster.delete hosts.remove certs.clean
	@echo ""
	@echo "✓ Domain cleanup complete!"

.PHONY: no-domain.init
no-domain.init: cluster.create hosts.add-keycloak operators.deploy-no-domain identity-secrets.create camunda.deploy-no-domain camunda.wait
	@( \
		PASSWORD=$$($(PROCEDURE_DIR)/get-password.sh); \
		echo ""; \
		echo "✓ No-domain setup complete! (secondary storage: $(SECONDARY_STORAGE))"; \
		echo "  Run: make port-forward"; \
		echo "  Credentials: admin / $$PASSWORD"; \
		if [[ "$(SECONDARY_STORAGE)" == "postgres" ]]; then \
			echo "  Note: Optimize is disabled in postgres mode"; \
		fi; \
		echo ""; \
		echo "  Keycloak admin credentials: make get-keycloak-password"; \
	)

# Infrastructure only (no Camunda) — bring your own values.yaml

.PHONY: domain.infra
domain.infra: cluster.create ingress.deploy coredns.config hosts.add certs.generate certs.create-secret certs.create-ca-configmap operators.deploy-domain
	@echo ""
	@echo "✓ Domain infrastructure ready!"
	@echo "  Before installing Camunda, create the required credentials secret (camunda-credentials):"
	@echo "    make identity-secrets.create"
	@echo "  Deploy Camunda with your own values:"
	@echo "    helm upgrade --install camunda oci://registry.camunda.cloud/team-distribution/camunda-platform --version <CHART_VERSION> -n camunda --create-namespace -f your-values.yaml"
	@echo ""

.PHONY: no-domain.infra
no-domain.infra: cluster.create hosts.add-keycloak operators.deploy-no-domain
	@echo ""
	@echo "✓ No-domain infrastructure ready!"
	@echo "  Before installing Camunda, create the required credentials secret (camunda-credentials):"
	@echo "    make identity-secrets.create"
	@echo "  Deploy Camunda with your own values:"
	@echo "    helm upgrade --install camunda oci://registry.camunda.cloud/team-distribution/camunda-platform --version <CHART_VERSION> -n camunda --create-namespace -f your-values.yaml"
	@echo ""

.PHONY: no-domain.clean
no-domain.clean: camunda.uninstall cluster.delete hosts.remove-keycloak
	@echo ""
	@echo "✓ No-domain cleanup complete!"

# =============================================================================
# Cluster
# =============================================================================

.PHONY: cluster.create
cluster.create:
	@$(PROCEDURE_DIR)/cluster-create.sh

.PHONY: cluster.delete
cluster.delete:
	@kind delete cluster --name $(CLUSTER_NAME)

# =============================================================================
# Operators (Elasticsearch, PostgreSQL, Keycloak)
# =============================================================================

.PHONY: operators.deploy-domain
operators.deploy-domain:
	@CAMUNDA_MODE=domain $(PROCEDURE_DIR)/operators-deploy.sh

.PHONY: operators.deploy-no-domain
operators.deploy-no-domain:
	@CAMUNDA_MODE=no-domain $(PROCEDURE_DIR)/operators-deploy.sh

# =============================================================================
# Infrastructure
# =============================================================================

.PHONY: ingress.deploy
ingress.deploy:
	@$(PROCEDURE_DIR)/contour-deploy.sh

.PHONY: coredns.config
coredns.config:
	@$(PROCEDURE_DIR)/coredns-config.sh

# =============================================================================
# Hosts (/etc/hosts)
# =============================================================================

.PHONY: hosts.add
hosts.add:
	@$(PROCEDURE_DIR)/hosts-add.sh

.PHONY: hosts.add-keycloak
hosts.add-keycloak:
	@echo "Adding Keycloak host entry (requires sudo)..."
	@if ! grep -q "^127\.0\.0\.1[[:space:]]\{1,\}keycloak-service$$" /etc/hosts; then \
		echo "127.0.0.1  keycloak-service" | sudo tee -a /etc/hosts > /dev/null; \
		echo "Added: 127.0.0.1  keycloak-service"; \
	else \
		echo "Host entry already exists."; \
	fi

.PHONY: hosts.remove
hosts.remove:
	@echo "Removing hosts entries (requires sudo)..."
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		sudo sed -i '' '/camunda.example.com/d' /etc/hosts; \
	else \
		sudo sed -i '/camunda.example.com/d' /etc/hosts; \
	fi
	@echo "Hosts entries removed."

.PHONY: hosts.remove-keycloak
hosts.remove-keycloak:
	@echo "Removing Keycloak host entry (requires sudo)..."
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		sudo sed -i '' '/^127\.0\.0\.1[[:space:]]\{1,\}keycloak-service$$/d' /etc/hosts; \
	else \
		sudo sed -i '/^127\.0\.0\.1[[:space:]]\{1,\}keycloak-service$$/d' /etc/hosts; \
	fi
	@echo "Keycloak host entry removed."

.PHONY: hosts.show
hosts.show:
	@echo "Hosts entries for camunda.example.com:"
	@grep "camunda.example.com" /etc/hosts || echo "  (none)"

# =============================================================================
# Certificates (mkcert)
# =============================================================================

.PHONY: certs.generate
certs.generate:
	@$(PROCEDURE_DIR)/certs-generate.sh

.PHONY: certs.create-secret
certs.create-secret:
	@$(PROCEDURE_DIR)/certs-create-secret.sh

.PHONY: certs.create-ca-configmap
certs.create-ca-configmap:
	@$(PROCEDURE_DIR)/certs-create-ca-configmap.sh

.PHONY: certs.clean
certs.clean:
	@rm -rf $(CERT_DIR)
	@echo "Certificates cleaned."

# =============================================================================
# Identity Secrets
# =============================================================================

.PHONY: identity-secrets.create
identity-secrets.create:
	@$(PROCEDURE_DIR)/create-identity-secrets.sh

# =============================================================================
# Camunda
# =============================================================================

.PHONY: camunda.deploy-domain
camunda.deploy-domain:
	@$(PROCEDURE_DIR)/camunda-deploy-domain.sh

.PHONY: camunda.deploy-no-domain
camunda.deploy-no-domain:
	@$(PROCEDURE_DIR)/camunda-deploy-no-domain.sh

.PHONY: camunda.uninstall
camunda.uninstall:
	@helm uninstall $(CAMUNDA_RELEASE_NAME) --namespace $(CAMUNDA_NAMESPACE) || true
	@kubectl delete namespace $(CAMUNDA_NAMESPACE) --ignore-not-found

.PHONY: camunda.wait
camunda.wait:
	@echo "Waiting for Camunda pods to be ready..."
	@CAMUNDA_NAMESPACE=$(CAMUNDA_NAMESPACE) ../../../generic/kubernetes/single-region/procedure/check-deployment-ready.sh

# =============================================================================
# Utilities
# =============================================================================

.PHONY: status
status:
	@echo "=== Cluster ==="
	@kind get clusters 2>/dev/null | grep -q "$(CLUSTER_NAME)" && echo "$(CLUSTER_NAME): running" || echo "$(CLUSTER_NAME): not running"
	@echo ""
	@echo "=== Pods ==="
	@kubectl get pods -n $(CAMUNDA_NAMESPACE) 2>/dev/null || echo "Namespace not found"

.PHONY: port-forward
port-forward:
	@$(PROCEDURE_DIR)/port-forward.sh

.PHONY: get-password
get-password:
	@$(PROCEDURE_DIR)/get-password.sh

.PHONY: get-keycloak-password
get-keycloak-password:
	@$(PROCEDURE_DIR)/get-keycloak-password.sh
