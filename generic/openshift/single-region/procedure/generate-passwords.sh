#!/bin/bash

export CONNECTORS_SECRET="$(openssl rand -hex 16)"
export CONSOLE_SECRET="$(openssl rand -hex 16)"
export OPERATE_SECRET="$(openssl rand -hex 16)"
export OPTIMIZE_SECRET="$(openssl rand -hex 16)"
export TASKLIST_SECRET="$(openssl rand -hex 16)"
export ZEEBE_SECRET="$(openssl rand -hex 16)"
export ADMIN_PASSWORD="$(openssl rand -hex 16)"
