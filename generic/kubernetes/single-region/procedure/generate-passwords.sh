#!/bin/bash

export CONNECTORS_SECRET="$(openssl rand -hex 16)"
export CONSOLE_SECRET="$(openssl rand -hex 16)"
export OPTIMIZE_SECRET="$(openssl rand -hex 16)"
export CORE_SECRET="$(openssl rand -hex 16)"
export ADMIN_PASSWORD="$(openssl rand -hex 16)"
export USER_PASSWORD="$(openssl rand -hex 16)"
