#!/bin/bash
# scripts/local/setup-access.sh
# Script unifié pour configurer l'accès aux services Kubernetes
# Usage: ./setup-access.sh [OPTIONS]
#   --network, -n              Configure l'accès réseau (dnsmasq + écoute sur 0.0.0.0)
#   --http-port PORT           Port HTTP local (défaut: 80 avec sudo, 8080 sans sudo)
#   --https-port PORT          Port HTTPS local (défaut: 444, le 443 est réservé à un autre usage)
#   --help, -h                 Affiche cette aide
#
# Variables d'environnement:
#   K8S_HTTP_PORT              Port HTTP local
#   K8S_HTTPS_PORT             Port HTTPS local
#
# Sans option, configure l'accès local uniquement (127.0.0.1)

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Mode par défaut : local
NETWORK_MODE=false
HTTP_PORT=""
HTTPS_PORT=""

# Port HTTPS exposé par le Service ingress-nginx-controller (et donc par le
# load balancer de Docker Desktop). 443 étant déjà utilisé sur la machine,
# tout le cluster local passe par 444 : https://<app>.white-wood.local:444
HTTPS_SERVICE_PORT=444

# Fonction pour vérifier si un port est disponible
is_port_available() {
    local port=$1
    if command -v lsof >/dev/null 2>&1; then
        ! lsof -i :"$port" >/dev/null 2>&1
    elif command -v netstat >/dev/null 2>&1; then
        ! netstat -an | grep -q ":$port.*LISTEN"
    else
        # Si aucun outil n'est disponible, on suppose que le port est disponible
        true
    fi
}

# Fonction pour trouver un port disponible
find_available_port() {
    local start_port=$1
    local port=$start_port
    local max_attempts=100
    
    while [ $port -lt $((start_port + max_attempts)) ]; do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done
    
    echo ""
    return 1
}

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --network|-n)
            NETWORK_MODE=true
            shift
            ;;
        --http-port)
            HTTP_PORT="$2"
            shift 2
            ;;
        --https-port)
            HTTPS_PORT="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --network, -n              Configure l'accès réseau (accessible depuis d'autres appareils)"
            echo "  --http-port PORT           Port HTTP local (défaut: 80 avec sudo, 8080 sans sudo)"
            echo "  --https-port PORT          Port HTTPS local (défaut: 444, le 443 est réservé à un autre usage)"
            echo "  --help, -h                 Affiche cette aide"
            echo ""
            echo "Variables d'environnement:"
            echo "  K8S_HTTP_PORT              Port HTTP local"
            echo "  K8S_HTTPS_PORT             Port HTTPS local"
            echo ""
            echo "Sans option, configure l'accès local uniquement (127.0.0.1)"
            echo ""
            echo "Exemples:"
            echo "  $0                                    # Mode local avec ports par défaut"
            echo "  $0 --http-port 8080 --https-port 8443 # Mode local avec ports personnalisés"
            echo "  sudo $0 --network                      # Mode réseau avec ports 80/444"
            echo "  sudo $0 --network --http-port 8880     # Mode réseau avec port HTTP personnalisé"
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Utilisez --help pour voir les options disponibles"
            exit 1
            ;;
    esac
done

# Utiliser les variables d'environnement si les ports ne sont pas spécifiés en argument
if [ -z "$HTTP_PORT" ] && [ -n "$K8S_HTTP_PORT" ]; then
    HTTP_PORT="$K8S_HTTP_PORT"
fi
if [ -z "$HTTPS_PORT" ] && [ -n "$K8S_HTTPS_PORT" ]; then
    HTTPS_PORT="$K8S_HTTPS_PORT"
fi

# Fonction pour vérifier si une commande existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Afficher le mode
if [ "$NETWORK_MODE" = true ]; then
    echo -e "${GREEN}🚀 Configuration de l'accès RÉSEAU aux services Kubernetes${NC}"
    echo -e "${BLUE}   Mode: Accessible depuis le réseau local${NC}"
