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

# Avertissement sur sudo
if [ "$EUID" -ne 0 ] && ! sudo -n true 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}ℹ️  Note : Ce script nécessitera votre mot de passe sudo pour :${NC}"
    echo "   • Démarrer/arrêter le service dnsmasq (port 53)"
    echo "   • Créer le resolver macOS (/etc/resolver/)"
    echo ""
fi

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

# Fonction pour vérifier si dnsmasq tourne réellement
dnsmasq_is_running() {
    pgrep -f "dnsmasq.*dnsmasq.conf" >/dev/null 2>&1
}

# Vérifier si dnsmasq tourne déjà
if dnsmasq_is_running; then
    echo ""
    echo -e "${GREEN}✓ dnsmasq est déjà en cours d'exécution${NC}"
    
    # Vérifier si la configuration est correcte
    if dig @127.0.0.1 baserow.white-wood.local +short >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Configuration DNS fonctionnelle${NC}"
        SKIP_START=true
    else
        echo -e "${YELLOW}⚠ dnsmasq tourne mais la configuration DNS ne fonctionne pas${NC}"
        echo "   Arrêt de dnsmasq pour reconfiguration..."
        if command -v sudo >/dev/null 2>&1; then
            sudo brew services stop dnsmasq 2>/dev/null || true
            pkill -f "dnsmasq.*dnsmasq.conf" 2>/dev/null || true
            sleep 2
            SKIP_START=false
        else
            echo -e "${RED}❌ sudo n'est pas disponible. Arrêtez dnsmasq manuellement et relancez le script.${NC}"
            exit 1
        fi
    fi
else
    SKIP_START=false
fi

# Démarrer dnsmasq si nécessaire
if [ "$SKIP_START" != "true" ]; then
    echo ""
    echo -e "${YELLOW}🚀 Démarrage de dnsmasq...${NC}"
    
    # Vérifier si sudo est disponible
    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "${RED}❌ sudo est requis pour démarrer dnsmasq (port 53)${NC}"
        echo "   Exécutez le script avec : sudo ./scripts/local/install-dnsmasq.sh"
        exit 1
    fi
    
    # Arrêter dnsmasq s'il est enregistré avec brew services mais ne tourne pas
    if brew services list | grep dnsmasq | grep -E "started|error" >/dev/null 2>&1; then
        echo "   Nettoyage de l'ancien service..."
        sudo brew services stop dnsmasq 2>/dev/null || true
        sleep 2
    fi
    
    # Démarrer dnsmasq avec brew services
    if sudo brew services start dnsmasq 2>/dev/null; then
        echo "   Service démarré via brew services"
    else
        echo -e "${YELLOW}⚠ Échec du démarrage via brew services, tentative alternative...${NC}"
        # Alternative : démarrer directement
        sudo /opt/homebrew/opt/dnsmasq/sbin/dnsmasq --keep-in-foreground \
            -C /opt/homebrew/etc/dnsmasq.conf \
            -7 /opt/homebrew/etc/dnsmasq.d,*.conf &
        sleep 2
    fi
    
    # Attendre que le service démarre
    sleep 3
    
    # Vérifier que dnsmasq est bien démarré (vérification réelle du processus)
    MAX_RETRIES=5
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if dnsmasq_is_running; then
            echo -e "${GREEN}✓ dnsmasq démarré avec succès${NC}"
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "   Attente du démarrage... ($RETRY_COUNT/$MAX_RETRIES)"
            sleep 2
        fi
    done
    
    if ! dnsmasq_is_running; then
        echo -e "${RED}❌ Échec du démarrage de dnsmasq après $MAX_RETRIES tentatives${NC}"
        echo "   Vérifiez les logs : tail -f /opt/homebrew/var/log/dnsmasq.log"
        echo "   Ou exécutez manuellement : sudo /opt/homebrew/opt/dnsmasq/sbin/dnsmasq -C /opt/homebrew/etc/dnsmasq.conf"
        exit 1
    fi
fi

# Configurer macOS pour utiliser dnsmasq en priorité pour .white-wood.local
echo ""
echo -e "${YELLOW}⚙️  Configuration macOS pour utiliser dnsmasq...${NC}"

RESOLVER_DIR="/etc/resolver"
RESOLVER_FILE="$RESOLVER_DIR/white-wood.local"

# Vérifier si le resolver existe déjà et est correct
if [ -f "$RESOLVER_FILE" ]; then
    if grep -q "nameserver 127.0.0.1" "$RESOLVER_FILE" 2>/dev/null; then
        echo -e "${GREEN}✓ Resolver macOS déjà configuré${NC}"
        echo "   Fichier : $RESOLVER_FILE"
    else
        echo "   Mise à jour du resolver existant..."
        NEEDS_SUDO=true
    fi
