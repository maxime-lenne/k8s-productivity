# Guide de déploiement de l'environnement Kubernetes

## Table des matières
- [Prérequis](#prérequis)
- [Structure des fichiers](#structure-des-fichiers)
- [Démarrage rapide](#démarrage-rapide)
- [Documentation détaillée](#documentation-détaillée)
- [Gestion multi-environnement](#gestion-multi-environnement)

Ce projet permet de déployer un environnement complet (Ingress-Nginx, PostgreSQL, Redis, N8N, Baserow) sur Kubernetes.

## Prérequis

- Cluster Kubernetes opérationnel
- `kubectl` configuré
- `helm` installé
- Noms de domaine configurés pour Let's Encrypt (en prod)

## Structure des fichiers

Voir la section dédiée ci-dessous pour l'organisation des dossiers et fichiers.

## Démarrage rapide

1. Copier et adapter le fichier d'environnement :
   ```bash
   cp .env.example .env
   vim .env
   ```
2. Générer les secrets Kubernetes :
   ```bash
   ./generate-secrets.sh
   ```
3. Appliquer les manifests de base :
   ```bash
   kubectl apply -f base/postgresql/postgresql-deployment.yaml
   kubectl apply -f base/redis/redis-deployment.yaml
   kubectl apply -f base/n8n/n8n-deployment.yaml
   kubectl apply -f base/baserow/baserow-deployment.yaml
   # ... et les services/secrets associés
   ```
4. Déployer l'ingress-nginx et configurer les ingress selon l'environnement :
   ```bash
   ./generate-ingress-configs.sh
   kubectl apply -f base/ingress-nginx/ingress-nginx-config.yaml
   kubectl apply -f environments/local/apps-ingress-local.yaml # ou prod/staging
   ```

## Documentation détaillée

- [Déploiement & Scaleway](docs/deploiement-scaleway.md)
    - [Prérequis](docs/deploiement-scaleway.md#prérequis)
    - [Configuration de kubectl pour Scaleway](docs/deploiement-scaleway.md#configuration-de-kubectl-pour-scaleway)
    - [Création de l'environement sur Scaleway](docs/deploiement-scaleway.md#création-de-lenvironement-sur-scaleway)
    - [Configuration du DNS](docs/deploiement-scaleway.md#configuration-du-dns)
    - [Installation des composants](docs/deploiement-scaleway.md#installation-des-composants)
    - [Déploiement des applications](docs/deploiement-scaleway.md#déploiement-des-applications)
    - [Maintenance](docs/deploiement-scaleway.md#maintenance)
  - [Ingress, certificats & secrets](docs/ingress-certificats-secrets.md)
    - [Configuration des secrets](docs/ingress-certificats-secrets.md#configuration-des-secrets)
    - [Configuration des Ingress](docs/ingress-certificats-secrets.md#configuration-des-ingress)
    - [Variables d'environnement](docs/ingress-certificats-secrets.md#variables-denvironnement)
    - [Utilisation](docs/ingress-certificats-secrets.md#utilisation)
    - [Spécificités des environnements](docs/ingress-certificats-secrets.md#spécificités-des-environnements)
    - [Configuration globale (ConfigMap)](docs/ingress-certificats-secrets.md#configuration-globale-configmap)
    - [Certificats](docs/ingress-certificats-secrets.md#certificats)
    - [Secrets](docs/ingress-certificats-secrets.md#secrets)
  - [FAQ, Dépannage & Maintenance](docs/faq-depannage-maintenance.md)
    - [FAQ](docs/faq-depannage-maintenance.md#faq)
    - [Maintenance](docs/faq-depannage-maintenance.md#maintenance)
    - [Dépannage](docs/faq-depannage-maintenance.md#dépannage)
      - [Problèmes courants](docs/faq-depannage-maintenance.md#problèmes-courants)
      - [Problèmes spécifiques à PostgreSQL sur Scaleway](docs/faq-depannage-maintenance.md#problèmes-spécifiques-à-postgresql-sur-scaleway)
      - [Problèmes avec Let's Encrypt](docs/faq-depannage-maintenance.md#problèmes-avec-lets-encrypt)
## Structure des fichiers

```
k8s-productivity/
├── base/
├── environments/
├── certs/
├── scripts/
├── docs/
├── .env, .env.example, .env.prod
├── README.md
└── ...
```

Voir la documentation pour plus de détails sur chaque dossier.

## Gestion multi-environnement

Ce projet utilise un fichier `.env` spécifique à chaque environnement :
- `.env.local` pour l'environnement local
- `.env.staging` pour l'environnement de staging
- `.env.prod` pour l'environnement de production

**Exemple :**
```bash
cp .env.example .env.local
cp .env.example .env.staging
cp .env.example .env.prod
# Modifiez chaque fichier selon vos besoins
```

Les scripts de génération prennent l'environnement en argument :
```bash
./generate-secrets.sh local
./generate-secrets.sh staging
./generate-secrets.sh prod

./generate-ingress-configs.sh local
./generate-ingress-configs.sh staging
./generate-ingress-configs.sh prod
```

Chaque script chargera automatiquement le bon fichier `.env`. 