#!/bin/sh
envsubst '${STATIC_PATH},${SERVER_PORT}' </etc/nginx/nginx.conf.template >/etc/nginx/nginx.conf

# Create .htpasswd file from env vars
if [ -n "$AUTH_USER" ] && [ -n "$AUTH_PASS" ]; then
  echo "$AUTH_USER:$(openssl passwd -apr1 "$AUTH_PASS")" >/etc/nginx/.htpasswd
  chmod 644 /etc/nginx/.htpasswd
else
  echo "WARNING: AUTH_USER and AUTH_PASS not set, basic auth will fail"
fi
exec "$@"
