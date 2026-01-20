# Accès réseau local aux services Kubernetes

Ce guide explique comment configurer l'accès aux services Kubernetes depuis d'autres machines sur votre réseau local.

## Vue d'ensemble

Pour accéder aux services (Baserow, N8N, Excalidraw, Metabase, Supabase) depuis d'autres machines sur votre réseau local, deux composants sont nécessaires :

1. **DNS local (dnsmasq)** : Résout les domaines `.local` vers l'IP du Mac Mini
2. **Port-forwarding** : Expose l'Ingress Controller sur toutes les interfaces réseau

## Configuration automatique

Un script automatique est disponible pour configurer ces deux composants :

```bash
./scripts/local/setup-network-access.sh
```

Ce script :
- ✅ Installe et configure dnsmasq
- ✅ Configure la résolution DNS pour tous les services
- ✅ Démarre le port-forwarding sur `0.0.0.0:80` et `0.0.0.0:443`
- ✅ Vérifie que tout fonctionne correctement

### Prérequis

- Homebrew installé
- Cluster Kubernetes opérationnel
- Ingress Controller installé (exécutez `./scripts/local/setup-local-access.sh` d'abord)

### Utilisation

1. **Démarrer l'accès réseau local** :
   ```bash
   ./scripts/local/setup-network-access.sh
   ```

2. **Arrêter l'accès réseau local** :
   ```bash
   ./scripts/local/stop-network-access.sh
   ```

## Configuration manuelle

### 1. Configuration de dnsmasq

```bash
# Installer dnsmasq
brew install dnsmasq

# Trouver le chemin Homebrew
HOMEBREW_PREFIX=$(brew --prefix)
CONFIG_FILE="$HOMEBREW_PREFIX/etc/dnsmasq.conf"

# Créer la configuration
sudo tee "$CONFIG_FILE" > /dev/null << EOF
listen-address=0.0.0.0,127.0.0.1
address=/baserow.local/192.168.1.71
address=/n8n.local/192.168.1.71
address=/excalidraw.local/192.168.1.71
address=/metabase.local/192.168.1.71
address=/supabase.local/192.168.1.71
server=8.8.8.8
server=1.1.1.1
EOF

# Démarrer dnsmasq
sudo brew services start dnsmasq
```

### 2. Configuration du port-forwarding

```bash
# Arrêter les port-forwards existants
pkill -f "kubectl port-forward.*ingress-nginx-controller"

# Démarrer le port-forward sur toutes les interfaces
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller \
    --address 0.0.0.0 80:80 443:443
```

## Accès depuis d'autres machines

### Option 1 : Configuration DNS sur le routeur (recommandé)

Configurez votre routeur pour utiliser l'IP du Mac Mini (192.168.1.71) comme serveur DNS. Toutes les machines du réseau utiliseront automatiquement la résolution DNS locale.

### Option 2 : Configuration DNS sur chaque machine

**Sur Linux/Mac** :
```bash
# Modifier /etc/resolv.conf ou les paramètres réseau
# Ajouter 192.168.1.71 comme serveur DNS primaire
```

**Sur Windows** :
1. Ouvrir "Paramètres réseau"
2. Modifier les propriétés de la connexion réseau
3. Configurer l'adresse IPv4 avec DNS personnalisé : `192.168.1.71`

### Option 3 : Modification de /etc/hosts (alternative)

Si vous ne pouvez pas configurer le DNS, modifiez `/etc/hosts` sur chaque machine :

```bash
# Sur chaque machine distante
sudo bash -c 'cat >> /etc/hosts' << 'HOSTS'
192.168.1.71	baserow.local
192.168.1.71	n8n.local
192.168.1.71	excalidraw.local
192.168.1.71	metabase.local
192.168.1.71	supabase.local
HOSTS
```

## Accès aux services

Une fois la configuration terminée, accédez aux services depuis n'importe quelle machine du réseau :

- **Baserow** : https://baserow.local
- **N8N** : https://n8n.local
- **Excalidraw** : https://excalidraw.local
- **Metabase** : https://metabase.local
- **Supabase Studio** : https://supabase.local

**Note** : Les certificats SSL sont auto-signés. Votre navigateur affichera un avertissement de sécurité. C'est normal en local. Acceptez le certificat pour continuer.

## Scripts disponibles

### `setup-network-access.sh`

Script principal pour configurer l'accès réseau local.

**Fonctionnalités** :
- Installation automatique de dnsmasq si nécessaire
- Configuration DNS pour tous les services
- Démarrage du port-forwarding sur toutes les interfaces
- Vérification de la configuration
- Détection automatique de l'IP locale

**Utilisation** :
```bash
./scripts/local/setup-network-access.sh
```

### `stop-network-access.sh`

Script pour arrêter l'accès réseau local.

**Fonctionnalités** :
- Arrêt du port-forwarding
- Option pour arrêter dnsmasq

**Utilisation** :
```bash
./scripts/local/stop-network-access.sh
```

## Vérification

### Tester la résolution DNS

```bash
# Depuis n'importe quelle machine du réseau
dig @192.168.1.71 baserow.local
# ou
nslookup baserow.local 192.168.1.71
```

### Tester la connectivité HTTP

```bash
# Depuis n'importe quelle machine du réseau
curl -k -H "Host: baserow.local" https://192.168.1.71/
```

### Vérifier les services

```bash
# Sur le Mac Mini
# Vérifier dnsmasq
sudo brew services list | grep dnsmasq

# Vérifier le port-forward
ps aux | grep "kubectl port-forward"

# Voir les logs dnsmasq
tail -f /var/log/dnsmasq.log
```

## Dépannage

### Le port-forward s'arrête

Le port-forward s'arrête si le terminal se ferme. Pour le garder actif :

```bash
# Utiliser screen
screen -S k8s-port-forward
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller --address 0.0.0.0 80:80 443:443
# Appuyer sur Ctrl+A puis D pour détacher

# Ou utiliser tmux
tmux new -s k8s-port-forward
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller --address 0.0.0.0 80:80 443:443
# Appuyer sur Ctrl+B puis D pour détacher
```

### Le DNS ne fonctionne pas

1. Vérifier que dnsmasq est démarré :
   ```bash
   sudo brew services list | grep dnsmasq
   ```

2. Vérifier la configuration :
   ```bash
   sudo dnsmasq --test
   ```

3. Vérifier les logs :
   ```bash
   tail -f /var/log/dnsmasq.log
   ```

4. Vérifier que le firewall autorise les connexions DNS (port 53)

### Les services ne sont pas accessibles

1. Vérifier que le port-forward est actif :
   ```bash
   ps aux | grep "kubectl port-forward"
   ```

2. Vérifier que les services sont déployés :
   ```bash
   kubectl get pods
   ```

3. Vérifier que l'Ingress Controller fonctionne :
   ```bash
   kubectl get pods -n ingress-nginx
   ```

4. Vérifier les logs du port-forward :
   ```bash
   tail -f /tmp/k8s-port-forward-network.log
   ```

## Notes importantes

- **Firewall** : Assurez-vous que les ports 80, 443 et 53 sont ouverts sur le Mac Mini
- **Persistance** : Le port-forward doit rester actif. Utilisez `screen` ou `tmux` pour le garder actif
- **Certificats SSL** : Les certificats sont auto-signés. Acceptez-les dans votre navigateur
- **IP dynamique** : Si l'IP du Mac Mini change, mettez à jour la configuration dnsmasq et redémarrez-le

