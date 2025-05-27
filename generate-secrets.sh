#!/bin/bash

if [ ! -f .env ]; then
    echo "Error: .env file not found"
    echo "Please copy .env.example to .env and update the values"
    exit 1
fi

# Load environment variables
source .env

# Generate Redis secret
cat << EOF > redis-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
type: Opaque
stringData:
  REDIS_PASSWORD: ${REDIS_PASSWORD}
EOF

# Generate PostgreSQL secret
cat << EOF > postgresql-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgresql-secret
type: Opaque
stringData:
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
  N8N_DB_NAME: ${N8N_DB_NAME}
  N8N_DB_USER: ${N8N_DB_USER}
  N8N_DB_PASSWORD: ${N8N_DB_PASSWORD}
  BASEROW_DB_NAME: ${BASEROW_DB_NAME}
  BASEROW_DB_USER: ${BASEROW_DB_USER}
  BASEROW_DB_PASSWORD: ${BASEROW_DB_PASSWORD}
EOF

# Generate Baserow secret
cat << EOF > baserow-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: baserow-secret
type: Opaque
stringData:
  SECRET_KEY: ${BASEROW_SECRET_KEY}
  JWT_SECRET: ${BASEROW_JWT_SECRET}
EOF

echo "Secrets generated successfully!" 