else
    NEEDS_SUDO=true
fi

# Créer/mettre à jour le resolver si nécessaire
if [ "$NEEDS_SUDO" = "true" ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ sudo n'est pas disponible${NC}"
        echo "   Créez manuellement le fichier $RESOLVER_FILE avec le contenu suivant :"
        echo "   nameserver 127.0.0.1"
        echo "   port 53"
        echo ""
        echo "   Commande : sudo mkdir -p $RESOLVER_DIR && sudo tee $RESOLVER_FILE << 'EOF'"
        echo "   nameserver 127.0.0.1"
        echo "   port 53"
        echo "   EOF"
    else
        # Vérifier si on peut utiliser sudo sans mot de passe (NOPASSWD)
        if sudo -n true 2>/dev/null; then
            # sudo disponible sans mot de passe
            if [ ! -d "$RESOLVER_DIR" ]; then
                sudo mkdir -p "$RESOLVER_DIR"
            fi
            sudo bash -c "cat > $RESOLVER_FILE << 'EOF'
nameserver 127.0.0.1
port 53
EOF"
            echo -e "${GREEN}✓ Resolver macOS configuré${NC}"
            echo "   Fichier : $RESOLVER_FILE"
        else
            # sudo nécessite un mot de passe
            echo -e "${YELLOW}⚠ sudo nécessite votre mot de passe${NC}"
            echo "   Le script va maintenant demander votre mot de passe pour configurer le resolver macOS"
            echo ""
            
            if [ ! -d "$RESOLVER_DIR" ]; then
                sudo mkdir -p "$RESOLVER_DIR" || {
                    echo -e "${RED}❌ Échec de la création du répertoire $RESOLVER_DIR${NC}"
                    echo "   Créez-le manuellement avec : sudo mkdir -p $RESOLVER_DIR"
                    exit 1
                }
            fi
            
            sudo bash -c "cat > $RESOLVER_FILE << 'EOF'
nameserver 127.0.0.1
port 53
EOF" || {
                echo -e "${RED}❌ Échec de la création du resolver${NC}"
                echo "   Créez-le manuellement avec :"
                echo "   sudo tee $RESOLVER_FILE << 'EOF'"
                echo "   nameserver 127.0.0.1"
                echo "   port 53"
                echo "   EOF"
                exit 1
            }
            
            echo -e "${GREEN}✓ Resolver macOS configuré${NC}"
            echo "   Fichier : $RESOLVER_FILE"
        fi
    fi
fi

# Test de résolution DNS
echo ""
echo -e "${YELLOW}🧪 Test de résolution DNS...${NC}"

sleep 2

# Test avec dig (plus fiable que ping)
DNS_RESULT=$(dig @127.0.0.1 baserow.white-wood.local +short +timeout=2 2>/dev/null | head -1)

if [ -n "$DNS_RESULT" ] && [ "$DNS_RESULT" = "$MAC_IP" ]; then
    echo -e "${GREEN}✓ Résolution DNS fonctionnelle${NC}"
    echo "   baserow.white-wood.local -> $DNS_RESULT"
    
    # Test avec un autre domaine
    DNS_RESULT2=$(dig @127.0.0.1 n8n.white-wood.local +short +timeout=2 2>/dev/null | head -1)
    if [ -n "$DNS_RESULT2" ] && [ "$DNS_RESULT2" = "$MAC_IP" ]; then
        echo "   n8n.white-wood.local -> $DNS_RESULT2"
        echo -e "${GREEN}✓ Tous les domaines *.white-wood.local sont configurés${NC}"
    fi
else
    echo -e "${YELLOW}⚠ La résolution DNS ne fonctionne pas encore${NC}"
    echo "   Vérifiez que dnsmasq écoute sur le port 53 :"
    echo "   sudo lsof -i :53"
    echo "   Test manuel : dig @127.0.0.1 baserow.white-wood.local"
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
echo "   1. Exécutez ./scripts/local/setup-access.sh --network pour démarrer les services"
echo "   2. Configurez les autres appareils du réseau (voir README-NETWORK.md)"
echo ""
echo "🔧 Commandes utiles :"
echo "   • Redémarrer dnsmasq : sudo brew services restart dnsmasq"
echo "   • Arrêter dnsmasq : sudo brew services stop dnsmasq"
echo "   • Logs dnsmasq : tail -f /opt/homebrew/var/log/dnsmasq.log"
echo "   • Test DNS : dig @127.0.0.1 baserow.white-wood.local"
echo ""
