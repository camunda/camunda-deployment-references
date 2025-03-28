# PostgreSQL Connection Information
# Generated for testing purposes - DO NOT USE IN PRODUCTION

Server: ${server_name}
Admin User: ${admin_user}
Admin Password: ${admin_pass}

# Database Connections:
%{ for db_key, db in databases ~}
## ${db_key} Database
Database Name: ${db.name}
Username: ${db.username}
Password: ${db.password}
Connection String: postgresql://${db.username}:${db.password}@${server_name}:5432/${db.name}

%{ endfor ~}

# Test Commands:
# You can verify connections with:
# psql -h ${server_name} -U ${admin_user} -d postgres -c "SELECT 1;"
