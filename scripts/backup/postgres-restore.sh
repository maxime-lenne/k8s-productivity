#!/bin/bash
set -e

# Configuration
BACKUP_DIR="/backups"
POSTGRES_POD=$(kubectl get pods -l app=postgresql -o jsonpath='{.items[0].metadata.name}')
NAMESPACE=${NAMESPACE:-"default"}

# Function to log messages
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to list available backups
list_backups() {
  log "Available backups:"
  find ${BACKUP_DIR} -name "*.sql.gz" | sort
}

# Function to verify backup integrity
verify_backup() {
  local BACKUP_FILE=$1
  local CHECKSUM_FILE="${BACKUP_FILE}.md5"
  
  if [ ! -f "${CHECKSUM_FILE}" ]; then
    log "Error: Checksum file not found for ${BACKUP_FILE}"
    return 1
  fi
  
  log "Verifying backup integrity: ${BACKUP_FILE}"
  cd $(dirname ${BACKUP_FILE})
  md5sum -c ${CHECKSUM_FILE} > /dev/null
  
  if [ $? -eq 0 ]; then
    log "Backup integrity verified"
    return 0
  else
    log "Error: Backup integrity check failed"
    return 1
  fi
}

# Function to restore a database
restore_database() {
  local BACKUP_FILE=$1
  local DB_NAME=$2
  
  # Extract database name from backup file if not provided
  if [ -z "${DB_NAME}" ]; then
    DB_NAME=$(basename ${BACKUP_FILE} | cut -d '_' -f 1)
  fi
  
  log "Restoring database: ${DB_NAME} from ${BACKUP_FILE}"
  
  # Verify backup integrity
  verify_backup ${BACKUP_FILE}
  if [ $? -ne 0 ]; then
    log "Aborting restore due to integrity check failure"
    exit 1
  fi
  
  # Check if database exists
  DB_EXISTS=$(kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- psql -U postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'")
  
  # If database exists, drop it
  if [ "${DB_EXISTS}" = "1" ]; then
    log "Database ${DB_NAME} exists, dropping it"
    kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- psql -U postgres -c "DROP DATABASE ${DB_NAME}"
  fi
  
  # Create empty database
  log "Creating empty database: ${DB_NAME}"
  kubectl exec -n ${NAMESPACE} ${POSTGRES_POD} -- psql -U postgres -c "CREATE DATABASE ${DB_NAME}"
  
  # Restore from backup
  log "Restoring data from backup"
  gunzip -c ${BACKUP_FILE} | kubectl exec -i -n ${NAMESPACE} ${POSTGRES_POD} -- psql -U postgres -d ${DB_NAME}
  
  if [ $? -eq 0 ]; then
    log "Restore completed successfully for database: ${DB_NAME}"
  else
    log "Restore failed for database: ${DB_NAME}"
    exit 1
  fi
}

# Main execution
if [ $# -eq 0 ]; then
  log "Usage: $0 <backup_file> [database_name]"
  log "       $0 --list"
  exit 1
fi

if [ "$1" = "--list" ]; then
  list_backups
  exit 0
fi

BACKUP_FILE=$1
DB_NAME=$2

if [ ! -f "${BACKUP_FILE}" ]; then
  log "Error: Backup file not found: ${BACKUP_FILE}"
  exit 1
fi

restore_database ${BACKUP_FILE} ${DB_NAME}