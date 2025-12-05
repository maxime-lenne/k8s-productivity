# Déploiement Local (Mac avec Docker Desktop)

Ce document détaille les étapes pour déployer l'environnement Kubernetes en local sur Mac avec Docker Desktop, en utilisant **Kustomize** pour la gestion des configurations.

> Voir aussi : [Déploiement & Scaleway](./deploiement-scaleway.md) | [Ingress, certificats & secrets](./ingress-certificats-secrets.md) | [FAQ, Dépannage & Maintenance](./faq-depannage-maintenance.md)

## Table des matières
- [Prérequis](#prérequis)
- [Installation des outils](#installation-des-outils)
- [Configuration du cluster Kubernetes](#configuration-du-cluster-kubernetes)
- [Configuration de kubectl](#configuration-de-kubectl)
- [Installation des composants](#installation-des-composants)
- [Configuration des secrets](#configuration-des-secrets)
- [Déploiement des applications](#déploiement-des-applications)
- [Configuration DNS locale](#configuration-dns-locale)
- [Accès aux services](#accès-aux-services)
- [Vérification du déploiement](#vérification-du-déploiement)
- [Dépannage](#dépannage)

## Prérequis

### Logiciels requis

1. **Docker Desktop pour Mac**
   - Version récente (recommandée : dernière version stable)
   - Kubernetes activé dans les paramètres Docker Desktop
   - Au moins 4 Go de RAM alloués à Docker
   - Au moins 20 Go d'espace disque disponible

2. **Homebrew** (gestionnaire de paquets pour Mac)
   ```bash
   # Vérifier l'installation
   brew --version
   
   # Si non installé, installer depuis https://brew.sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

3. **kubectl** (client Kubernetes)
   ```bash
   # Installation via Homebrew
   brew install kubectl
   
   # Vérifier l'installation
   kubectl version --client
   ```

4. **kustomize** (inclus avec kubectl depuis la v1.14+)
   ```bash
   # Vérifier que kustomize est disponible
   kubectl kustomize --help
   ```

### Vérification de l'environnement

```bash
# Vérifier que Docker est en cours d'exécution
docker ps

# Vérifier que Kubernetes est activé dans Docker Desktop
# (Menu Docker Desktop > Settings > Kubernetes > Enable Kubernetes)
```

## Installation des outils

### 1. Vérifier Docker Desktop

1. Ouvrir Docker Desktop
2. Aller dans **Settings** (⚙️) > **Kubernetes**
3. Cocher **Enable Kubernetes**
4. Cliquer sur **Apply & Restart**
5. Attendre que le cluster démarre (indicateur vert dans la barre de menu)

### 2. Vérifier l'installation de kubectl

```bash
# Vérifier la version
kubectl version --client

# Si kubectl n'est pas installé
brew install kubectl
```

## Configuration du cluster Kubernetes

Docker Desktop crée automatiquement un cluster Kubernetes de type "kind" (Kubernetes in Docker). Le cluster est nommé "desktop" et contient :
- 1 nœud control-plane
- 2 nœuds worker (par défaut)

### Vérification du cluster

```bash
# Vérifier que les conteneurs du cluster sont en cours d'exécution
docker ps | grep -E "control-plane|worker"

# Vous devriez voir :
# - desktop-control-plane
# - desktop-worker
# - desktop-worker2
```

## Configuration de kubectl

### 1. Récupérer le kubeconfig

Le kubeconfig est stocké dans le conteneur control-plane. Il faut l'extraire et le configurer pour utiliser le port mappé sur localhost.

```bash
# Récupérer le port mappé du control-plane
export K8S_PORT=$(docker port desktop-control-plane 6443 | cut -d: -f2)

# Extraire le kubeconfig et le configurer
docker exec desktop-control-plane cat /etc/kubernetes/admin.conf | \
  sed "s|server: https://desktop-control-plane:6443|server: https://127.0.0.1:${K8S_PORT}|" > /tmp/kubeconfig-local.yaml

# Configurer kubectl pour utiliser ce kubeconfig
export KUBECONFIG=/tmp/kubeconfig-local.yaml
kubectl config view --minify --raw > ~/.kube/config

# Vérifier la connexion
kubectl get nodes
```

### 2. Script de configuration automatique

Pour éviter de répéter cette configuration à chaque redémarrage, vous pouvez créer un script :

```bash
# Créer le script
cat > ~/bin/k8s-local-config.sh << 'EOF'
#!/bin/bash
export K8S_PORT=$(docker port desktop-control-plane 6443 2>/dev/null | cut -d: -f2)
if [ -z "$K8S_PORT" ]; then
  echo "Erreur: Le cluster Kubernetes n'est pas démarré"
  exit 1
fi
docker exec desktop-control-plane cat /etc/kubernetes/admin.conf | \
  sed "s|server: https://desktop-control-plane:6443|server: https://127.0.0.1:${K8S_PORT}|" > /tmp/kubeconfig-local.yaml
export KUBECONFIG=/tmp/kubeconfig-local.yaml
kubectl config view --minify --raw > ~/.kube/config
echo "✓ kubectl configuré pour le cluster local (port: $K8S_PORT)"
kubectl get nodes
EOF

chmod +x ~/bin/k8s-local-config.sh

# Ajouter au PATH si nécessaire
mkdir -p ~/bin
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc  # ou ~/.bash_profile selon votre shell
```

## Installation des composants

### 1. Ingress-Nginx Controller

L'Ingress Controller est nécessaire pour exposer les services via des URLs.

```bash
# Installer Ingress-Nginx
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Attendre que le controller soit prêt
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

# Vérifier l'installation
kubectl get pods -n ingress-nginx
```

### 2. StorageClass pour les volumes persistants

Le cluster kind utilise `rancher.io/local-path` comme provisioner de volumes. Créer un StorageClass personnalisé :

```bash
kubectl create -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: sbs-default
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
EOF

# Vérifier
kubectl get storageclass
```

### 3. Cert-Manager (optionnel pour le local)

Pour l'environnement local, les certificats auto-signés peuvent être utilisés. Cert-Manager n'est pas strictement nécessaire, mais peut être installé pour la cohérence :

```bash
# Installer cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

# Attendre que cert-manager soit prêt
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=90s
```

## Configuration des secrets

Pour l'environnement local, les secrets peuvent être créés directement sans Sealed Secrets (pour simplifier).

### 1. Créer les secrets PostgreSQL

```bash
kubectl create secret generic postgresql-secret \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=postgres123 \
  --from-literal=N8N_DB_NAME=n8n_db \
  --from-literal=N8N_DB_USER=n8n_user \
  --from-literal=N8N_DB_PASSWORD=n8n_pass123 \
  --from-literal=BASEROW_DB_NAME=baserow_db \
  --from-literal=BASEROW_DB_USER=baserow_user \
  --from-literal=BASEROW_DB_PASSWORD=baserow_pass123 \
  --from-literal=METABASE_DB_NAME=metabase_db \
  --from-literal=METABASE_DB_USER=metabase_user \
  --from-literal=METABASE_DB_PASSWORD=metabase_pass123 \
  --from-literal=SUPABASE_DB_NAME=supabase_db \
  --from-literal=SUPABASE_DB_USER=supabase_user \
  --from-literal=SUPABASE_DB_PASSWORD=supabase_pass123 \
  --from-literal=SUPABASE_DB_URI=postgresql://supabase_user:supabase_pass123@postgresql:5432/supabase_db
```

### 2. Créer le secret Redis

```bash
kubectl create secret generic redis-secret \
  --from-literal=REDIS_PASSWORD=redis123
```

### 3. Créer le secret Baserow

```bash
kubectl create secret generic baserow-secret \
  --from-literal=SECRET_KEY=baserow-secret-key-local-123 \
  --from-literal=JWT_SECRET=baserow-jwt-secret-local-123
```

### 4. Créer le secret Supabase

```bash
kubectl create secret generic supabase-secret \
  --from-literal=JWT_SECRET=supabase-jwt-secret-local-123 \
  --from-literal=ANON_KEY=supabase-anon-key-local-123 \
  --from-literal=SERVICE_ROLE_KEY=supabase-service-role-key-local-123
```

## Déploiement des applications

### 1. Appliquer la configuration Kustomize

```bash
# Se placer dans le répertoire du projet
cd /Users/maxime-lenne/Documents_Non_iCloud/workspace_devops/k8s-productivity

# Appliquer la configuration pour l'environnement local
kubectl apply -k environments/local/
```

### 2. Vérifier le déploiement

```bash
# Vérifier les pods
kubectl get pods

# Vérifier les services
kubectl get services

# Vérifier les ingress
kubectl get ingress

# Vérifier les PVCs
kubectl get pvc
```

## Configuration DNS locale et SSL

### Solution automatique (recommandée)

Un script d'automatisation complet est disponible pour configurer l'accès local avec SSL :

```bash
# Depuis la racine du projet
./scripts/local/setup-local-access.sh
```

Ce script automatise :
- ✅ Configuration de `/etc/hosts`
- ✅ Installation et vérification de l'Ingress Controller
- ✅ Installation et configuration de cert-manager
- ✅ Génération automatique des certificats SSL auto-signés
- ✅ Démarrage du port-forward en arrière-plan
- ✅ Test de connectivité

**Note** : Le script nécessite votre mot de passe pour modifier `/etc/hosts`.

### Configuration manuelle

#### Option 1 : Modification manuelle de /etc/hosts

```bash
# Ajouter les entrées suivantes dans /etc/hosts
sudo bash -c 'cat >> /etc/hosts' << 'HOSTS'
# Kubernetes local services
127.0.0.1	baserow.local
127.0.0.1	n8n.local
127.0.0.1	excalidraw.local
127.0.0.1	metabase.local
127.0.0.1	supabase.local
HOSTS
```

#### Option 2 : Utiliser port-forward (alternative)

Si vous ne voulez pas modifier `/etc/hosts`, vous pouvez utiliser port-forward :

```bash
# Dans un terminal séparé
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443
```

### Configuration SSL (HTTPS)

Les certificats SSL auto-signés sont générés automatiquement par cert-manager. Pour les activer :

1. **Vérifier que cert-manager est installé** :
   ```bash
   kubectl get pods -n cert-manager
   ```

2. **Vérifier que le ClusterIssuer existe** :
   ```bash
   kubectl get clusterissuer selfsigned-issuer
   ```

3. **Vérifier que les certificats sont générés** :
   ```bash
   kubectl get certificate
   kubectl get secret apps-tls-local-cert
   ```

Les certificats sont automatiquement générés lors du déploiement grâce à l'annotation `cert-manager.io/cluster-issuer: selfsigned-issuer` dans l'Ingress.

**Note** : Les certificats sont auto-signés, votre navigateur affichera un avertissement de sécurité. C'est normal en local. Cliquez sur "Avancé" puis "Continuer vers le site" pour accepter le certificat.

## Accès aux services

Une fois la configuration DNS et SSL effectuées, vous pouvez accéder aux services via HTTPS :

- **Excalidraw** : https://excalidraw.local
- **Baserow** : https://baserow.local
- **N8N** : https://n8n.local
- **Metabase** : https://metabase.local
- **Supabase Studio** : https://supabase.local

**Note** : Les certificats SSL sont auto-signés. Votre navigateur affichera un avertissement de sécurité. C'est normal en local. Acceptez le certificat pour continuer.

### Démarrer le port-forward

Le port-forward doit être actif pour accéder aux services. Si vous avez utilisé le script automatique, il est déjà démarré. Sinon :

```bash
# Démarrer le port-forward en arrière-plan
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443 > /tmp/k8s-port-forward.log 2>&1 &

# Vérifier qu'il tourne
ps aux | grep "kubectl port-forward"
```

Pour arrêter le port-forward :
```bash
pkill -f "kubectl port-forward.*ingress-nginx-controller"
```

### Vérifier que l'Ingress Controller est accessible

```bash
# Tester avec curl
curl -H "Host: excalidraw.local" http://localhost

# Ou si vous utilisez port-forward sur le port 80
curl http://excalidraw.local
```

## Vérification du déploiement

### 1. Vérifier l'état des pods

```bash
# Voir tous les pods
kubectl get pods

# Voir les pods avec plus de détails
kubectl get pods -o wide

# Voir les logs d'un pod spécifique
kubectl logs <nom-du-pod>
```

### 2. Vérifier les services

```bash
# Lister tous les services
kubectl get services

# Vérifier un service spécifique
kubectl describe service <nom-du-service>
```

### 3. Vérifier les ingress

```bash
# Lister les ingress
kubectl get ingress

# Vérifier les détails d'un ingress
kubectl describe ingress apps-ingress-local
```

### 4. Vérifier les volumes persistants

```bash
# Lister les PVCs
kubectl get pvc

# Vérifier les détails d'un PVC
kubectl describe pvc <nom-du-pvc>
```

## Dépannage

### Problème : Le cluster n'est pas accessible

```bash
# Vérifier que Docker Desktop est en cours d'exécution
docker ps

# Vérifier que les conteneurs du cluster sont actifs
docker ps | grep -E "control-plane|worker"

# Reconfigurer kubectl
export K8S_PORT=$(docker port desktop-control-plane 6443 | cut -d: -f2)
docker exec desktop-control-plane cat /etc/kubernetes/admin.conf | \
  sed "s|server: https://desktop-control-plane:6443|server: https://127.0.0.1:${K8S_PORT}|" > /tmp/kubeconfig-local.yaml
export KUBECONFIG=/tmp/kubeconfig-local.yaml
kubectl config view --minify --raw > ~/.kube/config
```

### Problème : Les pods restent en "Pending"

```bash
# Vérifier les events
kubectl get events --sort-by='.lastTimestamp'

# Vérifier les détails d'un pod
kubectl describe pod <nom-du-pod>

# Vérifier les PVCs
kubectl get pvc
kubectl describe pvc <nom-du-pvc>
```

### Problème : Erreur DNS_PROBE_FINISHED_NXDOMAIN

Cela signifie que les domaines `.local` ne sont pas résolus. Vérifiez que `/etc/hosts` contient les bonnes entrées :

```bash
# Vérifier les entrées dans /etc/hosts
grep -E "(baserow|n8n|excalidraw|metabase|supabase)\.local" /etc/hosts

# Si les entrées manquent, les ajouter (voir section Configuration DNS locale)
```

### Problème : Les images ne se téléchargent pas

```bash
# Vérifier les erreurs d'images
kubectl describe pod <nom-du-pod> | grep -A 5 "Events:"

# Forcer le redémarrage d'un pod
kubectl delete pod <nom-du-pod>

# Vérifier la connectivité réseau
kubectl run -it --rm debug --image=busybox --restart=Never -- ping -c 3 8.8.8.8
```

### Problème : Les services ne sont pas accessibles via l'Ingress

```bash
# Vérifier que l'Ingress Controller est en cours d'exécution
kubectl get pods -n ingress-nginx

# Vérifier les logs de l'Ingress Controller
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller

# Vérifier la configuration de l'Ingress
kubectl describe ingress apps-ingress-local
```

### Problème : Les bases de données ne démarrent pas

```bash
# Vérifier les logs PostgreSQL
kubectl logs -l app=postgresql

# Vérifier que les secrets sont correctement montés
kubectl describe pod -l app=postgresql | grep -A 10 "Environment:"

# Vérifier les PVCs
kubectl get pvc | grep postgresql
```

## Commandes utiles

### Redémarrer un service

```bash
kubectl rollout restart deployment <nom-du-deployment>
```

### Voir les logs d'un service

```bash
kubectl logs -f deployment/<nom-du-deployment>
```

### Accéder à un pod en shell

```bash
kubectl exec -it <nom-du-pod> -- /bin/sh
```

### Supprimer complètement l'environnement

```bash
# Supprimer toutes les ressources
kubectl delete -k environments/local/

# Supprimer les secrets
kubectl delete secret postgresql-secret redis-secret baserow-secret supabase-secret

# Supprimer le StorageClass
kubectl delete storageclass sbs-default

# Supprimer l'Ingress Controller
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
```

## Notes importantes

1. **Redémarrage du cluster** : Si Docker Desktop redémarre, le cluster Kubernetes est recréé et toutes les données sont perdues (sauf si vous utilisez des volumes persistants montés depuis l'hôte).

2. **Ports** : Le port du control-plane change à chaque redémarrage. Il faut reconfigurer kubectl après chaque redémarrage.

3. **Secrets** : Les secrets créés manuellement sont perdus lors d'un redémarrage. Il faut les recréer ou utiliser un script d'initialisation.

4. **Performance** : Les performances peuvent être limitées sur Mac, surtout avec plusieurs services. Ajustez les ressources allouées à Docker Desktop si nécessaire.

5. **Réseau** : Les services sont accessibles uniquement depuis la machine locale par défaut. Pour exposer vers l'extérieur, utilisez `kubectl port-forward` ou configurez un LoadBalancer.

