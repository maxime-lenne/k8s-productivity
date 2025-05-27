#!/bin/bash
set -e

# Configuration
BACKUP_DIR="/backups"
RETENTION_DAYS=7
POSTGRES_POD=$(kubectl get pods -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
TIMESTAMP=$(date +%Y%m%d%H%M%S)
NAMESPACE=${NAMESPACE:-"default"}

# Create backup directory if it doesn't exist
mkdir -p ${BACKUP_DIR}

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to backup a database
backup_database() {
  local DB_NAME=$1
  local BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql.gz"
  
  log "Backing up database: ${DB_NAME}"
  kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- pg_dump -U postgres ${DB_NAME} | gzip > ${BACKUP_FILE}
  
  if [ $? -eq 0 ]; then
    log "Backup completed successfully: ${BACKUP_FILE}"
    # Create a checksum file for verification
    md5sum ${BACKUP_FILE} > ${BACKUP_FILE}.md5
  else
    log "Backup failed for database: ${DB_NAME}"
    exit 1
  fi
}

# Function to clean up old backups
cleanup_old_backups() {
  log "Cleaning up backups older than ${RETENTION_DAYS} days"
  find ${BACKUP_DIR} -name "*.sql.gz" -mtime +${RETENTION_DAYS} -delete
  find ${BACKUP_DIR} -name "*.md5" -mtime +${RETENTION_DAYS} -delete
}

# Main execution
log "Starting PostgreSQL backup process"

# Get list of databases
DATABASES=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- psql -U postgres -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres';")

# Backup each database
for DB in ${DATABASES}; do
  DB=$(echo ${DB} | tr -d ' ')
  if [ ! -z "${DB}" ]; then
    backup_database ${DB}
  fi
done

# Clean up old backups
cleanup_old_backups

log "Backup process completed"