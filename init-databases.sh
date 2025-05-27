#!/bin/bash
set -e
set -u

function create_database() {
    local database=$1
    local user=$2
    local password=$3
    echo "Creating database '$database' for user '$user'"
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
        CREATE USER $user WITH PASSWORD '$password';
        CREATE DATABASE $database;
        GRANT ALL PRIVILEGES ON DATABASE $database TO $user;
        \c $database
        GRANT ALL ON SCHEMA public TO $user;
        GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $user;
        ALTER SCHEMA public OWNER TO $user;
EOSQL
}

if [ -n "$N8N_DB_NAME" ]; then
    create_database $N8N_DB_NAME $N8N_DB_USER $N8N_DB_PASSWORD
fi

if [ -n "$BASEROW_DB_NAME" ]; then
    create_database $BASEROW_DB_NAME $BASEROW_DB_USER $BASEROW_DB_PASSWORD
fi 