# Déploiement & Scaleway

> Voir aussi : [Ingress, certificats & secrets](./ingress-certificats-secrets.md) | [FAQ, Dépannage & Maintenance](./faq-depannage-maintenance.md)

## Table des matières
- [Prérequis](#prérequis)
- [Configuration de kubectl pour Scaleway](#configuration-de-kubectl-pour-scaleway)
- [Déploiement sur Scaleway](#déploiement-sur-scaleway)
- [Configuration du DNS](#configuration-du-dns)
- [Installation des composants](#installation-des-composants)
- [Déploiement des applications](#déploiement-des-applications)
- [Maintenance](#maintenance)

## Prérequis

- Kubernetes cluster opérationnel
- `kubectl` configuré pour votre cluster
- `helm` installé (pour Ingress-Nginx)
- Pour Let's Encrypt : des noms de domaine pointant vers votre cluster

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

### 3.1 Configuration de k9s

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

## Déploiement sur Scaleway

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

2. Ajouter les enregistrements A pour vos domaines :
```bash
# Récupérer l'IP du LoadBalancer
export INGRESS_IP=$(kubectl get service ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Ajouter les enregistrements A
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
helm install ingress-nginx ingress-nginx/ingress-nginx
```

### 2. Cert-Manager (pour HTTPS)

1. Installez cert-manager :
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
   ```

2. Choisissez votre configuration de certificat :

   a. Pour des certificats auto-signés (développement) :
   ```bash
   kubectl apply -f self-signed-issuer.yaml
   kubectl apply -f apps-ingress-local.yaml
   ```

   b. Pour des certificats Let's Encrypt (production) :
   1. Modifiez `letsencrypt-issuer.yaml` pour ajouter votre email
   2. Modifiez `apps-ingress-prod.yaml` pour utiliser vos domaines
   3. Appliquez la configuration :
      ```bash
      # D'abord testez avec l'environnement staging
      kubectl apply -f letsencrypt-issuer.yaml
      kubectl apply -f apps-ingress-prod.yaml
      
      # Une fois que tout fonctionne, passez en production :
      # 1. Modifiez apps-ingress-prod.yaml pour utiliser "letsencrypt-prod"
      # 2. Réappliquez la configuration
      kubectl apply -f apps-ingress-prod.yaml
      ```

   ⚠️ Let's Encrypt a des limites de taux : utilisez d'abord l'environnement staging pour tester.

### 3. PostgreSQL

```bash
kubectl apply -f postgresql-deployment.yaml
```

### 4. Redis

```bash
kubectl apply -f redis-deployment.yaml
```

### 5. N8N

```bash
kubectl apply -f n8n-deployment.yaml
```

### 6. Baserow

```bash
kubectl apply -f baserow-deployment.yaml
```

## Déploiement des applications

1. Créer le namespace pour les applications :
```bash
kubectl create namespace productivity
```

2. Déployer les applications :
```bash
kubectl apply -f baserow-deployment.yaml -n productivity
kubectl apply -f n8n-deployment.yaml -n productivity
```

3. Configurer les ingress :
```bash
# Générer les configurations d'ingress
./generate-ingress-configs.sh

# Appliquer les configurations
kubectl apply -f ingress-nginx-config.yaml
kubectl apply -f apps-ingress-prod.yaml
```

### Configuration de cert-manager

1. Installer cert-manager :
```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.13.0 \
  --set installCRDs=true
```

2. Créer le ClusterIssuer pour Let's Encrypt :
```bash
kubectl apply -f letsencrypt-issuer.yaml
```

### Vérification du déploiement

1. Vérifier l'état des pods :
```bash
kubectl get pods -n productivity
```

2. Vérifier les certificats :
```bash
kubectl get certificates -n productivity
```

3. Tester l'accès aux applications :
```bash
curl -k https://baserow.example.com
curl -k https://n8n.example.com
```

### Maintenance

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