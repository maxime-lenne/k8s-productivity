# PostgreSQL Backup and Restore

This directory contains scripts for backing up and restoring PostgreSQL databases in the Kubernetes environment.

## Backup Script

The `postgres-backup.sh` script performs automated backups of all PostgreSQL databases with retention policies.

### Features

- Backs up all non-template databases in the PostgreSQL instance
- Compresses backups using gzip
- Creates MD5 checksums for backup verification
- Implements retention policies to automatically remove old backups
- Logs all operations with timestamps

### Configuration

Edit the script to configure the following variables:

- `BACKUP_DIR`: Directory where backups will be stored (default: `/backups`)
- `RETENTION_DAYS`: Number of days to keep backups (default: 7)
- `NAMESPACE`: Kubernetes namespace where PostgreSQL is deployed (default: "default")

### Usage

```bash
# Run the backup script
./postgres-backup.sh
```

### Scheduling Backups

To schedule regular backups, create a Kubernetes CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 1 * * *"  # Run daily at 1:00 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: postgres-backup
            image: bitnami/kubectl:latest
            command:
            - /bin/bash
            - -c
            - /scripts/postgres-backup.sh
            volumeMounts:
            - name: backup-scripts
              mountPath: /scripts
            - name: backup-volume
              mountPath: /backups
          restartPolicy: OnFailure
          volumes:
          - name: backup-scripts
            configMap:
              name: backup-scripts
              defaultMode: 0755
          - name: backup-volume
            persistentVolumeClaim:
              claimName: postgres-backup-pvc
```

## Restore Script

The `postgres-restore.sh` script restores databases from backups created by the backup script.

### Features

- Lists available backups
- Verifies backup integrity using MD5 checksums
- Drops existing database if it exists
- Creates a new database and restores data from backup
- Logs all operations with timestamps

### Configuration

Edit the script to configure the following variables:

- `BACKUP_DIR`: Directory where backups are stored (default: `/backups`)
- `NAMESPACE`: Kubernetes namespace where PostgreSQL is deployed (default: "default")

### Usage

```bash
# List available backups
./postgres-restore.sh --list

# Restore a specific database from backup
./postgres-restore.sh /backups/database_name_20230101120000.sql.gz

# Restore to a different database name
./postgres-restore.sh /backups/database_name_20230101120000.sql.gz new_database_name
```

## Best Practices

1. **Regular Testing**: Periodically test the restore process to ensure backups are valid
2. **Multiple Backup Locations**: Store backups in multiple locations (e.g., cloud storage)
3. **Monitoring**: Set up monitoring to alert on backup failures
4. **Documentation**: Keep documentation up-to-date with any changes to the backup/restore process
5. **Security**: Secure access to backup files and ensure they are encrypted if they contain sensitive data

## Troubleshooting

### Backup Issues

- Check if the PostgreSQL pod is running: `kubectl get pods -l app=postgresql`
- Verify the backup directory exists and is writable
- Check logs for error messages: `kubectl logs <job-pod-name>`

### Restore Issues

- Verify the backup file exists and is readable
- Check if the MD5 checksum file exists and matches the backup file
- Ensure the PostgreSQL pod has sufficient resources for the restore operation
- Check logs for error messages during the restore process