# Ingress, certificats & secrets

> Voir aussi : [Déploiement & Scaleway](./deploiement-scaleway.md) | [FAQ, Dépannage & Maintenance](./faq-depannage-maintenance.md)

## Table des matières
- [Configuration des secrets](#configuration-des-secrets)
- [Configuration des Ingress](#configuration-des-ingress)
- [Variables d'environnement](#variables-denvironnement)
- [Utilisation](#utilisation)
- [Spécificités des environnements](#spécificités-des-environnements)
- [Configuration globale (ConfigMap)](#configuration-globale-configmap)
- [Certificats](#certificats)
- [Secrets](#secrets)
- [Gestion multi-environnement](#gestion-multi-environnement)

## Configuration des secrets

La gestion des secrets suit les bonnes pratiques de sécurité. Les secrets ne sont jamais versionnés dans Git.

1. Copiez le fichier d'exemple des variables d'environnement :
   ```bash
   cp .env.example .env
   ```

2. Modifiez le fichier `.env` avec vos propres valeurs :
   ```bash
   vim .env
   ```
   ⚠️ Ne committez JAMAIS le fichier `.env` dans Git. Il est déjà listé dans `.gitignore`.

3. Générez les secrets Kubernetes :
   ```bash
   ./generate-secrets.sh
   ```
   Cette commande va créer trois fichiers de secrets :
   - `redis-secret.yaml` : Contient le mot de passe Redis
   - `postgresql-secret.yaml` : Contient les identifiants PostgreSQL
   - `baserow-secret.yaml` : Contient les clés secrètes de Baserow

   ⚠️ Ces fichiers sont également exclus de Git via `.gitignore`.

4. Appliquez les secrets dans Kubernetes :
   ```bash
   kubectl apply -f redis-secret.yaml -f postgresql-secret.yaml -f baserow-secret.yaml
   ```

5. Créez le ConfigMap pour l'initialisation de PostgreSQL :
   ```bash
   kubectl create configmap init-script --from-file=init-databases.sh
   ```

## Configuration des Ingress

Ce projet utilise Nginx Ingress Controller pour gérer l'accès aux services Baserow et N8N. La configuration est gérée via des variables d'environnement et des scripts de génération.

- `.env` : Contient toutes les variables de configuration
- `generate-ingress-configs.sh` : Script pour générer les configurations d'ingress
- `ingress-nginx-config.yaml` : Configuration globale de l'ingress-controller (généré)
- `apps-ingress-local.yaml` : Configuration des ingress pour l'environnement local (généré)
- `apps-ingress-prod.yaml` : Configuration des ingress pour l'environnement de production (généré)

## Variables d'environnement

### Domaines
```env
# Local environment domains
BASEROW_LOCAL_DOMAIN=baserow.local
N8N_LOCAL_DOMAIN=n8n.local

# Production environment domains
BASEROW_PROD_DOMAIN=baserow.example.com
N8N_PROD_DOMAIN=n8n.example.com
```

### Configuration Ingress
```env
# Ingress configurations
INGRESS_CLASS=nginx
CERT_MANAGER_LOCAL_ISSUER=selfsigned-issuer
CERT_MANAGER_PROD_ISSUER=letsencrypt-prod

# SSL configuration
SSL_REDIRECT=false
FORCE_SSL_REDIRECT=false
```

## Utilisation

1. Modifiez les variables dans le fichier `.env` selon vos besoins

2. Générez et appliquez les configurations :
```bash
./generate-ingress-configs.sh
```

Ce script va :
- Générer le ConfigMap pour ingress-nginx avec les paramètres SSL globaux
- Créer les configurations d'ingress pour les environnements local et production
- Appliquer les configurations dans le cluster
- Redémarrer le contrôleur ingress-nginx pour appliquer les changements

## Spécificités des environnements

### Environnement Local
- Utilise des certificats auto-signés via `selfsigned-issuer`
- SSL redirect désactivé par défaut
- Accessible via :
  - https://baserow.local
  - https://n8n.local

### Environnement Production
- Utilise Let's Encrypt pour les certificats via `letsencrypt-prod`
- Force la redirection SSL
- Accessible via :
  - https://baserow.example.com
  - https://n8n.example.com

## Configuration globale (ConfigMap)

Le ConfigMap `ingress-nginx-controller` définit les paramètres globaux pour tous les ingress :
```yaml
data:
  ssl-redirect: "false"
  force-ssl-redirect: "false"
```

Ces paramètres peuvent être surchargés au niveau de chaque ingress si nécessaire.

## Certificats

### Let's Encrypt
Pour la production, le projet utilise des certificats Let's Encrypt via cert-manager. Le challenge HTTP-01 est utilisé pour valider les domaines. Voir la section "Installation des composants" dans [Déploiement & Scaleway](./deploiement-scaleway.md).

### Certificats auto-signés
Pour l'environnement local, des certificats auto-signés sont utilisés via un issuer cert-manager spécifique (`selfsigned-issuer`).

## Secrets

Les secrets sont générés à partir du script `generate-secrets.sh` et appliqués dans le cluster. Ils ne doivent jamais être versionnés dans Git.

## Gestion multi-environnement

Pour chaque environnement (local, staging, prod), créez un fichier `.env` dédié :
- `.env.local`
- `.env.staging`
- `.env.prod`

Copiez le modèle :
```bash
cp .env.example .env.local
cp .env.example .env.staging
cp .env.example .env.prod
```

Modifiez les variables selon l'environnement (domaines, secrets, émetteurs de certificats, etc.).

Pour générer les secrets et ingress pour un environnement donné :
```bash
./generate-secrets.sh local
./generate-ingress-configs.sh local

./generate-secrets.sh staging
./generate-ingress-configs.sh staging

./generate-secrets.sh prod
./generate-ingress-configs.sh prod
```

Chaque script chargera automatiquement le bon fichier `.env`. 