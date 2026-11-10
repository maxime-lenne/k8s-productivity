# Déploiement Scaleway

Ce document détaille les étapes pour déployer l'environnement Kubernetes sur Scaleway, en utilisant **Kustomize** pour la gestion des configurations par environnement et **Sealed Secrets** pour les secrets.

> Voir aussi : [Déploiement Local](./local-deployment.md) | [Certificats & Secrets](./certificats-secrets.md) | [FAQ & Support](./faq-support.md)

## Table des matières

- [Prérequis](#prérequis)
- [Configuration de kubectl pour Scaleway](#configuration-de-kubectl-pour-scaleway)
- [Création de l'environnement sur Scaleway](#création-de-lenvironnement-sur-scaleway)
- [Configuration du DNS](#configuration-du-dns)
- [Installation des composants](#installation-des-composants)
- [Déploiement des applications](#déploiement-des-applications)
- [Maintenance](#maintenance)
- [Gestion multi-environnement](#gestion-multi-environnement)

---

## Prérequis

- Cluster Kubernetes opérationnel sur Scaleway
- `kubectl` configuré pour votre cluster Scaleway
- `helm` installé (pour l'installation initiale d'Ingress-Nginx et Cert-Manager)
- `kubeseal` installé localement
- Contrôleur Sealed Secrets installé dans votre cluster Scaleway (généralement dans le namespace `kube-system`)
- Pour Let's Encrypt : des noms de domaine pointant vers l'IP publique de votre LoadBalancer Ingress-Nginx

---

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

# Pour rendre la configuration permanente
echo 'export KUBECONFIG=./kubeconfig.yaml' >> ~/.bashrc
```

### 4. Installation de k9s (optionnel)

k9s est un outil TUI pour gérer les clusters Kubernetes :

```bash
# Installation
brew install k9s  # macOS

# Lancer k9s
k9s
```

**Raccourcis utiles dans k9s** :
- `:context` : Changer de contexte
- `:namespace` : Changer de namespace
- `:pods` : Voir les pods
- `:services` : Voir les services
- `:ingress` : Voir les ingress
- `?` : Afficher l'aide
- `:q` : Quitter

### 5. Vérification

```bash
# Vérifier que vous êtes connecté au bon cluster
kubectl config current-context

# Vérifier l'accès au cluster
kubectl get nodes
```

### 6. Gestion des contextes

```bash
# Lister tous les contextes
kubectl config get-contexts

# Changer de contexte
kubectl config use-context <nom-du-contexte>

# Ajouter un nouveau contexte
kubectl config set-context <nom-du-contexte> --cluster=<nom-du-cluster> --user=<nom-utilisateur>
```

### 7. Dépannage

Si vous rencontrez des problèmes d'authentification :

```bash
# Vérifier les credentials
scw k8s kubeconfig get <nom-du-cluster> --debug

# Régénérer le kubeconfig
scw k8s kubeconfig reset <nom-du-cluster>

# Vérifier les permissions
scw k8s cluster get <nom-du-cluster>
```

---

## Création de l'environnement sur Scaleway

### Création du cluster

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

### Récupération du kubeconfig

```bash
scw k8s kubeconfig get productivity-cluster > kubeconfig.yaml
export KUBECONFIG=./kubeconfig.yaml
```

---

## Configuration du DNS

### Création d'une zone DNS

```bash
scw dns zone create domain=example.com
```

### Ajout des enregistrements DNS

Après l'installation d'Ingress-Nginx, récupérez l'IP publique du LoadBalancer :

```bash
# Récupérer l'IP du LoadBalancer
export INGRESS_IP=$(kubectl get service ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "IP du LoadBalancer : $INGRESS_IP"
```

Puis configurez les enregistrements DNS :

```bash
# Pour le domaine racine
scw dns record create \
  zone-id=<votre-zone-id> \
  name=@ \
  type=A \
  data=$INGRESS_IP

# Pour les sous-domaines
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

# Répéter pour les autres services...
```

**Exemple de configuration DNS** :
- `n8n.staging.mondomaine.com` → [EXTERNAL-IP]
- `baserow.staging.mondomaine.com` → [EXTERNAL-IP]
- `excalidraw.staging.mondomaine.com` → [EXTERNAL-IP]
- `metabase.staging.mondomaine.com` → [EXTERNAL-IP]
- `supabase.staging.mondomaine.com` → [EXTERNAL-IP]

Attendez la propagation DNS (quelques minutes à quelques heures selon le provider).

---

## Installation des composants

### 1. Ingress-Nginx Controller

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace
```

Vérifiez l'installation :

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
# Regardez la colonne EXTERNAL-IP
```

### 2. Cert-Manager (pour HTTPS)

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

# Attendre que cert-manager soit prêt
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=90s
```

### 3. Sealed Secrets Controller

```bash
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets-controller sealed-secrets/sealed-secrets \
  --namespace kube-system
```

---

## Déploiement des applications

Le déploiement est géré par Kustomize avec des overlays par environnement.

### 1. Préparation des secrets

```bash
# Copier le fichier sample
cp environments/secrets-sample.yaml environments/<environnement>/secrets-clear.yaml

# Éditer avec vos valeurs
nano environments/<environnement>/secrets-clear.yaml
```

### 2. Scellement des secrets

```bash
# Sceller le secret
kubeseal -f environments/<environnement>/secrets-clear.yaml \
  --namespace <environnement> \
  -o yaml > environments/<environnement>/secrets-<environnement>.yaml

# IMPORTANT : Supprimer le fichier en clair
rm environments/<environnement>/secrets-clear.yaml
```

### 3. Déploiement

```bash
# Créer le namespace si nécessaire
kubectl create namespace <environnement>

# Appliquer la configuration Kustomize
kubectl apply -k environments/<environnement>/
```

### 4. Vérification

```bash
kubectl get all -n <environnement>
kubectl get sealedsecrets -n <environnement>
kubectl get secrets -n <environnement>
kubectl get ingress -n <environnement>
kubectl get certificate -n <environnement>
```

---

## Maintenance

### Mise à jour des images

```bash
# Mettre à jour les images
kubectl set image deployment/baserow baserow=baserow/baserow:latest -n productivity
kubectl set image deployment/n8n n8n=n8nio/n8n:latest -n productivity

# Vérifier le déploiement
kubectl rollout status deployment/baserow -n productivity
kubectl rollout status deployment/n8n -n productivity
```

### Redémarrage des applications

```bash
kubectl rollout restart deployment/baserow -n productivity
kubectl rollout restart deployment/n8n -n productivity
```

### Consultation des logs

```bash
kubectl logs -f deployment/<nom-du-service> -n <namespace>
```

### Pods en double (plusieurs ReplicaSets, pods Pending/Unknown)

Si vous avez plusieurs pods par déploiement après des `apply` successifs :

```bash
./scripts/staging/clean-duplicate-pods.sh staging
```

Cela met tous les déploiements à 0 replica puis à 1 (courte indisponibilité). Détails et dépannage (Pending, Init:CreateContainerConfigError) : [FAQ & Support](./faq-support.md#jai-des-pods-en-double-sur-staging-ou-un-autre-environnement).

### Suppression de l'environnement

```bash
kubectl delete -k environments/<environnement>/
```

### Recréer uniquement le staging (sans toucher à la prod)

Pour supprimer puis recréer **uniquement** l'environnement staging (aucune action sur prod) :

```bash
export KUBECONFIG=./environments/staging/kubeconfig-k8s-productivity.yaml
./scripts/staging/recreate-staging.sh
```

Le script supprime les ressources staging, recrée le namespace si besoin, puis réapplique `kubectl apply -k environments/staging/ --validate=false`. Les données du namespace staging (PVC, etc.) sont perdues.

### StorageClass et politique de rétention des volumes

Tous les PVC du projet (`postgresql-data`, `baserow-data`, `n8n-data`, `metabase-data`, `supabase-storage-data`, `redis-data`, `postgres-backup-data`) utilisent `storageClassName: sbs-default` en staging/prod, qui correspond à du **Scaleway Block Storage** (provisioner `csi.scaleway.com`).

Vérifié sur le cluster staging (`kubectl get storageclass`) :

```
NAME                    PROVISIONER        RECLAIMPOLICY   VOLUMEBINDINGMODE
sbs-default (default)   csi.scaleway.com   Delete          WaitForFirstConsumer
sbs-default-retain      csi.scaleway.com   Retain          WaitForFirstConsumer
```

`sbs-default` a `reclaimPolicy: Delete` : supprimer un PVC (ou tout le namespace via `kubectl delete -k` / `recreate-staging.sh`) supprime aussi le disque Scaleway sous-jacent, sans possibilité de récupération. Scaleway fournit déjà une StorageClass `sbs-default-retain` (même driver, `reclaimPolicy: Retain`) qui conserve le disque même après suppression du PVC — le disque reste facturé et doit être nettoyé manuellement, mais les données ne sont pas perdues immédiatement. À envisager pour `postgresql-data` en prod si on veut un filet de sécurité supplémentaire contre une suppression accidentelle, en plus des backups applicatifs (voir [Certificats & Secrets](./certificats-secrets.md#backup-et-restore-postgresql)).

---

## Gestion multi-environnement

Ce projet utilise **Kustomize** pour gérer les variations de configuration entre différents environnements.

### Structure

```
environments/
├── staging/
│   ├── kustomization.yaml
│   └── secrets-staging.yaml  # Sealed Secrets (chiffré)
├── prod/
│   ├── kustomization.yaml
│   └── secrets-prod.yaml     # Sealed Secrets (chiffré)
└── secrets-sample.yaml       # Template de secrets
```

### Fonctionnement

Le répertoire `base/` contient les manifestes Kubernetes communs. Les répertoires sous `environments/` définissent les **overlays** spécifiques :

- Patches pour modifier les ressources de base (répliques, hostnames, certificats)
- ConfigMaps avec variables spécifiques à l'environnement
- Sealed Secrets pour les données sensibles

### Déploiement d'un environnement

```bash
kubectl apply -k environments/<environnement>/
```

Les secrets sensibles sont gérés avec **Sealed Secrets**. Le contrôleur dans le cluster déchiffre les `SealedSecret` pour créer les Secrets Kubernetes standards.

---

## Procédure complète pour un cluster neuf

1. **Se connecter au cluster Scaleway**
   ```bash
   export KUBECONFIG=./environments/<environnement>/kubeconfig.yaml
   ```

2. **Créer le namespace**
   ```bash
   kubectl create namespace <environnement>
   ```

3. **Installer les composants essentiels**
   - Ingress-Nginx Controller
   - Cert-Manager
   - Sealed Secrets Controller

4. **Générer et sceller les secrets**
   ```bash
   cp environments/secrets-sample.yaml environments/<environnement>/secrets-clear.yaml
   # Éditer le fichier...
   kubeseal -f environments/<environnement>/secrets-clear.yaml \
     --namespace <environnement> \
     -o yaml > environments/<environnement>/secrets-<environnement>.yaml
   rm environments/<environnement>/secrets-clear.yaml
   ```

5. **Appliquer la configuration**
   ```bash
   kubectl apply -k environments/<environnement>/
   ```

6. **Configurer le DNS**
   - Récupérer l'IP du LoadBalancer
   - Créer les enregistrements DNS

7. **Vérifier le déploiement**
   ```bash
   kubectl get all -n <environnement>
   kubectl get ingress -n <environnement>
   kubectl get certificate -n <environnement>
   ```
