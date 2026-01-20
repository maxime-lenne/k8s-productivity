# Configuration de l'accès réseau local aux services Kubernetes

Ce guide explique comment configurer l'accès aux services Kubernetes (Baserow, n8n, Excalidraw, Metabase, Supabase) depuis n'importe quel appareil de votre réseau local via des URLs comme `https://baserow.white-wood.local`.

## Architecture

La solution utilise :
- **dnsmasq** : serveur DNS local qui résout `*.white-wood.local` vers l'IP du Mac Mini
- **kubectl port-forward** : expose l'Ingress Controller Kubernetes sur les ports 80/443 en écoute sur toutes les interfaces réseau (0.0.0.0)

```
┌─────────────────────────────────────────────────────────────┐
│  Appareil sur le réseau local (iPhone, iPad, autre Mac...)  │
│                                                               │
│  1. Requête DNS : baserow.white-wood.local                   │
│     ↓                                                         │
│  2. Serveur DNS : Mac Mini (192.168.x.x)                     │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ↓
┌─────────────────────────────────────────────────────────────┐
│  Mac Mini (192.168.x.x)                                      │
│                                                               │
│  ┌──────────────┐        ┌─────────────────────────┐        │
│  │   dnsmasq    │  →  →  │  kubectl port-forward   │        │
│  │   (port 53)  │        │  (ports 80/443)         │        │
│  └──────────────┘        └───────────┬─────────────┘        │
│                                      │                       │
│                                      ↓                       │
│                          ┌─────────────────────────┐        │
│                          │  Ingress Controller     │        │
│                          │  (Kubernetes)           │        │
│                          └───────────┬─────────────┘        │
│                                      │                       │
│                          ┌───────────┴─────────────┐        │
│                          │  Services (Pods)        │        │
│                          │  • Baserow              │        │
│                          │  • n8n                  │        │
│                          │  • Excalidraw           │        │
│                          │  • Metabase             │        │
│                          │  • Supabase             │        │
│                          └─────────────────────────┘        │
└─────────────────────────────────────────────────────────────┘
```

## Configuration du Mac Mini (Serveur)

### 1. Installation et configuration de dnsmasq

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
- Configurer macOS pour utiliser dnsmasq comme resolver DNS pour `.white-wood.local`
- Démarrer le service dnsmasq

### 2. Déploiement des services Kubernetes

```bash
# Appliquer les configurations Kubernetes
kubectl apply -k environments/local

# Attendre que les pods soient prêts
kubectl wait --for=condition=ready pod --all --timeout=300s
```

### 3. Démarrage de l'accès réseau

```bash
# Démarrer le port-forward réseau (nécessite sudo)
sudo ./scripts/local/setup-network-access.sh
```

Ce script va :
- Vérifier que dnsmasq est actif
- Vérifier que le cluster Kubernetes est accessible
- Configurer cert-manager et l'Ingress Controller
- Démarrer le port-forward sur `0.0.0.0:80` et `0.0.0.0:443`

### 4. Vérification

```bash
# Vérifier l'état des services
kubectl get pods
kubectl get ingress
kubectl get certificate

# Tester la résolution DNS locale
dig @127.0.0.1 baserow.white-wood.local

# Tester l'accès HTTP/HTTPS
curl -k https://baserow.white-wood.local
```

### 5. Arrêt du service

```bash
# Arrêter le port-forward
./scripts/local/stop-network-access.sh

# Arrêter dnsmasq (optionnel)
sudo brew services stop dnsmasq
```

## Configuration des appareils clients

### Prérequis

1. Tous les appareils doivent être sur le même réseau local que le Mac Mini
2. Vous devez connaître l'IP locale du Mac Mini (affichée lors de l'exécution des scripts, par exemple `192.168.1.100`)

### iOS / iPadOS

1. Ouvrir **Réglages** → **Wi-Fi**
2. Appuyer sur **(i)** à côté du réseau Wi-Fi actuel
3. Descendre jusqu'à **Configurer DNS**
4. Sélectionner **Manuel**
5. Ajouter le serveur DNS : `192.168.x.x` (IP du Mac Mini)
6. Optionnel : conserver les DNS existants (Google, Cloudflare) comme DNS secondaires
7. Enregistrer

### macOS

1. Ouvrir **Préférences Système** → **Réseau**
2. Sélectionner la connexion active (Wi-Fi ou Ethernet)
3. Cliquer sur **Avancé**
4. Onglet **DNS**
5. Cliquer sur **+** pour ajouter un serveur DNS
6. Entrer l'IP du Mac Mini : `192.168.x.x`
7. Optionnel : monter ce DNS en première position dans la liste
8. Cliquer sur **OK** puis **Appliquer**

### Windows