else
    echo -e "${GREEN}🚀 Configuration de l'accès LOCAL aux services Kubernetes${NC}"
    echo -e "${BLUE}   Mode: Accessible uniquement depuis cette machine${NC}"
fi
echo ""

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

# Configuration DNS selon le mode
echo ""
if [ "$NETWORK_MODE" = true ]; then
    echo -e "${YELLOW}🌐 Vérification de dnsmasq...${NC}"

    if ! command_exists dnsmasq; then
        echo -e "${RED}❌ dnsmasq n'est pas installé${NC}"
        echo "   Exécutez d'abord : ./scripts/local/install-dnsmasq.sh"
        exit 1
    fi

    if ! brew services list | grep dnsmasq | grep started >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ dnsmasq n'est pas démarré${NC}"
        echo "   Démarrage de dnsmasq..."
        sudo brew services start dnsmasq
        sleep 2
    fi

    echo -e "${GREEN}✓ dnsmasq est actif${NC}"

    # Détecter l'IP locale
    echo ""
    echo -e "${YELLOW}🔍 Détection de l'IP locale...${NC}"
    MAC_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

    if [ -z "$MAC_IP" ]; then
        echo -e "${RED}❌ Impossible de détecter l'IP locale${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ IP locale détectée : $MAC_IP${NC}"
    BIND_ADDRESS="0.0.0.0"
    DOMAIN_SUFFIX="white-wood.local"
else
    echo -e "${YELLOW}📝 Configuration de /etc/hosts...${NC}"

    # Vérifier si les entrées existent déjà
    if grep -qE "127\.0\.0\.1.*(baserow|n8n|excalidraw|metabase|supabase)\.white-wood\.local" /etc/hosts 2>/dev/null; then
        echo -e "${GREEN}✓ /etc/hosts déjà configuré${NC}"
    else
        echo "   Nettoyage des anciennes entrées..."
        sudo sed -i '' '/\.white-wood\.local/d' /etc/hosts 2>/dev/null || true

        echo "   Ajout des entrées dans /etc/hosts..."
        echo "127.0.0.1 baserow.white-wood.local n8n.white-wood.local excalidraw.white-wood.local metabase.white-wood.local supabase.white-wood.local" | sudo tee -a /etc/hosts > /dev/null
        echo -e "${GREEN}✓ /etc/hosts configuré${NC}"
    fi

    BIND_ADDRESS="127.0.0.1"
    DOMAIN_SUFFIX="white-wood.local"
fi

# Vérifier/Installer l'Ingress Controller
echo ""
echo -e "${YELLOW}🌐 Vérification de l'Ingress Controller...${NC}"

if ! kubectl get namespace ingress-nginx &>/dev/null; then
    echo "   Installation de l'Ingress Controller..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=90s
fi

# Faire écouter le Service ingress-nginx sur $HTTPS_SERVICE_PORT au lieu de 443.
# Le manifeste upstream (re)positionne 443 : on le corrige après chaque installation.
HTTPS_PORT_INDEX=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{range .spec.ports[*]}{.name}{"\n"}{end}' | grep -n '^https$' | cut -d: -f1)
CURRENT_HTTPS_SVC_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
    -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
if [ -n "$HTTPS_PORT_INDEX" ] && [ "$CURRENT_HTTPS_SVC_PORT" != "$HTTPS_SERVICE_PORT" ]; then
    echo "   Passage du port HTTPS du Service ingress-nginx : $CURRENT_HTTPS_SVC_PORT -> $HTTPS_SERVICE_PORT"
    kubectl patch svc ingress-nginx-controller -n ingress-nginx --type=json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/ports/$((HTTPS_PORT_INDEX - 1))/port\",\"value\":$HTTPS_SERVICE_PORT}]"
    # Le load balancer Docker Desktop (kindccm-*) publie les ports à sa création :
    # on le supprime, il est recréé automatiquement avec le nouveau port.
    LB_CONTAINER=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep '^kindccm-' || true)
    if [ -n "$LB_CONTAINER" ]; then
        echo "   Recréation du load balancer Docker ($LB_CONTAINER)..."
        docker rm -f $LB_CONTAINER >/dev/null
        kubectl annotate svc ingress-nginx-controller -n ingress-nginx sync-trigger="$(date +%s)" --overwrite >/dev/null
    fi
