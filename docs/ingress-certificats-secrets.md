# Ingress, certificats & secrets

Ce document décrit la gestion des Ingress, des certificats SSL/TLS et des secrets dans ce projet, en utilisant **Kustomize** pour la gestion des configurations par environnement et **Sealed Secrets** pour les secrets sensibles.

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
- [Variables d'environnement (ConfigMaps et Secrets)](#variables-denvironnement-configmaps-et-secrets)
- [Utilisation (Déploiement avec Kustomize)](#utilisation-déploiement-avec-kustomize)
- [Secrets (avec Sealed Secrets)](#secrets-avec-sealed-secrets)
- [Gestion multi-environnement avec Kustomize](#gestion-multi-environnement-avec-kustomize-1)

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

## Variables d'environnement (ConfigMaps et Secrets)

Les applications (Baserow, N8N, etc.) consomment leurs configurations via des variables d'environnement, qui sont injectées à partir de ConfigMaps et de Secrets.

*   **Variables non sensibles :** (URLs, noms d'utilisateurs, noms de bases de données, configurations diverses) sont stockées dans des **ConfigMaps**. Pour chaque environnement, une ConfigMap est générée par Kustomize en utilisant la section `configMapGenerator` dans le fichier `environments/<environnement>/kustomization.yaml`. Kustomize ajoute un hash au nom de la ConfigMap générée.
*   **Secrets sensibles :** (Mots de passe, clés secrètes) sont stockés dans des **Secrets**, qui sont créés à partir des manifestes `SealedSecret` déchiffrés par le contrôleur Sealed Secrets (comme décrit dans la section [Configuration des secrets (avec Sealed Secrets)](#configuration-des-secrets-avec-sealed-secrets)). Les noms de ces Secrets sont ceux définis dans le manifeste Secret original avant scellement.

Les déploiements des applications dans le répertoire `base/` référencent ces variables en utilisant `valueFrom` avec `configMapKeyRef` (pour les ConfigMaps) ou `secretKeyRef` (pour les Secrets). Kustomize (pour les ConfigMaps générées) et le contrôleur Sealed Secrets (pour les Secrets déchiffrés) s'assurent que les déploiements référencent les bonnes ressources avec les noms corrects.

## Utilisation (Déploiement avec Kustomize)

Le déploiement ou la mise à jour de l'environnement se fait en appliquant la kustomization de l'environnement souhaité. Assurez-vous d'abord que les secrets sensibles pour l'environnement ont été scellés et que le fichier `SealedSecret` chiffré est présent dans le répertoire de l'environnement et référencé dans `kustomization.yaml`.

Utilisez la commande suivante :

```bash
kubectl apply -k environments/<environnement>/
```

Remplacez `<environnement>` par le nom du répertoire de l'environnement (par exemple, `staging`, `prod`).

Cette commande :
1.  Combine les manifestes de base (`base/`) avec les overlays spécifiques à l'environnement (`environments/<environnement>/`).
2.  Génère les ConfigMaps avec les variables non sensibles.
3.  Inclut le manifeste `SealedSecret` chiffré.
4.  Applique l'ensemble des ressources générées à votre cluster dans le namespace défini par la kustomization de l'environnement.

Le contrôleur Sealed Secrets dans le cluster interceptera le `SealedSecret`, le déchiffrera et créera le Secret Kubernetes standard correspondant, permettant aux déploiements de l'utiliser.

## Spécificités des environnements

Les spécificités de chaque environnement (domaines, émetteurs de certificats, etc.) sont définies dans les fichiers `kustomization.yaml` de leurs répertoires respectifs sous `environments/`.

Par exemple, pour l'environnement `staging`, les patches définissent les hostnames spécifiques de staging et l'utilisation de l'émetteur Let's Encrypt de production pour les certificats.

## Configuration globale (ConfigMap)

Une ConfigMap de base pour la configuration globale de l'Ingress Nginx peut être définie dans `base/ingress-nginx/ingress-nginx-config.yaml` et incluse dans la base Kustomize. Les paramètres globaux (comme la redirection SSL par défaut) peuvent être surchargés par des annotations dans les manifestes Ingress spécifiques à l'application (qui sont patchés par les overlays d'environnement).

## Certificats

Les certificats SSL/TLS sont gérés par **cert-manager**. L'émetteur de certificat à utiliser (par exemple, `letsencrypt-prod` pour la production, un auto-signé pour le local) est spécifié via une annotation (`cert-manager.io/cluster-issuer`) dans le manifeste Ingress de l'environnement, définie dans le patch de l'overlay Kustomize (voir [Configuration des Ingress](#configuration-des-ingress-avec-kustomize-overlays)).

Les Secrets contenant les certificats sont créés automatiquement par cert-manager une fois que l'Ingress est appliqué et que le challenge de validation est réussi.

## Secrets (avec Sealed Secrets)

Comme détaillé dans la section [Configuration des secrets (avec Sealed Secrets)](#configuration-des-secrets-avec-sealed-secrets), les secrets sensibles sont gérés par Sealed Secrets. Les déploiements des applications référencent ces secrets par leurs noms.

## Gestion multi-environnement avec Kustomize

Cette section renvoie à la documentation détaillée sur la [Gestion multi-environnement avec Kustomize](#gestion-multi-environnement-avec-kustomize) dans le `README.md` principal, qui décrit la structure et le fonctionnement général des overlays. 