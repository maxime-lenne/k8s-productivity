#!/bin/bash

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🌐 Installation et configuration de dnsmasq pour le réseau local${NC}"
echo ""

# Vérifier si Homebrew est installé
if ! command -v brew &>/dev/null; then
    echo -e "${RED}❌ Homebrew n'est pas installé${NC}"
    echo "   Installez Homebrew : https://brew.sh"
    exit 1
fi

echo -e "${GREEN}✓ Homebrew est installé${NC}"

# Installer dnsmasq si nécessaire
if ! brew list dnsmasq &>/dev/null; then
    echo ""
    echo -e "${YELLOW}📦 Installation de dnsmasq...${NC}"
    brew install dnsmasq
    echo -e "${GREEN}✓ dnsmasq installé${NC}"
else
    echo -e "${GREEN}✓ dnsmasq déjà installé${NC}"
fi

# Détecter l'IP locale du Mac Mini (interface principale)
echo ""
echo -e "${YELLOW}🔍 Détection de l'IP locale...${NC}"

# Essayer de trouver l'IP sur l'interface réseau principale (en0 ou en1)
MAC_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

if [ -z "$MAC_IP" ]; then
    echo -e "${RED}❌ Impossible de détecter l'IP locale${NC}"
    echo "   Vérifiez votre connexion réseau"
    exit 1
fi

echo -e "${GREEN}✓ IP locale détectée : $MAC_IP${NC}"

# Configurer dnsmasq
echo ""
echo -e "${YELLOW}⚙️  Configuration de dnsmasq...${NC}"

DNSMASQ_CONF="/opt/homebrew/etc/dnsmasq.conf"

# Créer la configuration dnsmasq
cat > "$DNSMASQ_CONF" << EOF
# Configuration dnsmasq pour k8s-productivity
# Généré automatiquement

# Port DNS standard
port=53

# Interface d'écoute (toutes les interfaces)
listen-address=127.0.0.1,$MAC_IP

# Ne pas lire /etc/resolv.conf pour les serveurs DNS upstream
no-resolv

# Serveurs DNS upstream (Cloudflare et Google)
server=1.1.1.1
server=8.8.8.8

# Ne pas transférer les requêtes sans domaine
domain-needed

# Ne pas transférer les requêtes pour les adresses privées
bogus-priv

# Domaine local
local=/white-wood.local/
domain=white-wood.local

# Résoudre tous les *.white-wood.local vers l'IP du Mac Mini
address=/white-wood.local/$MAC_IP

# Cache DNS
cache-size=1000

# Log les requêtes DNS (optionnel, décommentez pour debug)
# log-queries
# log-facility=/opt/homebrew/var/log/dnsmasq.log
EOF

echo -e "${GREEN}✓ Configuration dnsmasq créée${NC}"
echo "   Fichier : $DNSMASQ_CONF"
echo "   Domaines : *.white-wood.local -> $MAC_IP"

# Arrêter dnsmasq s'il est en cours d'exécution
if brew services list | grep dnsmasq | grep started >/dev/null; then
    echo ""
    echo -e "${YELLOW}🛑 Arrêt du service dnsmasq existant...${NC}"
    sudo brew services stop dnsmasq
fi

# Démarrer dnsmasq
echo ""
echo -e "${YELLOW}🚀 Démarrage de dnsmasq...${NC}"

# dnsmasq nécessite sudo pour écouter sur le port 53
sudo brew services start dnsmasq

# Attendre que le service démarre
sleep 2

# Vérifier que dnsmasq est bien démarré
if brew services list | grep dnsmasq | grep started >/dev/null; then
    echo -e "${GREEN}✓ dnsmasq démarré avec succès${NC}"
else
    echo -e "${RED}❌ Échec du démarrage de dnsmasq${NC}"
    echo "   Vérifiez les logs : tail -f /opt/homebrew/var/log/dnsmasq.log"
    exit 1
fi

# Configurer macOS pour utiliser dnsmasq en priorité pour .white-wood.local
echo ""
echo -e "${YELLOW}⚙️  Configuration macOS pour utiliser dnsmasq...${NC}"

RESOLVER_DIR="/etc/resolver"
if [ ! -d "$RESOLVER_DIR" ]; then
    sudo mkdir -p "$RESOLVER_DIR"
fi

# Créer un resolver pour .white-wood.local
sudo bash -c "cat > $RESOLVER_DIR/white-wood.local << EOF
nameserver 127.0.0.1
port 53
EOF"

echo -e "${GREEN}✓ Resolver macOS configuré${NC}"
echo "   Fichier : $RESOLVER_DIR/white-wood.local"

# Test de résolution DNS
echo ""
echo -e "${YELLOW}🧪 Test de résolution DNS...${NC}"

sleep 1

if ping -c 1 -t 1 baserow.white-wood.local &>/dev/null; then
    echo -e "${GREEN}✓ Résolution DNS fonctionnelle${NC}"
    echo "   baserow.white-wood.local -> $MAC_IP"
else
    echo -e "${YELLOW}⚠ La résolution DNS peut prendre quelques secondes...${NC}"
fi

# Résumé
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         INSTALLATION DNSMASQ TERMINÉE                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📝 Configuration :"
echo "   • IP du Mac Mini : $MAC_IP"
echo "   • Domaines : *.white-wood.local"
echo "   • Port DNS : 53"
echo ""
echo "🎯 Prochaines étapes :"
echo "   1. Exécutez ./scripts/local/setup-network-access.sh pour démarrer les services"
echo "   2. Configurez les autres appareils du réseau (voir README-NETWORK.md)"
echo ""
echo "🔧 Commandes utiles :"
echo "   • Redémarrer dnsmasq : sudo brew services restart dnsmasq"
echo "   • Arrêter dnsmasq : sudo brew services stop dnsmasq"
echo "   • Logs dnsmasq : tail -f /opt/homebrew/var/log/dnsmasq.log"
echo "   • Test DNS : dig @127.0.0.1 baserow.white-wood.local"
echo ""
