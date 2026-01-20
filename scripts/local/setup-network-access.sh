#!/bin/bash
# scripts/local/setup-network-access.sh
# Script pour configurer l'accès réseau local aux services Kubernetes
# Combine dnsmasq (DNS) et port-forwarding sur l'IP du Mac Mini

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MAC_MINI_IP="192.168.1.71"
SERVICES=("baserow" "n8n" "excalidraw" "metabase" "supabase")

echo -e "${GREEN}🚀 Configuration de l'accès réseau local aux services Kubernetes${NC}"
echo -e "${BLUE}   IP du Mac Mini: ${MAC_MINI_IP}${NC}"
echo ""

# Fonction pour vérifier si une commande existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Fonction pour obtenir l'IP réelle de la machine
get_local_ip() {
    # Essayer différentes méthodes pour obtenir l'IP locale
    if command_exists ipconfig; then
        ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo ""
    elif command_exists hostname; then
        hostname -I | awk '{print $1}' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Détecter l'IP réelle si MAC_MINI_IP n'est pas défini
if [ -z "$MAC_MINI_IP" ] || [ "$MAC_MINI_IP" = "192.168.1.71" ]; then
    DETECTED_IP=$(get_local_ip)
    if [ -n "$DETECTED_IP" ]; then
        echo -e "${YELLOW}📍 IP détectée: ${DETECTED_IP}${NC}"
        read -p "Utiliser cette IP? (o/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Oo]$ ]]; then
            MAC_MINI_IP="$DETECTED_IP"
        fi
    fi
fi

# ============================================
# 1. Configuration de dnsmasq
# ============================================
echo ""
echo -e "${YELLOW}📡 Configuration de dnsmasq...${NC}"

# Vérifier que Homebrew est installé
if ! command_exists brew; then
    echo -e "${RED}❌ Homebrew n'est pas installé${NC}"
    echo "   Installez-le depuis: https://brew.sh"
    exit 1
fi

# Installer dnsmasq si nécessaire
if ! command_exists dnsmasq; then
    echo "   Installation de dnsmasq..."
    brew install dnsmasq
else
    echo -e "${GREEN}✓ dnsmasq déjà installé${NC}"
fi

# Trouver le chemin Homebrew
HOMEBREW_PREFIX=$(brew --prefix)
CONFIG_DIR="$HOMEBREW_PREFIX/etc"
CONFIG_FILE="$CONFIG_DIR/dnsmasq.conf"
LOG_FILE="/var/log/dnsmasq.log"

# Créer le répertoire de configuration
if [ ! -d "$CONFIG_DIR" ]; then
    echo "   Création du répertoire de configuration..."
    sudo mkdir -p "$CONFIG_DIR"
fi

# Créer le fichier de configuration
echo "   Configuration de dnsmasq pour les services Kubernetes..."
sudo tee "$CONFIG_FILE" > /dev/null << EOF
# Configuration DNS pour les services Kubernetes
# Généré automatiquement par setup-network-access.sh

# Écouter sur toutes les interfaces
listen-address=0.0.0.0,127.0.0.1

# Résolution DNS pour les services Kubernetes
address=/baserow.local/${MAC_MINI_IP}
address=/n8n.local/${MAC_MINI_IP}
address=/excalidraw.local/${MAC_MINI_IP}
address=/metabase.local/${MAC_MINI_IP}
address=/supabase.local/${MAC_MINI_IP}

# Serveurs DNS publics comme fallback
server=8.8.8.8
server=1.1.1.1

# Logs pour debug
log-queries
log-facility=${LOG_FILE}
EOF

# Créer le fichier de log
if [ ! -f "$LOG_FILE" ]; then
    sudo touch "$LOG_FILE"
    sudo chmod 644 "$LOG_FILE"
fi

# Tester la configuration
echo "   Test de la configuration dnsmasq..."
if sudo dnsmasq --test -C "$CONFIG_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓ Configuration dnsmasq valide${NC}"
else
    echo -e "${RED}❌ Erreur dans la configuration dnsmasq${NC}"
    exit 1
fi

# Démarrer/redémarrer dnsmasq
echo "   Démarrage de dnsmasq..."
if sudo brew services list | grep -q "dnsmasq.*started"; then
    echo "   Redémarrage de dnsmasq..."
    sudo brew services restart dnsmasq
else
    sudo brew services start dnsmasq
fi

sleep 2

# Vérifier que dnsmasq fonctionne
if sudo brew services list | grep -q "dnsmasq.*started"; then
    echo -e "${GREEN}✓ dnsmasq démarré${NC}"
else
    echo -e "${RED}❌ Échec du démarrage de dnsmasq${NC}"
    echo "   Vérifiez les logs: $LOG_FILE"
    exit 1
fi

# ============================================
# 2. Configuration du port-forwarding
# ============================================
echo ""
echo -e "${YELLOW}🔌 Configuration du port-forwarding...${NC}"

# Vérifier que kubectl est disponible
if ! command_exists kubectl; then
    echo -e "${RED}❌ kubectl n'est pas installé${NC}"
    exit 1
fi

# Vérifier la connexion au cluster
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}❌ Impossible de se connecter au cluster Kubernetes${NC}"
    echo "   Vérifiez que Docker Desktop est démarré et que Kubernetes est activé"
    exit 1