1. Ouvrir le **Panneau de configuration** → **Centre Réseau et partage**
2. Cliquer sur votre connexion active
3. Cliquer sur **Propriétés**
4. Sélectionner **Protocole Internet version 4 (TCP/IPv4)**
5. Cliquer sur **Propriétés**
6. Sélectionner **Utiliser l'adresse de serveur DNS suivante**
7. Serveur DNS préféré : `192.168.x.x` (IP du Mac Mini)
8. Serveur DNS auxiliaire : `8.8.8.8` (Google DNS, optionnel)
9. Cliquer sur **OK**

### Linux

#### Méthode 1 : NetworkManager (Ubuntu, Fedora, etc.)

```bash
# Via l'interface graphique
nmcli connection modify "Nom de la connexion" ipv4.dns "192.168.x.x 8.8.8.8"
nmcli connection down "Nom de la connexion"
nmcli connection up "Nom de la connexion"
```

#### Méthode 2 : /etc/resolv.conf (méthode manuelle)

```bash
# Éditer /etc/resolv.conf
sudo nano /etc/resolv.conf

# Ajouter en première ligne
nameserver 192.168.x.x
nameserver 8.8.8.8
```

**Note** : Sur certaines distributions, `/etc/resolv.conf` est généré automatiquement. Dans ce cas, modifiez la configuration de votre gestionnaire réseau.

### Android

1. Ouvrir **Paramètres** → **Wi-Fi**
2. Appui long sur le réseau Wi-Fi connecté
3. Sélectionner **Modifier le réseau**
4. Cocher **Options avancées**
5. **Paramètres IP** : Statique
6. **DNS 1** : `192.168.x.x` (IP du Mac Mini)
7. **DNS 2** : `8.8.8.8` (Google DNS, optionnel)
8. Enregistrer

## Test de connectivité

Une fois la configuration DNS effectuée sur l'appareil client :

### 1. Test DNS

Ouvrir un terminal ou une app de commande et tester la résolution DNS :

```bash
# Sur macOS/Linux
dig baserow.white-wood.local

# Sur Windows (PowerShell)
Resolve-DnsName baserow.white-wood.local

# Sur iOS/Android
# Utiliser une app comme "Network Analyzer" ou "DNS Lookup"
```

Le résultat doit afficher l'IP du Mac Mini.

### 2. Test HTTP/HTTPS

Ouvrir un navigateur et accéder à :
- https://baserow.white-wood.local
- https://n8n.white-wood.local
- https://excalidraw.white-wood.local
- https://metabase.white-wood.local
- https://supabase.white-wood.local

**Note** : Vous verrez un avertissement de certificat SSL car les certificats sont auto-signés. C'est normal et sécurisé pour un usage local.

Sur chaque appareil :
- **Safari/Chrome** : Cliquer sur "Avancé" puis "Continuer vers le site"
- **Firefox** : Cliquer sur "Avancé" → "Accepter le risque et continuer"

### 3. Test avancé

```bash
# Tester la connectivité HTTP
curl -k -I https://baserow.white-wood.local

# Tester la résolution DNS complète
nslookup baserow.white-wood.local
```

## Dépannage

### Le DNS ne résout pas les domaines `.white-wood.local`

1. Vérifier que dnsmasq est actif sur le Mac Mini :
   ```bash
   brew services list | grep dnsmasq
   ```

2. Vérifier que le serveur DNS du client pointe bien vers le Mac Mini :
   ```bash
   # macOS/Linux
   cat /etc/resolv.conf | grep nameserver

   # iOS/Android : vérifier dans les paramètres Wi-Fi
   ```

3. Tester la résolution DNS directement :
   ```bash
   dig @192.168.x.x baserow.white-wood.local
   ```

4. Vider le cache DNS :
   ```bash
   # macOS
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder

   # Windows
   ipconfig /flushdns

   # Linux
   sudo systemd-resolve --flush-caches
   ```

### Les services ne sont pas accessibles depuis le réseau

1. Vérifier que le port-forward est actif sur le Mac Mini :
   ```bash
   ps aux | grep "kubectl port-forward"
   cat /tmp/k8s-logs/network-port-forward.log
   ```

2. Vérifier que les ports 80 et 443 sont accessibles :
   ```bash
   # Depuis un autre appareil
   nc -zv 192.168.x.x 80
   nc -zv 192.168.x.x 443
   ```

3. Vérifier le pare-feu macOS :
   ```bash
   # Autoriser les connexions entrantes
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/kubectl
   sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/local/bin/kubectl
   ```

4. Redémarrer le port-forward :
   ```bash
   ./scripts/local/stop-network-access.sh
   sudo ./scripts/local/setup-network-access.sh
   ```

