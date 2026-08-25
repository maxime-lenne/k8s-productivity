# Certificats & Secrets

Ce document décrit la gestion des Ingress, des certificats SSL/TLS, des secrets et des sauvegardes PostgreSQL dans ce projet.

> Voir aussi : [Déploiement Local](./local-deployment.md) | [Déploiement Scaleway](./scaleway-deployment.md) | [FAQ & Support](./faq-support.md)

## Table des matières

- [Configuration des Ingress](#configuration-des-ingress)
- [Certificats SSL/TLS](#certificats-ssltls)
- [Gestion des secrets](#gestion-des-secrets)
- [Variables d'environnement](#variables-denvironnement)
- [Backup et Restore PostgreSQL](#backup-et-restore-postgresql)

---

## Configuration des Ingress

Ce projet utilise **Nginx Ingress Controller** pour gérer l'accès aux services.

### Fichiers de configuration

- `base/ingress-nginx/ingress-nginx-configmap.yaml` : Configuration globale de l'ingress-controller
- `environments/staging/apps-tls-staging-cert.yaml` : Certificat pour staging
- `environments/prod/apps-tls-prod-cert.yaml` : Certificat pour production

### Configuration globale (ConfigMap)

Le ConfigMap `ingress-nginx-controller` définit les paramètres globaux :

```yaml
data:
  ssl-redirect: "false"
  force-ssl-redirect: "false"
```

Ces paramètres peuvent être surchargés au niveau de chaque ingress via des annotations.

### Spécificités par environnement

#### Environnement Local

- Utilise des certificats auto-signés via `selfsigned-issuer`
- SSL redirect désactivé par défaut
- Accessible via :
  - https://baserow.white-wood.local
  - https://n8n.white-wood.local
  - https://excalidraw.white-wood.local
  - https://metabase.white-wood.local
  - https://supabase.white-wood.local

#### Environnement Production

- Utilise Let's Encrypt pour les certificats via `letsencrypt-prod`
- Force la redirection SSL
- Accessible via vos domaines configurés

---

## Certificats SSL/TLS

Les certificats sont gérés par **cert-manager**.

### Let's Encrypt (Production/Staging)

Pour les environnements cloud, le projet utilise des certificats Let's Encrypt. Le challenge HTTP-01 est utilisé pour valider les domaines.

```bash
# Vérifier l'état des certificats
kubectl get certificate -n <namespace>
kubectl describe certificate <nom-du-cert> -n <namespace>

# Vérifier les challenges en cours
kubectl get challenges -n <namespace>
```

### Certificats auto-signés (Local)

Pour l'environnement local, des certificats auto-signés sont générés automatiquement :

```bash
# Vérifier le ClusterIssuer
kubectl get clusterissuer selfsigned-issuer

# Vérifier les certificats générés
kubectl get certificate
kubectl get secret apps-tls-local-cert
```

### Configuration dans les Ingress

L'émetteur de certificat est spécifié via une annotation :

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: selfsigned-issuer  # ou letsencrypt-prod
spec:
  tls:
    - hosts:
        - baserow.white-wood.local
      secretName: apps-tls-local-cert
```

---

## Gestion des secrets

### Workflow avec Sealed Secrets

Les secrets sensibles sont gérés avec **Sealed Secrets**. Le workflow :

1. **Créer un fichier de secrets en clair** (ne jamais commiter !)
   ```bash
   cp environments/secrets-sample.yaml environments/<env>/secrets-clear.yaml
   ```

2. **Éditer les valeurs**
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: secrets-staging
     namespace: staging
   type: Opaque
   stringData:
     REDIS_PASSWORD: "votre_mdp_redis"
     POSTGRES_PASSWORD: "votre_mdp_postgres"
     # ... autres secrets ...
   ```

3. **Sceller le secret**
   ```bash
   kubeseal -f environments/<env>/secrets-clear.yaml \
     --namespace <env> \
     -o yaml > environments/<env>/secrets-<env>.yaml
   ```

4. **Supprimer le fichier en clair**
   ```bash
   rm environments/<env>/secrets-clear.yaml
   ```

5. **Référencer dans kustomization.yaml**
   ```yaml
   resources:
     - secrets-<env>.yaml
   ```

6. **Appliquer**
   ```bash
   kubectl apply -k environments/<env>/
   ```

### Vérification des secrets

```bash
# Voir les SealedSecrets
kubectl get sealedsecrets -n <namespace>

# Voir les Secrets créés
kubectl get secrets -n <namespace>

# Vérifier qu'un secret a été correctement déchiffré
kubectl describe secret <nom-du-secret> -n <namespace>
```

### Bonnes pratiques

- **Ne jamais commiter de secrets en clair** dans le dépôt Git
- Les fichiers `secrets-<env>.yaml` (chiffrés) peuvent être commités
- Le contrôleur Sealed Secrets ne doit être installé qu'une seule fois par cluster
- Utilisez des mots de passe forts et uniques pour chaque environnement

---

## Variables d'environnement

### Variables non sensibles (ConfigMaps)

Injectées via ConfigMap générée par Kustomize :

```yaml
# Dans kustomization.yaml
configMapGenerator:
  - name: app-config
    literals:
      - POSTGRES_USER=postgres
      - N8N_DB_NAME=n8n_db
      - BASEROW_DOMAIN=baserow.white-wood.local
      # ...
```

### Variables sensibles (Secrets)

Injectées via Secret, scellé avec SealedSecrets :

```yaml
# Dans le déploiement
env:
  - name: POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgresql-secret
        key: POSTGRES_PASSWORD
```

### Référencement dans les déploiements

```yaml
env:
  # Depuis une ConfigMap
  - name: BASEROW_DOMAIN
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: BASEROW_DOMAIN

  # Depuis un Secret
  - name: SECRET_KEY
    valueFrom:
      secretKeyRef:
        name: baserow-secret
        key: SECRET_KEY
```

---

## Backup et Restore PostgreSQL

### Scripts disponibles

Les scripts de backup/restore se trouvent dans `scripts/backup/`.

### Script de Backup

Le script `postgres-backup.sh` effectue des sauvegardes automatiques :

**Fonctionnalités** :
- Sauvegarde toutes les bases de données non-template
- Compression avec gzip
- Création de checksums MD5 pour vérification
- Politique de rétention configurable
- Logging horodaté

**Configuration** :
```bash
BACKUP_DIR="/backups"      # Répertoire de stockage
RETENTION_DAYS=7           # Nombre de jours de rétention
NAMESPACE="default"        # Namespace Kubernetes
```

**Utilisation** :
```bash
./scripts/backup/postgres-backup.sh
```

### Script de Restore

Le script `postgres-restore.sh` restaure les bases de données :

**Fonctionnalités** :
- Liste les backups disponibles
- Vérifie l'intégrité via checksums MD5
- Supprime la base existante si nécessaire
- Crée et restaure la nouvelle base
- Logging horodaté

**Utilisation** :
```bash
# Lister les backups disponibles
./scripts/backup/postgres-restore.sh --list

# Restaurer un backup spécifique
./scripts/backup/postgres-restore.sh /backups/database_name_20230101120000.sql.gz

# Restaurer vers une autre base
./scripts/backup/postgres-restore.sh /backups/database_name_20230101120000.sql.gz new_database_name
```

### Planification des backups (CronJob)

Pour automatiser les sauvegardes, créez un CronJob Kubernetes :

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 1 * * *"  # Tous les jours à 1h00
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

### Bonnes pratiques de backup

1. **Tests réguliers** : Testez périodiquement le processus de restauration
2. **Stockage multiple** : Stockez les backups dans plusieurs emplacements (cloud storage)
3. **Monitoring** : Configurez des alertes en cas d'échec de backup
4. **Sécurité** : Sécurisez l'accès aux fichiers de backup et chiffrez-les si nécessaire

### Dépannage backup/restore

**Problèmes de backup** :
```bash
# Vérifier que PostgreSQL est actif
kubectl get pods -l app=postgresql

# Vérifier que le répertoire de backup existe et est accessible
kubectl exec -it <postgres-pod> -- ls -la /backups

# Consulter les logs du job
kubectl logs <job-pod-name>
```

**Problèmes de restore** :
```bash
# Vérifier que le fichier de backup existe
ls -la /backups/

# Vérifier le checksum
md5sum /backups/<backup-file>.sql.gz

# Vérifier les ressources PostgreSQL
kubectl top pod <postgres-pod>
```

---

## Gestion multi-environnement

Les spécificités (domaines, émetteurs de certificats, etc.) sont définies dans les fichiers `kustomization.yaml` de chaque overlay sous `environments/`.

Pour plus de détails sur la structure Kustomize, consultez le [README principal](../README.md).