fi

echo -e "${GREEN}✓ Ingress Controller prêt${NC}"

# Vérifier/Installer cert-manager
echo ""
echo -e "${YELLOW}🔒 Vérification de cert-manager...${NC}"

if ! kubectl get namespace cert-manager &>/dev/null; then
    echo "   Installation de cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
    kubectl wait --namespace cert-manager \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/instance=cert-manager \
        --timeout=90s
fi

if ! kubectl get clusterissuer selfsigned-issuer &>/dev/null; then
    echo "   Création du ClusterIssuer self-signed..."
    kubectl apply -f base/cert-managers/self-signed-issuer.yaml
fi

echo -e "${GREEN}✓ cert-manager configuré${NC}"

# Configuration du port-forward
echo ""
echo -e "${YELLOW}🔌 Configuration du port-forward...${NC}"

# Arrêter les port-forwards existants
PORT_FORWARD_PIDS=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)
if [ -n "$PORT_FORWARD_PIDS" ]; then
    echo "   Arrêt des port-forwards existants..."
    echo "$PORT_FORWARD_PIDS" | xargs kill 2>/dev/null || true
    sleep 2
fi

# Créer le répertoire de logs
LOG_DIR="/tmp/k8s-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/port-forward.log"
PID_FILE="$LOG_DIR/port-forward.pid"
PORTS_FILE="$LOG_DIR/port-forward.ports"

# Déterminer les ports à utiliser
echo ""
echo -e "${YELLOW}🔌 Détermination des ports...${NC}"

if [ "$EUID" -eq 0 ]; then
    # Avec sudo : ports privilégiés par défaut
    DEFAULT_HTTP_PORT=80
    DEFAULT_HTTPS_PORT=$HTTPS_SERVICE_PORT
else
    # Sans sudo : ports non privilégiés par défaut
    DEFAULT_HTTP_PORT=8080
    DEFAULT_HTTPS_PORT=$HTTPS_SERVICE_PORT
fi

# Utiliser les ports spécifiés ou les valeurs par défaut
if [ -n "$HTTP_PORT" ]; then
    LOCAL_HTTP_PORT="$HTTP_PORT"
else
    LOCAL_HTTP_PORT="$DEFAULT_HTTP_PORT"
fi

if [ -n "$HTTPS_PORT" ]; then
    LOCAL_HTTPS_PORT="$HTTPS_PORT"
else
    LOCAL_HTTPS_PORT="$DEFAULT_HTTPS_PORT"
fi

# Vérifier si les ports sont disponibles
HTTP_PORT_AVAILABLE=true
HTTPS_PORT_AVAILABLE=true

if ! is_port_available "$LOCAL_HTTP_PORT"; then
    HTTP_PORT_AVAILABLE=false
    echo -e "${YELLOW}⚠ Port HTTP $LOCAL_HTTP_PORT est déjà utilisé${NC}"
    
    if [ -z "$HTTP_PORT" ]; then
        # Port non spécifié, chercher un port alternatif
        echo "   Recherche d'un port HTTP alternatif..."
        ALTERNATIVE_HTTP=$(find_available_port $((LOCAL_HTTP_PORT + 1)))
        if [ -n "$ALTERNATIVE_HTTP" ]; then
            LOCAL_HTTP_PORT="$ALTERNATIVE_HTTP"
            echo -e "${GREEN}✓ Port HTTP $LOCAL_HTTP_PORT disponible${NC}"
            HTTP_PORT_AVAILABLE=true
        else
            echo -e "${RED}❌ Impossible de trouver un port HTTP disponible${NC}"
        fi
    else
        echo -e "${RED}❌ Le port HTTP $LOCAL_HTTP_PORT spécifié est déjà utilisé${NC}"
        echo "   Spécifiez un autre port avec --http-port ou la variable K8S_HTTP_PORT"
    fi
else
    echo -e "${GREEN}✓ Port HTTP $LOCAL_HTTP_PORT disponible${NC}"
