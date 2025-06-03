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

## Configuration des Ingress

Ce projet utilise Nginx Ingress Controller pour gérer l'accès aux services Baserow et N8N. La configuration est gérée via des variables d'environnement.


- `base/ingress-nginx/ingress-nginx-configmap.yaml` : Configuration globale de l'ingress-controller
- `environnements/staging/apps-tls-staging-cert.yaml` : Configuration du certificate pour l'environnement de staging
- `environnements/prod/apps-tls-prod-cert.yaml` : Configuration du certificate pour l'environnement de production


## Variables d'environnement
todo : ajouter du détails pour savoir à quoi elle serve

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

> **Nouveau workflow de gestion des secrets (Kustomize + SealedSecrets) :**
>
> 1. Copier `environments/secrets-sample.yaml` dans le dossier de l'environnement souhaité (ex : `environments/staging/secrets-clear.yaml`)
> 2. Adapter les valeurs et le namespace
> 3. Sceller le secret avec :
>    ```sh
>    kubeseal -f environments/staging/secrets-clear.yaml --namespace staging -o yaml > environments/staging/secrets-staging.yaml
>    rm environments/staging/secrets-clear.yaml
>    ```
> 4. S'assurer que le fichier scellé est bien référencé dans `environments/staging/kustomization.yaml`
> 5. Appliquer l'overlay avec :
>    ```sh
>    kubectl apply -k environments/staging/
>    ```
> 6. **Ne jamais commiter de secret en clair dans le dépôt.**

Les secrets sensibles sont stockés dans des SealedSecrets, scellés à partir d'un manifeste Secret en clair. Le contrôleur Sealed Secrets du cluster déchiffre ces fichiers et crée les Secrets Kubernetes standards. Les déploiements référencent ces secrets via `secretKeyRef`.

## Variables d'environnement (ConfigMaps et Secrets)

- **Variables non sensibles** : injectées via ConfigMap générée par Kustomize (`configMapGenerator` dans le `kustomization.yaml` de l'overlay).
- **Variables sensibles** : injectées via Secret, scellé avec SealedSecrets.

Les déploiements référencent ces variables via `valueFrom` (`configMapKeyRef` ou `secretKeyRef`).

## Utilisation (Déploiement avec Kustomize)

1. S'assurer que le SealedSecret est présent et référencé dans le `kustomization.yaml` de l'overlay.
2. Appliquer l'overlay :
   ```sh
   kubectl apply -k environments/<environnement>/
   ```
3. Vérifier la création des ressources :
   ```sh
   kubectl get all -n <environnement>
   kubectl get sealedsecrets -n <environnement>
   kubectl get secrets -n <environnement>
   ```

## Certificats

Les certificats SSL/TLS sont gérés par **cert-manager**. L'émetteur (`ClusterIssuer`) est défini dans les patches d'overlay Kustomize. Les secrets de certificats sont créés automatiquement par cert-manager.

## Spécificités des environnements

Les spécificités (domaines, émetteurs de certificats, etc.) sont définies dans les fichiers `kustomization.yaml` de chaque overlay sous `environments/`.

## Configuration globale (ConfigMap)

Une ConfigMap de base pour la configuration globale de l'Ingress Nginx peut être définie dans `base/ingress-nginx/ingress-nginx-config.yaml` et incluse dans la base Kustomize. Les paramètres globaux (comme la redirection SSL par défaut) peuvent être surchargés par des annotations dans les manifestes Ingress spécifiques à l'application (qui sont patchés par les overlays d'environnement).

## Certificats

Les certificats SSL/TLS sont gérés par **cert-manager**. L'émetteur de certificat à utiliser (par exemple, `letsencrypt-prod` pour la production, un auto-signé pour le local) est spécifié via une annotation (`cert-manager.io/cluster-issuer`) dans le manifeste Ingress de l'environnement, définie dans le patch de l'overlay Kustomize (voir [Configuration des Ingress](#configuration-des-ingress-avec-kustomize-overlays)).

Les Secrets contenant les certificats sont créés automatiquement par cert-manager une fois que l'Ingress est appliqué et que le challenge de validation est réussi.

## Secrets (avec Sealed Secrets)

Comme détaillé dans la section [Configuration des secrets (avec Sealed Secrets)](#configuration-des-secrets-avec-sealed-secrets), les secrets sensibles sont gérés par Sealed Secrets. Les déploiements des applications référencent ces secrets par leurs noms.

## Gestion multi-environnement avec Kustomize

Cette section renvoie à la documentation détaillée sur la [Gestion multi-environnement avec Kustomize](#gestion-multi-environnement-avec-kustomize) dans le `README.md` principal, qui décrit la structure et le fonctionnement général des overlays. 