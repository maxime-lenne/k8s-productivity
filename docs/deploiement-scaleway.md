# Déploiement & Scaleway

Ce document détaille les étapes pour déployer l'environnement Kubernetes sur Scaleway, en utilisant **Kustomize** pour la gestion des configurations par environnement et **Sealed Secrets** pour les secrets.

> Voir aussi : [Ingress, certificats & secrets](./ingress-certificats-secrets.md) | [FAQ, Dépannage & Maintenance](./faq-depannage-maintenance.md)

## Table des matières
- [Prérequis](#prérequis)
- [Configuration de kubectl pour Scaleway](#configuration-de-kubectl-pour-scaleway)
- [Création de l'environement sur Scaleway](#création-de-lenvironement-sur-scaleway)
- [Configuration du DNS](#configuration-du-dns)
- [Installation des composants](#installation-des-composants)
- [Déploiement des applications](#déploiement-des-applications)
- [Maintenance](#maintenance)
- [Gestion multi-environnement](#gestion-multi-environnement)

## Prérequis

- Cluster Kubernetes opérationnel sur Scaleway
- `kubectl` configuré pour votre cluster Scaleway
- `helm` installé (pour l'installation initiale d'Ingress-Nginx et Cert-Manager, si non inclus dans la base Kustomize)
- `kubeseal` installé localement
- Contrôleur Sealed Secrets installé dans votre cluster Scaleway (généralement dans le namespace `kube-system`)
- Pour Let's Encrypt : des noms de domaine pointant vers l'IP publique de votre LoadBalancer Ingress-Nginx

## Configuration de kubectl pour Scaleway

### 1. Installation du CLI Scaleway

```bash
# Sur macOS avec Homebrew
brew install scw

# Sur Linux
wget https://github.com/scaleway/scaleway-cli/releases/download/v2.19.0/scaleway-cli_2.19.0_linux_amd64
chmod +x scaleway-cli_2.19.0_linux_amd64
sudo mv scaleway-cli_2.19.0_linux_amd64 /usr/local/bin/scw
```

### 2. Authentification

```bash
# Initialiser la configuration
scw init

# Vous devrez fournir :
# - Organization ID (trouvable dans la console Scaleway)
# - Access Key (trouvable dans la console Scaleway)
# - Secret Key (trouvable dans la console Scaleway)
# - Default region (fr-par)
# - Default zone (fr-par-1)
```

### 3. Configuration de kubectl

```bash
# Récupérer le kubeconfig de votre cluster
scw k8s kubeconfig get <nom-du-cluster> > kubeconfig.yaml

# Configurer kubectl pour utiliser ce kubeconfig
export KUBECONFIG=./kubeconfig.yaml

# Pour rendre la configuration permanente, ajoutez à votre ~/.bashrc ou ~/.zshrc :
echo 'export KUBECONFIG=./kubeconfig.yaml' >> ~/.bashrc
```

### 3.1 Configuration de k9s (optionel)

k9s utilise automatiquement la configuration de kubectl, donc il n'y a pas de configuration supplémentaire nécessaire.

```bash
# Installation de k9s
# Sur macOS avec Homebrew
brew install k9s

# Sur Linux
wget https://github.com/derailed/k9s/releases/download/v0.32.3/k9s_Linux_amd64.tar.gz
tar -xf k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/

# Lancer k9s
k9s
```

Raccourcis utiles dans k9s :
- `:context` : Changer de contexte
- `:namespace` : Changer de namespace
- `:pods` : Voir les pods
- `:services` : Voir les services
- `:ingress` : Voir les ingress
- `:deployments` : Voir les déploiements
- `:configmaps` : Voir les configmaps
- `:secrets` : Voir les secrets
- `:events` : Voir les événements
- `?` : Afficher l'aide
- `esc` : Retourner au menu précédent
- `:q` : Quitter k9s

### 4. Vérification

```bash
# Vérifier que vous êtes bien connecté au bon cluster
kubectl config current-context

# Vérifier l'accès au cluster
kubectl get nodes
```

### 5. Gestion des contextes

Si vous gérez plusieurs clusters :

```bash
# Lister tous les contextes
kubectl config get-contexts

# Changer de contexte
kubectl config use-context <nom-du-contexte>

# Ajouter un nouveau contexte
kubectl config set-context <nom-du-contexte> --cluster=<nom-du-cluster> --user=<nom-utilisateur>
```

### 6. Dépannage

Si vous rencontrez des problèmes d'authentification :

```bash
# Vérifier les credentials
scw k8s kubeconfig get <nom-du-cluster> --debug

# Régénérer le kubeconfig
scw k8s kubeconfig reset <nom-du-cluster>

# Vérifier les permissions
scw k8s cluster get <nom-du-cluster>
```

## Création de l'environement sur Scaleway

### Prérequis

1. Installer le CLI Scaleway :
```bash
brew install scw
```

2. Se connecter à votre compte Scaleway :
```bash
scw init
```

### Création du cluster

1. Créer un cluster Kubernetes sur Scaleway :
```bash
scw k8s cluster create \
  name=productivity-cluster \
  version=1.28.0 \
  cni=cilium \
  pools.0.name=default \
  pools.0.node-type=DEV1-M \
  pools.0.size=3 \
  region=fr-par
```

2. Récupérer le kubeconfig :
```bash
scw k8s kubeconfig get productivity-cluster > kubeconfig.yaml
```

3. Configurer kubectl pour utiliser le cluster :
```bash
export KUBECONFIG=./kubeconfig.yaml
```

### Configuration du DNS

1. Créer une zone DNS sur Scaleway pour vos domaines :
```bash
scw dns zone create domain=example.com
```

2. Ajouter les enregistrements A pour vos domaines, pointant vers l'IP publique du LoadBalancer Ingress-Nginx. Remplacez `example.com` et les sous-domaines par les vôtres :
```bash
# Récupérer l'IP du LoadBalancer Ingress-Nginx
export INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Exemple d'ajout d'enregistrements A (à adapter)
# Pour le domaine racine (si nécessaire)
scw dns record create \
  zone-id=<votre-zone-id> \
  name=@ \
  type=A \
  data=$INGRESS_IP

# Pour les sous-domaines (baserow, n8n, etc.)
scw dns record create \
  zone-id=<votre-zone-id> \
  name=baserow \
  type=A \
  data=$INGRESS_IP

scw dns record create \
  zone-id=<votre-zone-id> \
  name=n8n \
  type=A \
  data=$INGRESS_IP
```

## Installation des composants

### 1. Ingress-Nginx Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
```

### 2. Cert-Manager (pour HTTPS)

Installez cert-manager et ses CRDs :
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
```

Installez également le contrôleur Sealed Secrets dans votre cluster, si ce n'est pas déjà fait. Voir le README pour les instructions d'installation avec Helm.

## Déploiement des applications

Le déploiement des applications (PostgreSQL, Redis, N8N, Baserow) et de leurs configurations spécifiques à l'environnement est géré par Kustomize.

Chaque environnement (staging, prod, etc.) a un répertoire dédié sous `environments/` contenant un fichier `kustomization.yaml` qui définit l'overlay pour cet environnement.

Les variables spécifiques à l'environnement (domaines, noms d'utilisateurs de bases de données, etc.) sont gérées via des ConfigMaps générées par Kustomize. Les secrets sensibles (mots de passe, clés secrètes) sont gérés à l'aide de Sealed Secrets.

Pour déployer ou mettre à jour un environnement :

1.  Assurez-vous d'avoir un fichier de secrets *en clair* pour l'environnement, par exemple `environments/<environnement>/secrets-clear.yaml`. **Ce fichier NE doit PAS être commité dans Git !** Il doit contenir les variables sensibles spécifiques à cet environnement sous forme de manifeste Secret Kubernetes standard.
    ```yaml
    # Exemple de environments/staging/secrets-clear.yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: secrets-staging # Nom du Secret qui sera créé dans le cluster
      namespace: staging
    type: Opaque
    stringData:
      REDIS_PASSWORD: "votre_mdp_redis_staging"
      POSTGRES_PASSWORD: "votre_mdp_postgres_staging"
      # ... autres secrets sensibles ...
    ```

2.  Utilisez `kubeseal` pour sceller ce fichier et créer le manifeste `SealedSecret` chiffré. Ce fichier `secrets-<environnement>.yaml` *peut* être commité dans Git.
    ```bash
    kubeseal -f environments/<environnement>/secrets-clear.yaml --namespace <environnement> -o yaml > environments/<environnement>/secrets-<environnement>.yaml
    # Supprimez le fichier secrets-clear.yaml après le scellement !
    rm environments/<environnement>/secrets-clear.yaml
    ```

3.  Assurez-vous que le fichier `environments/<environnement>/kustomization.yaml` est correctement configuré pour inclure le `SealedSecret` (via la section `resources`) et générer la ConfigMap (via `configMapGenerator`) avec les variables non sensibles spécifiques à l'environnement.

4.  Appliquez la configuration de l'environnement à votre cluster en utilisant la commande `kubectl apply -k` :
    ```bash
    kubectl apply -k environments/<environnement>/
    ```

    Remplacez `<environnement>` par le nom du répertoire de l'environnement (par exemple, `staging`).

Les ressources définies dans `base/` seront appliquées, patchées selon l'overlay de l'environnement, le `SealedSecret` sera déchiffré par le contrôleur Sealed Secrets dans le cluster pour créer un Secret standard, et la ConfigMap sera générée.

## Maintenance

Pour mettre à jour les applications :
```bash
# Mettre à jour les images
kubectl set image deployment/baserow baserow=baserow/baserow:latest -n productivity
kubectl set image deployment/n8n n8n=n8nio/n8n:latest -n productivity

# Vérifier le déploiement
kubectl rollout status deployment/baserow -n productivity
kubectl rollout status deployment/n8n -n productivity
```

Pour redémarrer les applications :
```bash
kubectl rollout restart deployment/baserow -n productivity
kubectl rollout restart deployment/n8n -n productivity
```

## Gestion multi-environnement

Cette section est couverte par l'utilisation de Kustomize. Voir [Gestion multi-environnement avec Kustomize](#gestion-multi-environnement-avec-kustomize) dans le README principal. 