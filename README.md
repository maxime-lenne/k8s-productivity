# Guide de déploiement de l'environnement Kubernetes

## Table des matières
- [Prérequis](#prérequis)
- [Structure des fichiers](#structure-des-fichiers)
- [Démarrage rapide](#démarrage-rapide)
- [Gestion multi-environnement avec Kustomize](#gestion-multi-environnement-avec-kustomize)
- [Documentation détaillée](#documentation-détaillée)

Ce projet permet de déployer un environnement complet (Ingress-Nginx, PostgreSQL, Redis, N8N, Baserow) sur Kubernetes en utilisant **Kustomize** pour la gestion des configurations multi-environnements et **Sealed Secrets** pour la gestion sécurisée des secrets.

## Prérequis

- Cluster Kubernetes opérationnel
- `kubectl` configuré
- `helm` installé (pour l'installation du contrôleur Sealed Secrets)
- `kubeseal` installé localement
- Contrôleur Sealed Secrets installé dans votre cluster (généralement dans le namespace `kube-system`)
- Noms de domaine configurés pour Let's Encrypt (en prod/staging si nécessaire)

## Structure des fichiers

Voir la section dédiée ci-dessous pour l'organisation des dossiers et fichiers.

## Démarrage rapide

Ces étapes décrivent comment déployer un environnement en utilisant Kustomize. Remplacez `<environnement>` par le nom de l'environnement souhaité (par exemple, `staging`, `prod`).

1. Assurez-vous que le contrôleur Sealed Secrets est installé dans votre cluster.
2. Créez un fichier de secrets en clair pour votre environnement (par exemple, `environments/<environnement>/secrets-clear.yaml`). **Ne commitez PAS ce fichier dans Git !**
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: secrets-<environnement>
     namespace: <environnement>
   type: Opaque
   stringData:
     VOTRE_CLE_SECRETE_1: "votre_valeur_1"
     VOTRE_CLE_SECRETE_2: "votre_valeur_2"
     # ... ajoutez toutes vos clés sensibles ici ...
   ```
3. Scellez le fichier de secrets en clair en utilisant `kubeseal` pour créer le fichier `SealedSecret` chiffré. Ce fichier *peut* être commité dans Git.
   ```bash
   kubeseal -f environments/<environnement>/secrets-clear.yaml --namespace <environnement> -o yaml > environments/<environnement>/secrets-<environnement>.yaml
   # Supprimez le fichier secrets-clear.yaml après le scellement !
   rm environments/<environnement>/secrets-clear.yaml
   ```
4. Assurez-vous que votre fichier de configuration Kustomize pour l'environnement (`environments/<environnement>/kustomization.yaml`) référence la base et inclut les configurations spécifiques (comme les Sealed Secrets et les ConfigMaps générées).
5. Appliquez la configuration de l'environnement en utilisant `kubectl apply -k` :
   ```bash
   kubectl apply -k environments/<environnement>/
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
├── base/             # Manifestes Kubernetes de base (communs à tous les environnements)
├── environments/     # Configurations spécifiques à chaque environnement (overlays Kustomize)
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   └── secrets-staging.yaml  # Sealed Secrets pour staging (chiffré)
│   └── prod/
│       ├── kustomization.yaml
│       └── secrets-prod.yaml     # Sealed Secrets pour prod (chiffré)
├── certs/            # Certificats (peut inclure les clés publiques de Sealed Secrets si nécessaire)
├── scripts/          # Scripts utilitaires (les scripts de génération .env ne sont plus nécessaires avec Kustomize/Sealed Secrets)
├── docs/             # Documentation détaillée
├── sample.env        # Fichier d'exemple des variables possibles
├── README.md
└── ...
```

Notez que les fichiers `.env` par environnement et les scripts `generate-*.sh` ne sont plus utilisés pour le déploiement avec cette approche Kustomize/Sealed Secrets.

## Gestion multi-environnement avec Kustomize

Ce projet utilise **Kustomize** pour gérer les variations de configuration entre différents environnements (staging, production, etc.).

Le répertoire `base/` contient les manifestes Kubernetes de base qui sont communs à tous les environnements. Les répertoires sous `environments/` (`environments/staging/`, `environments/prod/`, etc.) contiennent des fichiers `kustomization.yaml` qui définissent les **overlays** spécifiques à chaque environnement.

Ces overlays peuvent :

*   Appliquer des patches pour modifier les ressources de base (par exemple, changer le nombre de répliques, modifier les Ingress pour utiliser les bons hostnames et certificats).
*   Générer des ConfigMaps avec des variables spécifiques à l'environnement.
*   Inclure des ressources spécifiques à l'environnement, comme les **Sealed Secrets** pour les données sensibles.

Les secrets sensibles pour chaque environnement sont gérés à l'aide de **Sealed Secrets**. Les valeurs réelles des secrets ne sont jamais stockées en clair dans le dépôt Git. Au lieu de cela, vous scellez un manifeste Secret en clair en un `SealedSecret` chiffré qui est stocké dans Git. Le contrôleur Sealed Secrets dans le cluster est le seul à pouvoir déchiffrer ce `SealedSecret` et créer le Secret Kubernetes standard correspondant.

Chaque répertoire d'environnement (`environments/<environnement>/`) doit contenir :

*   `kustomization.yaml` : Le fichier principal de Kustomize définissant l'overlay, référençant la base, les patches, les générateurs de ConfigMap, et les Sealed Secrets.
*   `secrets-<environnement>.yaml` : Le manifeste `SealedSecret` chiffré contenant les secrets sensibles pour cet environnement (peut être commité dans Git).
*   D'autres fichiers de patches ou de ressources spécifiques si nécessaire.

Pour déployer un environnement, utilisez simplement `kubectl apply -k environments/<environnement>/`.
