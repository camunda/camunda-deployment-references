#!/bin/bash

export CONNECTORS_SECRET="$(openssl rand -hex 16)"
export CONSOLE_SECRET="$(openssl rand -hex 16)"
export WEB_MODELER_SECRET="$(openssl rand -hex 16)"
export ORCHESTRATION_SECRET="$(openssl rand -hex 16)"
export OPTIMIZE_SECRET="$(openssl rand -hex 16)"
export ADMIN_PASSWORD="$(openssl rand -hex 16)"
export FIRST_USER_PASSWORD="$(openssl rand -hex 16)"
