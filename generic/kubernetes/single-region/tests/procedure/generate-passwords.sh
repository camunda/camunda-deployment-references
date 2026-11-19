#!/bin/bash

# Preserve export's masked substitution status when errexit is enabled.
CONNECTORS_SECRET="$(openssl rand -hex 16)" || true
export CONNECTORS_SECRET
CONSOLE_SECRET="$(openssl rand -hex 16)" || true
export CONSOLE_SECRET
WEB_MODELER_SECRET="$(openssl rand -hex 16)" || true
export WEB_MODELER_SECRET
ORCHESTRATION_SECRET="$(openssl rand -hex 16)" || true
export ORCHESTRATION_SECRET
OPTIMIZE_SECRET="$(openssl rand -hex 16)" || true
export OPTIMIZE_SECRET
ADMIN_PASSWORD="$(openssl rand -hex 16)" || true
export ADMIN_PASSWORD
FIRST_USER_PASSWORD="$(openssl rand -hex 16)" || true
export FIRST_USER_PASSWORD
