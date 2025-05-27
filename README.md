# Guide de déploiement de l'environnement Kubernetes

Ce guide détaille les étapes pour déployer un environnement complet comprenant Ingress-Nginx, PostgreSQL, Redis, N8N et Baserow sur Kubernetes.

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

## Structure des fichiers

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

## Vérification du déploiement

1. Vérifiez que tous les pods sont en cours d'exécution :
   ```bash
   kubectl get pods
   ```
   ⚠️ Attendez que tous les pods soient en état `Running` avant de continuer.

2. Vérifiez les services :
   ```bash
   kubectl get services
   ```

3. Vérifiez les ingress et les certificats :
   ```bash
   kubectl get ingress
   kubectl get certificate
   ```

## Accès aux applications

Pour les certificats auto-signés :
- N8N : https://n8n.local
- Baserow : https://baserow.local

Pour Let's Encrypt :
- N8N : https://n8n.example.com (remplacez par votre domaine)
- Baserow : https://baserow.example.com (remplacez par votre domaine)

⚠️ Pour Let's Encrypt :
- Assurez-vous que vos domaines pointent vers votre cluster
- Commencez par l'environnement staging pour éviter les limites de taux
- Le certificat peut prendre quelques minutes pour être émis

## Maintenance

### Redémarrage d'un service

Pour redémarrer un service spécifique :
```bash
kubectl rollout restart deployment <nom-du-service>
```

### Consultation des logs

Pour voir les logs d'un service :
```bash
kubectl logs -f deployment/<nom-du-service>
```

### Suppression complète de l'environnement

Pour supprimer tous les composants :
```bash
kubectl delete deployment baserow n8n postgresql redis
kubectl delete service baserow n8n postgresql redis
kubectl delete pvc --all
kubectl delete configmap postgresql-config init-script
kubectl delete secret postgresql-secret redis-secret baserow-secret apps-tls-cert
kubectl delete certificate apps-tls-cert
kubectl delete clusterissuer selfsigned-issuer
helm uninstall ingress-nginx
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
```

## Dépannage

### Problèmes courants

1. Si les pods restent en état "Pending" :
   - Vérifiez les events : `kubectl get events`
   - Vérifiez les logs : `kubectl describe pod <nom-du-pod>`

2. Si les services ne sont pas accessibles :
   - Vérifiez l'état de l'ingress : `kubectl describe ingress`
   - Vérifiez les logs de l'ingress-controller : `kubectl logs -n ingress-nginx deployment/ingress-nginx-controller`
   - Vérifiez l'état des certificats : `kubectl describe certificate`

3. Si les bases de données ne s'initialisent pas correctement :
   - Vérifiez les logs PostgreSQL : `kubectl logs -l app=postgresql`
   - Vérifiez que les secrets sont correctement montés : `kubectl describe pod <nom-du-pod-postgresql>`

### Problèmes spécifiques à PostgreSQL sur Scaleway

1. **Problème de volume persistant** :
   ```bash
   # Vérifier l'état des PVC
   kubectl get pvc
   
   # Vérifier les events liés aux PVC
   kubectl get events | grep postgresql
   
   # Vérifier les logs du pod PostgreSQL
   kubectl logs -l app=postgresql
   ```

   Solutions possibles :
   - Vérifier que le StorageClass est correctement configuré :
     ```yaml
     apiVersion: storage.k8s.io/v1
     kind: StorageClass
     metadata:
       name: csi-csi-high-speed
     provisioner: csi.scaleway.com
     parameters:
       type: b_ssd
     ```
   - S'assurer que le PVC utilise la bonne StorageClass :
     ```yaml
     apiVersion: v1
     kind: PersistentVolumeClaim
     metadata:
       name: postgresql-data
     spec:
       storageClassName: csi-csi-high-speed
       accessModes:
         - ReadWriteOnce
       resources:
         requests:
           storage: 10Gi
     ```

2. **Problème de permissions** :
   ```bash
   # Vérifier les logs du pod PostgreSQL
   kubectl logs -l app=postgresql
   
   # Vérifier les permissions du volume
   kubectl exec -it <postgresql-pod> -- ls -la /var/lib/postgresql/data
   ```

   Solutions possibles :
   - Ajouter un initContainer pour corriger les permissions :
     ```yaml
     spec:
       initContainers:
       - name: init-chmod-data
         image: busybox
         command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
         volumeMounts:
         - name: postgresql-data
           mountPath: /var/lib/postgresql/data
       volumes:
       - name: postgresql-data
         persistentVolumeClaim:
           claimName: postgresql-data
     ```