fi

if ! is_port_available "$LOCAL_HTTPS_PORT"; then
    HTTPS_PORT_AVAILABLE=false
    echo -e "${YELLOW}⚠ Port HTTPS $LOCAL_HTTPS_PORT est déjà utilisé${NC}"
    
    if [ -z "$HTTPS_PORT" ]; then
        # Port non spécifié, chercher un port alternatif
        echo "   Recherche d'un port HTTPS alternatif..."
        ALTERNATIVE_HTTPS=$(find_available_port $((LOCAL_HTTPS_PORT + 1)))
        if [ -n "$ALTERNATIVE_HTTPS" ]; then
            LOCAL_HTTPS_PORT="$ALTERNATIVE_HTTPS"
            echo -e "${GREEN}✓ Port HTTPS $LOCAL_HTTPS_PORT disponible${NC}"
            HTTPS_PORT_AVAILABLE=true
        else
            echo -e "${RED}❌ Impossible de trouver un port HTTPS disponible${NC}"
        fi
    else
        echo -e "${RED}❌ Le port HTTPS $LOCAL_HTTPS_PORT spécifié est déjà utilisé${NC}"
        echo "   Spécifiez un autre port avec --https-port ou la variable K8S_HTTPS_PORT"
    fi
else
    echo -e "${GREEN}✓ Port HTTPS $LOCAL_HTTPS_PORT disponible${NC}"
fi

# Vérifier les permissions pour les ports privilégiés
if [ "$NETWORK_MODE" = true ]; then
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ Ce script doit être exécuté avec sudo pour le mode réseau${NC}"
        echo "   Utilisez : sudo ./scripts/local/setup-access.sh --network"
        exit 1
    fi
fi

# Vérifier que les ports sont disponibles avant de continuer
if [ "$HTTP_PORT_AVAILABLE" != "true" ] || [ "$HTTPS_PORT_AVAILABLE" != "true" ]; then
    echo ""
    echo -e "${RED}❌ Impossible de continuer : ports non disponibles${NC}"
    echo "   HTTP: $LOCAL_HTTP_PORT (disponible: $HTTP_PORT_AVAILABLE)"
    echo "   HTTPS: $LOCAL_HTTPS_PORT (disponible: $HTTPS_PORT_AVAILABLE)"
    echo ""
    echo "   Solutions :"
    echo "   1. Libérez les ports utilisés"
    echo "   2. Spécifiez d'autres ports : $0 --http-port <PORT> --https-port <PORT>"
    echo "   3. Utilisez des variables d'environnement : K8S_HTTP_PORT=<PORT> K8S_HTTPS_PORT=<PORT> $0"
    exit 1
fi

# Démarrer le port-forward
echo ""
echo -e "${YELLOW}🚀 Démarrage du port-forward sur $BIND_ADDRESS...${NC}"
echo "   Ports: HTTP=$LOCAL_HTTP_PORT, HTTPS=$LOCAL_HTTPS_PORT"

kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller \
    --address "$BIND_ADDRESS" $LOCAL_HTTP_PORT:80 $LOCAL_HTTPS_PORT:$HTTPS_SERVICE_PORT > "$LOG_FILE" 2>&1 &
PORT_FORWARD_PID=$!

echo "$PORT_FORWARD_PID" > "$PID_FILE"
# Sauvegarder les ports utilisés
echo "HTTP_PORT=$LOCAL_HTTP_PORT" > "$PORTS_FILE"
echo "HTTPS_PORT=$LOCAL_HTTPS_PORT" >> "$PORTS_FILE"
echo "BIND_ADDRESS=$BIND_ADDRESS" >> "$PORTS_FILE"
sleep 3

# Vérifier que le port-forward est actif
if ps -p $PORT_FORWARD_PID > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Port-forward actif (PID: $PORT_FORWARD_PID)${NC}"
    echo "   HTTP : $BIND_ADDRESS:$LOCAL_HTTP_PORT"
    echo "   HTTPS: $BIND_ADDRESS:$LOCAL_HTTPS_PORT"
