#!/bin/sh
envsubst '${STATIC_PATH},${SERVER_PORT}' </etc/nginx/nginx.conf.template >/etc/nginx/nginx.conf
exec "$@"