### Les pods ne sont pas prêts

```bash
# Vérifier l'état des pods
kubectl get pods

# Voir les logs d'un pod spécifique
kubectl logs <pod-name>

# Voir les événements
kubectl get events --sort-by='.lastTimestamp'

# Redéployer les services
kubectl delete pods --all
kubectl wait --for=condition=ready pod --all --timeout=300s
```

### Les certificats SSL ne sont pas générés

```bash
# Vérifier l'état des certificats
kubectl get certificate

# Voir les détails d'un certificat
kubectl describe certificate apps-tls-local-cert

# Vérifier cert-manager
kubectl get pods -n cert-manager

# Redéployer le certificat
kubectl delete certificate apps-tls-local-cert
kubectl apply -k environments/local
```

## Commandes utiles

### Gestion du service

```bash
# Démarrer l'accès réseau
sudo ./scripts/local/setup-network-access.sh

# Arrêter l'accès réseau
./scripts/local/stop-network-access.sh

# Redémarrer dnsmasq
sudo brew services restart dnsmasq

# Voir les logs du port-forward
tail -f /tmp/k8s-logs/network-port-forward.log

# Voir les logs de dnsmasq (si activé dans la config)
tail -f /opt/homebrew/var/log/dnsmasq.log
```

### Diagnostic Kubernetes

```bash
# État général
kubectl get all
kubectl get ingress
kubectl get certificate

# Logs des services
kubectl logs -l app=baserow
kubectl logs -l app=n8n
kubectl logs -l app=excalidraw

# Tester l'Ingress Controller
kubectl get pods -n ingress-nginx
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller
```

### Test réseau

```bash
# Depuis le Mac Mini
curl -k https://baserow.white-wood.local
dig @127.0.0.1 baserow.white-wood.local

# Depuis un autre appareil
curl -k https://baserow.white-wood.local
nslookup baserow.white-wood.local
```

## Sécurité

### Certificats SSL auto-signés

Les certificats SSL sont auto-signés et générés automatiquement par cert-manager. Ils sont parfaitement sécurisés pour un usage local mais généreront des avertissements dans les navigateurs.

Pour une utilisation en production, vous devriez utiliser Let's Encrypt avec un domaine public.

### Pare-feu

Par défaut, macOS peut bloquer les connexions entrantes. Si vous avez des problèmes de connectivité depuis d'autres appareils, vérifiez les paramètres du pare-feu :

**Préférences Système** → **Sécurité et confidentialité** → **Pare-feu**

Autorisez les connexions entrantes pour `kubectl`.

### Réseau privé uniquement

Cette configuration est conçue pour un usage sur un réseau local privé uniquement. Ne l'exposez jamais directement sur Internet sans :
1. Une authentification forte sur tous les services
2. Des certificats SSL valides
3. Un pare-feu correctement configuré
4. Des mises à jour de sécurité régulières

## FAQ

### Puis-je utiliser un autre domaine que `.white-wood.local` ?

Oui, modifiez :
1. `scripts/local/install-dnsmasq.sh` : changez `white-wood.local` par votre domaine
2. `environments/local/kustomization.yaml` : mettez à jour tous les domaines
3. Redéployez : `kubectl apply -k environments/local`

### Puis-je accéder aux services depuis l'extérieur de mon réseau local ?

Non, pas avec cette configuration. Pour un accès externe, vous devriez :
1. Configurer un VPN (Wireguard, Tailscale)
2. Utiliser un tunnel (Cloudflare Tunnel, ngrok)
3. Exposer via un reverse proxy public (avec Let's Encrypt)

### Le port-forward va-t-il survivre à un redémarrage ?

Non, vous devez relancer le script après chaque redémarrage du Mac Mini.

Pour démarrer automatiquement au boot, créez un LaunchDaemon macOS :

```bash
# Créer /Library/LaunchDaemons/com.k8s.network-access.plist
sudo nano /Library/LaunchDaemons/com.k8s.network-access.plist
```

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.k8s.network-access</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/path/to/k8s-productivity/scripts/local/setup-network-access.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/k8s-network-access.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/k8s-network-access.err</string>
</dict>
</plist>
```

```bash
sudo launchctl load /Library/LaunchDaemons/com.k8s.network-access.plist
```

### Comment désinstaller complètement la configuration ?

```bash
# Arrêter les services
./scripts/local/stop-network-access.sh
sudo brew services stop dnsmasq

# Supprimer dnsmasq
brew uninstall dnsmasq

# Supprimer la configuration DNS macOS
sudo rm /etc/resolver/white-wood.local

# Nettoyer les logs
rm -rf /tmp/k8s-logs

# Sur les clients, retirer le serveur DNS du Mac Mini
```

## Licence

MIT