3. **Problème de connexion** :
   ```bash
   # Vérifier les logs de connexion
   kubectl logs -l app=postgresql
   
   # Vérifier les variables d'environnement
   kubectl describe pod <postgresql-pod>
   ```

   Solutions possibles :
   - Vérifier que les variables d'environnement sont correctement définies :
     ```yaml
     env:
     - name: POSTGRES_USER
       valueFrom:
         secretKeyRef:
           name: postgresql-secret
           key: username
     - name: POSTGRES_PASSWORD
       valueFrom:
         secretKeyRef:
           name: postgresql-secret
           key: password
     - name: POSTGRES_DB
       valueFrom:
         secretKeyRef:
           name: postgresql-secret
           key: database
     ```

4. **Problème de redémarrage** :
   ```bash
   # Vérifier l'historique des redémarrages
   kubectl describe pod <postgresql-pod>
   
   # Vérifier les logs précédents
   kubectl logs -l app=postgresql --previous
   ```

   Solutions possibles :
   - Ajouter des probes de liveness et readiness :
     ```yaml
     livenessProbe:
       exec:
         command:
         - pg_isready
         - -U
         - postgres
       initialDelaySeconds: 30
       periodSeconds: 10
     readinessProbe:
       exec:
         command:
         - pg_isready
         - -U
         - postgres
       initialDelaySeconds: 5
       periodSeconds: 2
     ```

5. **Problème de performance** :
   ```bash
   # Vérifier les ressources utilisées
   kubectl top pod <postgresql-pod>
   
   # Vérifier les limites de ressources
   kubectl describe pod <postgresql-pod>
   ```

   Solutions possibles :
   - Ajuster les ressources :
     ```yaml
     resources:
       requests:
         memory: "1Gi"
         cpu: "500m"
       limits:
         memory: "2Gi"
         cpu: "1000m"
     ```

### Problèmes avec Let's Encrypt

1. Si les certificats ne sont pas émis :
   ```bash
   kubectl describe certificate
   kubectl describe challenges
   ```

2. Vérifiez que vos domaines sont accessibles :
   ```bash
   curl -v http://votre-domaine/.well-known/acme-challenge/
   ```

3. Limites de taux atteintes :
   - Utilisez l'environnement staging pour les tests
   - Attendez que les limites soient réinitialisées pour la production 

# K8s Productivity

Ce projet contient les configurations Kubernetes pour déployer des outils de productivité (Baserow, N8N) sur un cluster Kubernetes.

## Configuration des Ingress

Le projet utilise deux ingress distincts pour gérer le trafic HTTP/HTTPS :

1. **Environnement Local** (`apps-ingress-local.yaml`)
   - Domaine : baserow.local, n8n.local
   - Certificat : Auto-signé (selfsigned-issuer)
   - SSL Redirect : Désactivé

2. **Environnement Production** (`apps-ingress-prod.yaml`)
   - Domaine : baserow.example.com, n8n.example.com
   - Certificat : Let's Encrypt
   - SSL Redirect : Activé

### Configuration globale via ConfigMap

La configuration globale de l'ingress-nginx est gérée via un ConfigMap :

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
data:
  ssl-redirect: "false"
  force-ssl-redirect: "false"
```

### Variables d'environnement

Les configurations sont générées à partir du fichier `.env` :

```bash
# Domains configuration
BASEROW_LOCAL_DOMAIN=baserow.local
N8N_LOCAL_DOMAIN=n8n.local
BASEROW_PROD_DOMAIN=baserow.example.com
N8N_PROD_DOMAIN=n8n.example.com

# Ingress configuration
INGRESS_CLASS=nginx
CERT_MANAGER_LOCAL_ISSUER=selfsigned-issuer
CERT_MANAGER_PROD_ISSUER=letsencrypt-prod

# SSL configuration
SSL_REDIRECT=false
FORCE_SSL_REDIRECT=false
```

### Génération des configurations

Pour générer et appliquer les configurations :

```bash
# Rendre le script exécutable
chmod +x generate-ingress-configs.sh

# Générer et appliquer les configurations
./generate-ingress-configs.sh
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

### Déploiement des applications

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