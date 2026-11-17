#!/bin/bash

CONNECTORS_SECRET="$(openssl rand -hex 16)"
export CONNECTORS_SECRET
WEB_MODELER_SECRET="$(openssl rand -hex 16)"
export WEB_MODELER_SECRET
ORCHESTRATION_SECRET="$(openssl rand -hex 16)"
export ORCHESTRATION_SECRET
OPTIMIZE_SECRET="$(openssl rand -hex 16)"
export OPTIMIZE_SECRET
ADMIN_PASSWORD="$(openssl rand -hex 16)"
export ADMIN_PASSWORD
FIRST_USER_PASSWORD="$(openssl rand -hex 16)"
export FIRST_USER_PASSWORD
