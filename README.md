# Guide de déploiement de l'environnement Kubernetes

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
- [Ingress, certificats & secrets](docs/ingress-certificats-secrets.md)
- [FAQ, Dépannage & Maintenance](docs/faq-depannage-maintenance.md)

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