else
    echo -e "${RED}❌ Échec du démarrage du port-forward${NC}"
    if [ -f "$LOG_FILE" ]; then
        echo "   Dernières lignes du log :"
        tail -5 "$LOG_FILE" | sed 's/^/   /'
    fi
    exit 1
fi

# Vérification des certificats
echo ""
echo -e "${YELLOW}🔐 Vérification des certificats SSL...${NC}"

for i in {1..30}; do
    if kubectl get certificate apps-tls-local-cert &>/dev/null; then
        CERT_STATUS=$(kubectl get certificate apps-tls-local-cert -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$CERT_STATUS" == "True" ]; then
            echo -e "${GREEN}✓ Certificats SSL générés${NC}"
            break
        fi
    fi
    if [ $i -eq 30 ]; then
        echo -e "${YELLOW}⚠ Certificats en cours de génération...${NC}"
    else
        sleep 2
    fi
done

# Test de connectivité
echo ""
echo -e "${YELLOW}🧪 Test de connectivité...${NC}"
sleep 2

TEST_HOST="baserow.$DOMAIN_SUFFIX"
# Toujours inclure le port dans l'URL de test si ce n'est pas le port standard
if [ "$LOCAL_HTTPS_PORT" != "443" ]; then
    TEST_URL="https://$TEST_HOST:$LOCAL_HTTPS_PORT"
else
    TEST_URL="https://$TEST_HOST"
fi

if curl -s -k -o /dev/null -w "%{http_code}" "$TEST_URL" 2>/dev/null | grep -qE "200|301|302|404"; then
    echo -e "${GREEN}✓ Services accessibles${NC}"
else
    echo -e "${YELLOW}⚠ Test de connectivité non concluant (normal si les pods ne sont pas encore prêts)${NC}"
fi

# Résumé
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         CONFIGURATION TERMINÉE AVEC SUCCÈS                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$NETWORK_MODE" = true ]; then
    echo "🌐 Mode : RÉSEAU"
    echo "   IP du serveur : $MAC_IP"
else
    echo "🏠 Mode : LOCAL"
fi

echo ""
echo "📦 Services disponibles :"
# Afficher les URLs avec le port si ce n'est pas le port standard HTTPS
if [ "$LOCAL_HTTPS_PORT" != "443" ]; then
    echo "   • https://baserow.$DOMAIN_SUFFIX:$LOCAL_HTTPS_PORT"
    echo "   • https://n8n.$DOMAIN_SUFFIX:$LOCAL_HTTPS_PORT"
    echo "   • https://excalidraw.$DOMAIN_SUFFIX:$LOCAL_HTTPS_PORT"
    echo "   • https://metabase.$DOMAIN_SUFFIX:$LOCAL_HTTPS_PORT"
    echo "   • https://supabase.$DOMAIN_SUFFIX:$LOCAL_HTTPS_PORT"
else
    echo "   • https://baserow.$DOMAIN_SUFFIX"
    echo "   • https://n8n.$DOMAIN_SUFFIX"
    echo "   • https://excalidraw.$DOMAIN_SUFFIX"
    echo "   • https://metabase.$DOMAIN_SUFFIX"
    echo "   • https://supabase.$DOMAIN_SUFFIX"
fi

# Afficher les ports utilisés
echo ""
echo "🔌 Ports utilisés :"
echo "   • HTTP : $LOCAL_HTTP_PORT"
echo "   • HTTPS: $LOCAL_HTTPS_PORT"

if [ "$NETWORK_MODE" = true ]; then
    echo ""
    echo "📝 Configuration des autres appareils :"
    echo "   Configurez le DNS vers : $MAC_IP"
    echo "   Voir README-NETWORK.md pour plus de détails"
fi

echo ""
echo "🔧 Commandes utiles :"
echo "   • Arrêter : ./scripts/local/stop-access.sh"
echo "   • Logs : tail -f $LOG_FILE"
echo "   • État : kubectl get pods"
echo ""
echo "🔐 Note : Les certificats sont auto-signés (avertissement navigateur normal)"
echo ""
