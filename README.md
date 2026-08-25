# k8s-productivity

Environnement Kubernetes complet pour déployer des outils de productivité (Baserow, N8N, Excalidraw, Metabase, Supabase) avec **Kustomize** pour la gestion multi-environnements et **Sealed Secrets** pour les secrets.

## Table des matières

- [Prérequis](#prérequis)
- [Démarrage rapide](#démarrage-rapide)
- [Documentation](#documentation)
- [Structure du projet](#structure-du-projet)
- [Gestion multi-environnement](#gestion-multi-environnement)

---

## Prérequis

- Cluster Kubernetes opérationnel
- `kubectl` configuré
- `helm` installé (pour l'installation du contrôleur Sealed Secrets)
- `kubeseal` installé localement
- Contrôleur Sealed Secrets installé dans votre cluster
- Noms de domaine configurés (pour les environnements cloud)

---

## Démarrage rapide

### Environnement local (Mac)

```bash
# Appliquer la configuration Kustomize
kubectl apply -k environments/local/

# Démarrer l'accès aux services
./scripts/local/setup-access.sh

# Pour l'accès depuis d'autres appareils du réseau
sudo ./scripts/local/setup-access.sh --network
```

### Environnement cloud (Scaleway)

```bash
# Se connecter au cluster
export KUBECONFIG=./environments/<env>/kubeconfig.yaml

# Créer le namespace
kubectl create namespace <env>

# Appliquer la configuration
kubectl apply -k environments/<env>/
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Déploiement Local](docs/local-deployment.md) | Guide complet pour Mac avec Docker Desktop, incluant l'accès réseau local |
| [Déploiement Scaleway](docs/scaleway-deployment.md) | Guide pour déployer sur Scaleway Kubernetes |
| [Certificats & Secrets](docs/certificats-secrets.md) | Gestion des certificats SSL, secrets, et backups PostgreSQL |
| [FAQ & Support](docs/faq-support.md) | Dépannage, maintenance et questions fréquentes |

---

## Structure du projet

```
k8s-productivity/
├── base/                 # Manifestes Kubernetes de base
│   ├── baserow/
│   ├── n8n/
│   ├── excalidraw/
│   ├── metabase/
│   ├── supabase/
│   ├── postgresql/
│   ├── redis/
│   ├── ingress-nginx/
│   └── cert-managers/
├── environments/         # Overlays Kustomize par environnement
│   ├── local/
│   │   ├── kustomization.yaml
│   │   └── secrets-local.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── secrets-staging.yaml
│   └── prod/
│       ├── kustomization.yaml
│       └── secrets-prod.yaml
├── scripts/              # Scripts utilitaires
│   ├── local/
│   │   ├── setup-access.sh
│   │   ├── stop-access.sh
│   │   └── install-dnsmasq.sh
│   └── backup/
│       ├── postgres-backup.sh
│       └── postgres-restore.sh
├── docs/                 # Documentation
│   ├── local-deployment.md
│   ├── scaleway-deployment.md
│   ├── certificats-secrets.md
│   └── faq-support.md
└── README.md
```

---

## Gestion multi-environnement

Ce projet utilise **Kustomize** pour gérer les variations de configuration.

### Structure Kustomize

- `base/` : Manifestes Kubernetes communs à tous les environnements
- `environments/<env>/` : Overlays spécifiques par environnement

### Overlays

Les overlays permettent de :
- Appliquer des patches (répliques, hostnames, certificats)
- Générer des ConfigMaps avec variables spécifiques
- Inclure des Sealed Secrets pour les données sensibles

### Déploiement

```bash
kubectl apply -k environments/<environnement>/
```

### Workflow des secrets

1. Copier le template : `cp environments/secrets-sample.yaml environments/<env>/secrets-clear.yaml`
2. Éditer les valeurs sensibles
3. Sceller : `kubeseal -f secrets-clear.yaml --namespace <env> -o yaml > secrets-<env>.yaml`
4. Supprimer le fichier en clair : `rm secrets-clear.yaml`
5. Déployer : `kubectl apply -k environments/<env>/`

---

## Services déployés

| Service | Description | Port par défaut |
|---------|-------------|-----------------|
| **Baserow** | Base de données no-code | 443 |
| **N8N** | Automatisation de workflows | 443 |
| **Excalidraw** | Tableau blanc collaboratif | 443 |
| **Metabase** | Business Intelligence | 443 |
| **Supabase** | Backend-as-a-Service | 443 |

---

## Scripts disponibles

### Accès local

```bash
# Démarrer l'accès local (127.0.0.1)
./scripts/local/setup-access.sh

# Démarrer l'accès local avec ports personnalisés
./scripts/local/setup-access.sh --http-port 8080 --https-port 8443

# Démarrer l'accès réseau (0.0.0.0, nécessite sudo)
sudo ./scripts/local/setup-access.sh --network

# Démarrer l'accès réseau avec ports personnalisés
sudo ./scripts/local/setup-access.sh --network --http-port 8880 --https-port 9443

# Utiliser des variables d'environnement pour les ports
K8S_HTTP_PORT=8080 K8S_HTTPS_PORT=8443 ./scripts/local/setup-access.sh

# Arrêter l'accès
./scripts/local/stop-access.sh
```

**Note** : Si les ports 80/443 (ou 8080/8443) sont déjà utilisés, le script détecte automatiquement des ports alternatifs disponibles.

### DNS réseau local

```bash
# Installer et configurer dnsmasq
./scripts/local/install-dnsmasq.sh
```

### Backup PostgreSQL

```bash
# Sauvegarder
./scripts/backup/postgres-backup.sh

# Restaurer
./scripts/backup/postgres-restore.sh --list
./scripts/backup/postgres-restore.sh /backups/<backup-file>.sql.gz
```

---

## Licence

MIT
