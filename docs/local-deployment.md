# Déploiement Local (Mac avec Docker Desktop)

Ce document détaille les étapes pour déployer l'environnement Kubernetes en local sur Mac avec Docker Desktop, en utilisant **Kustomize** pour la gestion des configurations.

> Voir aussi : [Déploiement Scaleway](./scaleway-deployment.md) | [Certificats & Secrets](./certificats-secrets.md) | [FAQ & Support](./faq-support.md)

## Table des matières

- [Prérequis](#prérequis)
- [Installation des outils](#installation-des-outils)
- [Configuration du cluster Kubernetes](#configuration-du-cluster-kubernetes)
- [Configuration de kubectl](#configuration-de-kubectl)
- [Installation des composants](#installation-des-composants)
- [Configuration des secrets](#configuration-des-secrets)
- [Déploiement des applications](#déploiement-des-applications)
- [Accès local aux services](#accès-local-aux-services)
- [Accès réseau local (depuis d'autres machines)](#accès-réseau-local-depuis-dautres-machines)
- [Vérification du déploiement](#vérification-du-déploiement)
- [Dépannage](#dépannage)

---

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

---

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

---

## Configuration du cluster Kubernetes

Docker Desktop crée automatiquement un cluster Kubernetes. Le cluster contient :
- 1 nœud control-plane
- 2 nœuds worker (par défaut)

### Vérification du cluster

```bash
# Vérifier que les conteneurs du cluster sont en cours d'exécution
docker ps | grep -E "control-plane|worker"

# Vérifier les nœuds
kubectl get nodes
```

---

## Configuration de kubectl

### 1. Récupérer le kubeconfig

Le kubeconfig est stocké dans le conteneur control-plane. Il faut l'extraire et le configurer :

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

Pour éviter de répéter cette configuration à chaque redémarrage :

```bash
# Créer le script
mkdir -p ~/bin
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
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
```

---

## Installation des composants

### 1. Ingress-Nginx Controller

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

```bash
# Installer cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml

# Attendre que cert-manager soit prêt
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=90s
```

---

## Configuration des secrets

Pour l'environnement local, les secrets peuvent être créés directement :

### 1. Secret PostgreSQL

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

### 2. Secret Redis

```bash
kubectl create secret generic redis-secret \
  --from-literal=REDIS_PASSWORD=redis123
```

### 3. Secret Baserow

```bash
kubectl create secret generic baserow-secret \
  --from-literal=SECRET_KEY=baserow-secret-key-local-123 \
  --from-literal=JWT_SECRET=baserow-jwt-secret-local-123
```

### 4. Secret Supabase

```bash
kubectl create secret generic supabase-secret \
  --from-literal=JWT_SECRET=supabase-jwt-secret-local-123 \
  --from-literal=ANON_KEY=supabase-anon-key-local-123 \
  --from-literal=SERVICE_ROLE_KEY=supabase-service-role-key-local-123
```

---

## Déploiement des applications

### 1. Appliquer la configuration Kustomize

```bash
# Se placer dans le répertoire du projet
cd /path/to/k8s-productivity

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

---

## Accès local aux services

### Solution automatique (recommandée)

Un script unifié est disponible pour configurer l'accès local avec SSL :

```bash
# Depuis la racine du projet
./scripts/local/setup-access.sh
```

Ce script automatise :
- Configuration de `/etc/hosts`
- Installation et vérification de l'Ingress Controller
- Installation et configuration de cert-manager
- Génération automatique des certificats SSL auto-signés
- Démarrage du port-forward en arrière-plan
- Détection automatique des ports disponibles
- Test de connectivité

**Note** : Le script nécessite votre mot de passe pour modifier `/etc/hosts`.

#### Options du script

Le script supporte plusieurs options pour personnaliser les ports :

```bash
# Aide
./scripts/local/setup-access.sh --help

# Mode local avec ports par défaut (8080/8443 sans sudo, 80/443 avec sudo)
./scripts/local/setup-access.sh

# Mode local avec ports personnalisés
./scripts/local/setup-access.sh --http-port 8080 --https-port 8443

# Mode réseau avec ports par défaut (nécessite sudo)
sudo ./scripts/local/setup-access.sh --network

# Mode réseau avec ports personnalisés
sudo ./scripts/local/setup-access.sh --network --http-port 8880 --https-port 9443

# Utilisation de variables d'environnement
K8S_HTTP_PORT=8080 K8S_HTTPS_PORT=8443 ./scripts/local/setup-access.sh
```

**Ports par défaut** :
- **Avec sudo** : HTTP=80, HTTPS=443
- **Sans sudo** : HTTP=8080, HTTPS=8443

Si les ports par défaut sont déjà utilisés, le script cherche automatiquement des ports alternatifs disponibles.

### Configuration manuelle

#### Option 1 : Modification manuelle de /etc/hosts

```bash
# Ajouter les entrées suivantes dans /etc/hosts
sudo bash -c 'cat >> /etc/hosts' << 'HOSTS'
# Kubernetes local services
127.0.0.1 baserow.white-wood.local
127.0.0.1 n8n.white-wood.local
127.0.0.1 excalidraw.white-wood.local
127.0.0.1 metabase.white-wood.local
127.0.0.1 supabase.white-wood.local
HOSTS
```

#### Option 2 : Utiliser port-forward (alternative)

```bash
# Dans un terminal séparé
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443
```

### URLs des services

Une fois configuré, accédez aux services via HTTPS :

- **Baserow** : https://baserow.white-wood.local (ou avec le port si différent de 443)
- **N8N** : https://n8n.white-wood.local
- **Excalidraw** : https://excalidraw.white-wood.local
- **Metabase** : https://metabase.white-wood.local
- **Supabase Studio** : https://supabase.white-wood.local

**Note** : 
- Les certificats SSL sont auto-signés. Votre navigateur affichera un avertissement de sécurité. Acceptez le certificat pour continuer.
- Si vous utilisez des ports personnalisés (différents de 443), ajoutez le port dans l'URL : `https://baserow.white-wood.local:8443`
- Le script affiche les URLs complètes avec les ports utilisés à la fin de l'exécution.

---

## Accès réseau local (depuis d'autres machines)

Cette section explique comment configurer l'accès aux services depuis d'autres appareils sur votre réseau local (iPhone, iPad, autre Mac, etc.).

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Appareil sur le réseau local (iPhone, iPad, autre Mac...)  │
│                                                             │
│  1. Requête DNS : baserow.white-wood.local                  │
│     ↓                                                       │
│  2. Serveur DNS : Mac Mini (192.168.x.x)                    │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Mac Mini (192.168.x.x)                                     │
│                                                             │
│  ┌──────────────┐        ┌─────────────────────────┐       │
│  │   dnsmasq    │  →  →  │  kubectl port-forward   │       │
│  │   (port 53)  │        │  (ports 80/443)         │       │
│  └──────────────┘        └───────────┬─────────────┘       │
│                                      │                      │
│                                      ↓                      │
│                          ┌─────────────────────────┐       │
│                          │  Ingress Controller     │       │
│                          │  (Kubernetes)           │       │
│                          └───────────┬─────────────┘       │
│                                      │                      │
│                          ┌───────────┴─────────────┐       │
│                          │  Services (Pods)        │       │
│                          │  • Baserow • N8N        │       │
│                          │  • Excalidraw • Metabase│       │
│                          │  • Supabase             │       │
│                          └─────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Configuration du serveur (Mac Mini)

#### 1. Installation de dnsmasq

```bash
# Rendre les scripts exécutables
chmod +x scripts/local/*.sh

# Installer et configurer dnsmasq
./scripts/local/install-dnsmasq.sh
```

Ce script va :
- Installer dnsmasq via Homebrew
- Détecter l'IP locale du Mac Mini
- Configurer dnsmasq pour résoudre `*.white-wood.local` vers l'IP du Mac Mini
- Configurer macOS pour utiliser dnsmasq comme resolver DNS
- Démarrer le service dnsmasq

#### 2. Démarrage de l'accès réseau

```bash
# Démarrer le port-forward réseau (nécessite sudo)
sudo ./scripts/local/setup-access.sh --network
```

Ce script va :
- Vérifier que dnsmasq est actif
- Vérifier que le cluster Kubernetes est accessible
- Configurer cert-manager et l'Ingress Controller
- Démarrer le port-forward sur `0.0.0.0:80` et `0.0.0.0:443`

#### 3. Arrêt du service

```bash
# Arrêter le port-forward
./scripts/local/stop-access.sh

# Arrêter dnsmasq (optionnel)
sudo brew services stop dnsmasq
```

### Configuration des appareils clients

#### iOS / iPadOS

1. Ouvrir **Réglages** → **Wi-Fi**
2. Appuyer sur **(i)** à côté du réseau Wi-Fi actuel
3. Descendre jusqu'à **Configurer DNS**
4. Sélectionner **Manuel**
5. Ajouter le serveur DNS : `192.168.x.x` (IP du Mac Mini)
6. Enregistrer

#### macOS

1. Ouvrir **Préférences Système** → **Réseau**
2. Sélectionner la connexion active (Wi-Fi ou Ethernet)
3. Cliquer sur **Avancé**
4. Onglet **DNS**
5. Cliquer sur **+** pour ajouter : `192.168.x.x`
6. Cliquer sur **OK** puis **Appliquer**

#### Windows

1. Ouvrir le **Panneau de configuration** → **Centre Réseau et partage**
2. Cliquer sur votre connexion active
3. Cliquer sur **Propriétés**
4. Sélectionner **Protocole Internet version 4 (TCP/IPv4)**
5. Cliquer sur **Propriétés**
6. Sélectionner **Utiliser l'adresse de serveur DNS suivante**
7. Serveur DNS préféré : `192.168.x.x` (IP du Mac Mini)
8. Cliquer sur **OK**

#### Linux

```bash
# Via NetworkManager
nmcli connection modify "Nom de la connexion" ipv4.dns "192.168.x.x 8.8.8.8"
nmcli connection down "Nom de la connexion"
nmcli connection up "Nom de la connexion"
```

#### Android

1. Ouvrir **Paramètres** → **Wi-Fi**
2. Appui long sur le réseau Wi-Fi connecté
3. Sélectionner **Modifier le réseau**
4. Cocher **Options avancées**
5. **Paramètres IP** : Statique
6. **DNS 1** : `192.168.x.x` (IP du Mac Mini)
7. Enregistrer

### Test de connectivité

```bash
# Test DNS (depuis un client)
dig @192.168.x.x baserow.white-wood.local

# Test HTTP
curl -k https://baserow.white-wood.local
```

---

## Vérification du déploiement

### 1. Vérifier l'état des pods

```bash
kubectl get pods
kubectl get pods -o wide
kubectl logs <nom-du-pod>
```

### 2. Vérifier les services

```bash
kubectl get services
kubectl describe service <nom-du-service>
```

### 3. Vérifier les ingress

```bash
kubectl get ingress
kubectl describe ingress apps-ingress-local
```

### 4. Vérifier les volumes persistants

```bash
kubectl get pvc
kubectl describe pvc <nom-du-pvc>
```

---

## Dépannage

### Le cluster n'est pas accessible

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

### Les pods restent en "Pending"

```bash
kubectl get events --sort-by='.lastTimestamp'
kubectl describe pod <nom-du-pod>
kubectl get pvc
```

### Erreur DNS_PROBE_FINISHED_NXDOMAIN

Les domaines `.white-wood.local` ne sont pas résolus :

```bash
# Vérifier les entrées dans /etc/hosts
grep "white-wood.local" /etc/hosts

# Vider le cache DNS macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

### Les services ne sont pas accessibles depuis le réseau

```bash
# Vérifier que le port-forward est actif
ps aux | grep "kubectl port-forward"

# Vérifier les logs
tail -f /tmp/k8s-logs/port-forward.log

# Vérifier dnsmasq
brew services list | grep dnsmasq
```

### Les certificats SSL ne sont pas générés

```bash
kubectl get certificate
kubectl describe certificate apps-tls-local-cert
kubectl get pods -n cert-manager
```

---

## Commandes utiles

### Gestion du service

```bash
# Démarrer l'accès local
./scripts/local/setup-access.sh

# Démarrer l'accès réseau
sudo ./scripts/local/setup-access.sh --network

# Arrêter l'accès
./scripts/local/stop-access.sh

# Redémarrer dnsmasq
sudo brew services restart dnsmasq
```

### Gestion Kubernetes

```bash
# Redémarrer un service
kubectl rollout restart deployment <nom-du-deployment>

# Voir les logs d'un service
kubectl logs -f deployment/<nom-du-deployment>

# Accéder à un pod en shell
kubectl exec -it <nom-du-pod> -- /bin/sh

# Supprimer complètement l'environnement
kubectl delete -k environments/local/
```

---

## Notes importantes

1. **Redémarrage du cluster** : Si Docker Desktop redémarre, le cluster Kubernetes est recréé et toutes les données sont perdues (sauf volumes persistants).

2. **Ports** : Le port du control-plane change à chaque redémarrage. Il faut reconfigurer kubectl après chaque redémarrage.

3. **Secrets** : Les secrets créés manuellement sont perdus lors d'un redémarrage. Utilisez un script d'initialisation ou Sealed Secrets.

4. **Performance** : Les performances peuvent être limitées sur Mac. Ajustez les ressources allouées à Docker Desktop si nécessaire.

5. **Réseau** : Les services sont accessibles uniquement depuis la machine locale par défaut. Utilisez `--network` pour exposer sur le réseau local.