fi

echo -e "${GREEN}✓ Cluster Kubernetes accessible${NC}"

# Vérifier que l'Ingress Controller existe
if ! kubectl get namespace ingress-nginx &>/dev/null; then
    echo -e "${RED}❌ Ingress Controller n'est pas installé${NC}"
    echo "   Exécutez d'abord: ./scripts/local/setup-local-access.sh"
    exit 1
fi

# Arrêter les port-forwards existants
PORT_FORWARD_PID=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)
if [ -n "$PORT_FORWARD_PID" ]; then
    echo "   Arrêt du port-forward existant (PID: $PORT_FORWARD_PID)..."
    kill "$PORT_FORWARD_PID" 2>/dev/null || true
    sleep 2
fi

# Créer un fichier de log pour le port-forward
LOG_FILE_PF="/tmp/k8s-port-forward-network.log"

# Démarrer le port-forward sur toutes les interfaces
echo "   Démarrage du port-forward sur 0.0.0.0:80 et 0.0.0.0:443..."
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller \
    --address 0.0.0.0 80:80 443:443 > "$LOG_FILE_PF" 2>&1 &
PORT_FORWARD_PID=$!

sleep 3

# Vérifier que le port-forward fonctionne
if ps -p $PORT_FORWARD_PID > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Port-forward démarré (PID: $PORT_FORWARD_PID)${NC}"
    echo "   Logs disponibles dans: $LOG_FILE_PF"
else
    echo -e "${RED}❌ Échec du démarrage du port-forward${NC}"
    echo "   Vérifiez les logs: $LOG_FILE_PF"
    if [ -f "$LOG_FILE_PF" ]; then
        echo ""
        echo "   Dernières lignes du log :"
        tail -5 "$LOG_FILE_PF" | sed 's/^/   /'
    fi
    exit 1
fi

# ============================================
# 3. Vérification
# ============================================
echo ""
echo -e "${YELLOW}🔍 Vérification de la configuration...${NC}"

# Tester la résolution DNS
echo "   Test de la résolution DNS..."
if command_exists dig; then
    if dig @127.0.0.1 baserow.local +short | grep -q "$MAC_MINI_IP"; then
        echo -e "${GREEN}✓ Résolution DNS fonctionnelle${NC}"
    else
        echo -e "${YELLOW}⚠ Résolution DNS locale non fonctionnelle${NC}"
        echo "   Les machines distantes devront configurer $MAC_MINI_IP comme serveur DNS"
    fi
else
    echo -e "${YELLOW}⚠ dig non disponible, test DNS ignoré${NC}"
fi

# Tester la connectivité HTTP
echo "   Test de la connectivité HTTP..."
if curl -s -k -H "Host: baserow.local" "https://${MAC_MINI_IP}/" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Connectivité HTTP fonctionnelle${NC}"
else
    echo -e "${YELLOW}⚠ Connectivité HTTP non vérifiée${NC}"
    echo "   Vérifiez que les services sont déployés: kubectl get pods"
fi

# ============================================
# 4. Résumé et instructions
# ============================================
echo ""
echo -e "${GREEN}✅ Configuration terminée avec succès!${NC}"
echo ""
echo -e "${BLUE}📋 Résumé de la configuration:${NC}"
echo "   • DNS (dnsmasq): Actif sur $MAC_MINI_IP"
echo "   • Port-forward: Actif sur 0.0.0.0:80 et 0.0.0.0:443"
echo "   • PID port-forward: $PORT_FORWARD_PID"
echo ""
echo -e "${BLUE}🌐 Pour accéder aux services depuis d'autres machines:${NC}"
echo ""
echo "   1. Configurer le DNS sur les machines distantes:"
echo "      • Routeur: Définir $MAC_MINI_IP comme serveur DNS"
echo "      • Ou sur chaque machine: Définir $MAC_MINI_IP comme DNS dans les paramètres réseau"
echo ""
echo "   2. Accéder aux services via:"
for service in "${SERVICES[@]}"; do
    echo "      • https://${service}.local"
done
echo ""
echo -e "${BLUE}🔧 Commandes utiles:${NC}"
echo "   • Vérifier dnsmasq: sudo brew services list | grep dnsmasq"
echo "   • Voir les logs dnsmasq: tail -f $LOG_FILE"
echo "   • Vérifier le port-forward: ps aux | grep 'kubectl port-forward'"
echo "   • Arrêter le port-forward: kill $PORT_FORWARD_PID"
echo "   • Arrêter dnsmasq: sudo brew services stop dnsmasq"
echo ""
echo -e "${YELLOW}⚠ Note:${NC}"
echo "   • Le port-forward doit rester actif pour que les services soient accessibles"
echo "   • Utilisez 'screen' ou 'tmux' pour le garder actif en arrière-plan"
echo "   • Les certificats SSL sont auto-signés (avertissement navigateur normal)"
echo ""

# Sauvegarder le PID dans un fichier pour faciliter l'arrêt
echo "$PORT_FORWARD_PID" > /tmp/k8s-port-forward-network.pid
echo -e "${GREEN}✓ PID sauvegardé dans /tmp/k8s-port-forward-network.pid${NC}"

