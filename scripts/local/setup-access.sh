#!/bin/bash
# scripts/local/setup-access.sh
# Script unifié pour configurer l'accès aux services Kubernetes
# Usage: ./setup-access.sh [OPTIONS]
#   --network, -n              Configure l'accès réseau (dnsmasq au lieu de /etc/hosts)
#   --help, -h                 Affiche cette aide
#
# Les services sont exposés par le load balancer de Docker Desktop (Service
# ingress-nginx-controller de type LoadBalancer) : HTTP sur 80, HTTPS sur 444
# (443 est déjà utilisé sur la machine). Aucun port-forward n'est nécessaire.
#
# Sans option, la résolution DNS des domaines *.white-wood.local se fait via /etc/hosts

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Mode par défaut : local
NETWORK_MODE=false

# Ports exposés par le Service ingress-nginx-controller (et donc publiés sur la
# machine par le load balancer de Docker Desktop). 443 étant déjà utilisé sur la
# machine, tout le cluster local passe par 444 : https://<app>.white-wood.local:444
HTTP_SERVICE_PORT=80
HTTPS_SERVICE_PORT=444

# Parser les arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --network|-n)
            NETWORK_MODE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --network, -n              Configure l'accès réseau (dnsmasq, accessible depuis d'autres appareils)"
            echo "  --help, -h                 Affiche cette aide"
            echo ""
            echo "Les services sont exposés par le load balancer de Docker Desktop :"
            echo "  HTTP  : $HTTP_SERVICE_PORT"
            echo "  HTTPS : $HTTPS_SERVICE_PORT (le 443 est déjà utilisé sur la machine)"
            echo ""
            echo "Sans option, la résolution DNS se fait via /etc/hosts (cette machine uniquement)"
            echo ""
            echo "Exemples:"
            echo "  $0                  # Mode local (/etc/hosts)"
            echo "  sudo $0 --network   # Mode réseau (dnsmasq)"
            exit 0
            ;;
        *)
            echo "Option inconnue: $1"
            echo "Utilisez --help pour voir les options disponibles"
            exit 1
            ;;
    esac
done

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
    echo -e "${BLUE}   Mode: Résolution DNS via /etc/hosts (cette machine)${NC}"
fi
echo ""

# Le mode réseau pilote dnsmasq (brew services) et nécessite les droits root
if [ "$NETWORK_MODE" = true ] && [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ce script doit être exécuté avec sudo pour le mode réseau${NC}"
    echo "   Utilisez : sudo ./scripts/local/setup-access.sh --network"
    exit 1
fi

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

# Exposition via le load balancer de Docker Desktop
echo ""
echo -e "${YELLOW}🔌 Vérification de l'exposition du cluster...${NC}"

# Docker Desktop (kind) publie directement les ports du Service LoadBalancer
# ingress-nginx-controller sur la machine : aucun port-forward n'est nécessaire.
LB_IP=""
for i in {1..30}; do
    LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$LB_IP" ] && break
    sleep 2
done

if [ -z "$LB_IP" ]; then
    echo -e "${RED}❌ Le Service ingress-nginx-controller n'a pas d'IP de load balancer${NC}"
    echo "   Vérifiez que Kubernetes (kind) est activé dans Docker Desktop et que le"
    echo "   load balancer tourne : docker ps | grep kindccm"
    exit 1
fi
echo -e "${GREEN}✓ Load balancer actif ($LB_IP)${NC}"

HTTPS_READY=false
for i in {1..30}; do
    if curl -sk -o /dev/null -m 3 "https://127.0.0.1:$HTTPS_SERVICE_PORT/" 2>/dev/null; then
        HTTPS_READY=true
        break
    fi
    sleep 2
done

if [ "$HTTPS_READY" != "true" ]; then
    echo -e "${RED}❌ Le port HTTPS $HTTPS_SERVICE_PORT ne répond pas sur cette machine${NC}"
    echo "   Le load balancer Docker publie peut-être encore l'ancien port :"
    docker ps --format '   {{.Names}} {{.Ports}}' 2>/dev/null | grep kindccm || true
    echo "   Voir docs/local-deployment.md (« Pourquoi 444 ? »)"
    exit 1
fi
echo -e "${GREEN}✓ HTTP : $HTTP_SERVICE_PORT, HTTPS : $HTTPS_SERVICE_PORT${NC}"

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

TEST_URL="https://baserow.$DOMAIN_SUFFIX:$HTTPS_SERVICE_PORT"

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
echo "   • https://baserow.$DOMAIN_SUFFIX:$HTTPS_SERVICE_PORT"
echo "   • https://n8n.$DOMAIN_SUFFIX:$HTTPS_SERVICE_PORT"
echo "   • https://excalidraw.$DOMAIN_SUFFIX:$HTTPS_SERVICE_PORT"
echo "   • https://metabase.$DOMAIN_SUFFIX:$HTTPS_SERVICE_PORT"
echo "   • https://supabase.$DOMAIN_SUFFIX:$HTTPS_SERVICE_PORT"

echo ""
echo "🔌 Ports exposés par le load balancer Docker Desktop :"
echo "   • HTTP : $HTTP_SERVICE_PORT"
echo "   • HTTPS: $HTTPS_SERVICE_PORT"

if [ "$NETWORK_MODE" = true ]; then
    echo ""
    echo "📝 Configuration des autres appareils :"
    echo "   Configurez le DNS vers : $MAC_IP"
    echo "   Voir README-NETWORK.md pour plus de détails"
fi

echo ""
echo "🔧 Commandes utiles :"
echo "   • État : kubectl get pods"
echo "   • Load balancer : docker ps | grep kindccm"
echo ""
echo "🔐 Note : Les certificats sont auto-signés (avertissement navigateur normal)"
echo ""
