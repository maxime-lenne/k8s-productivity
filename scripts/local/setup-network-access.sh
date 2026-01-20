#!/bin/bash

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Configuration de l'accès réseau local aux services Kubernetes${NC}"
echo ""

# Fonction pour vérifier si une commande existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

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

# Vérifier que dnsmasq est installé et en cours d'exécution
echo ""
echo -e "${YELLOW}🌐 Vérification de dnsmasq...${NC}"

if ! command_exists dnsmasq; then
    echo -e "${RED}❌ dnsmasq n'est pas installé${NC}"
    echo "   Exécutez d'abord : ./scripts/local/install-dnsmasq.sh"
    exit 1
fi

if ! brew services list | grep dnsmasq | grep started >/dev/null; then
    echo -e "${YELLOW}⚠ dnsmasq n'est pas démarré${NC}"
    echo "   Démarrage de dnsmasq..."
    sudo brew services start dnsmasq
    sleep 2
fi

echo -e "${GREEN}✓ dnsmasq est actif${NC}"

# Détecter l'IP locale du Mac Mini
echo ""
echo -e "${YELLOW}🔍 Détection de l'IP locale...${NC}"

MAC_IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -1)

if [ -z "$MAC_IP" ]; then
    echo -e "${RED}❌ Impossible de détecter l'IP locale${NC}"
    exit 1
fi

echo -e "${GREEN}✓ IP locale détectée : $MAC_IP${NC}"

# Vérifier que l'Ingress Controller est installé
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

echo -e "${GREEN}✓ Ingress Controller prêt${NC}"

# Vérifier que cert-manager est installé
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

# Vérifier que le ClusterIssuer self-signed existe
if ! kubectl get clusterissuer selfsigned-issuer &>/dev/null; then
    echo "   Création du ClusterIssuer self-signed..."
    kubectl apply -f base/cert-managers/self-signed-issuer.yaml
fi

echo -e "${GREEN}✓ cert-manager configuré${NC}"

# Configuration du port-forward pour l'accès réseau
echo ""
echo -e "${YELLOW}🔌 Configuration du port-forward réseau...${NC}"

# Arrêter les port-forwards existants
PORT_FORWARD_PIDS=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)

if [ -n "$PORT_FORWARD_PIDS" ]; then
    echo "   Arrêt des port-forwards existants..."
    echo "$PORT_FORWARD_PIDS" | xargs kill 2>/dev/null || true
    sleep 2
fi

# Créer un fichier de log pour le port-forward
LOG_DIR="/tmp/k8s-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/network-port-forward.log"

# Port-forward HTTP (80) et HTTPS (443) sur toutes les interfaces
echo "   Démarrage du port-forward HTTP/HTTPS sur $MAC_IP..."
echo -e "${YELLOW}   Note: Ce script doit être exécuté avec sudo pour utiliser les ports 80/443${NC}"

# Vérifier si on a les permissions sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Ce script doit être exécuté avec sudo${NC}"
    echo "   Utilisez : sudo ./scripts/local/setup-network-access.sh"
    exit 1
fi

# Port-forward avec --address pour écouter sur l'IP locale (accessible depuis le réseau)
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller \
    --address 0.0.0.0 \
    80:80 443:443 > "$LOG_FILE" 2>&1 &

PORT_FORWARD_PID=$!

# Sauvegarder le PID pour pouvoir l'arrêter plus tard
echo "$PORT_FORWARD_PID" > "$LOG_DIR/network-port-forward.pid"

# Attendre que le port-forward soit prêt
sleep 3

# Vérifier que le port-forward est actif
if ps -p $PORT_FORWARD_PID > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Port-forward actif sur toutes les interfaces (PID: $PORT_FORWARD_PID)${NC}"
    echo "   HTTP : $MAC_IP:80"
    echo "   HTTPS: $MAC_IP:443"
    echo "   Logs : $LOG_FILE"
else
    echo -e "${RED}❌ Échec du démarrage du port-forward${NC}"
    echo "   Vérifiez les logs : $LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        echo ""
        echo "   Dernières lignes du log :"
        tail -10 "$LOG_FILE" | sed 's/^/   /'
    fi
    exit 1
fi

# Vérifier que les certificats sont générés
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
        echo -e "${YELLOW}⚠ Certificats en cours de génération (cela peut prendre quelques minutes)${NC}"
    else
        sleep 2
    fi
done

# Test de connectivité
echo ""
echo -e "${YELLOW}🧪 Test de connectivité...${NC}"

sleep 2

# Test local
if curl -s -k -o /dev/null -w "%{http_code}" "https://baserow.white-wood.local" >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" "https://baserow.white-wood.local")
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
        echo -e "${GREEN}✓ Services accessibles localement${NC}"
    else
        echo -e "${YELLOW}⚠ Services accessibles mais code HTTP: $HTTP_CODE${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Impossible de tester la connectivité (normal si les pods ne sont pas encore prêts)${NC}"
fi

# Vérifier que le port 80 est bien accessible depuis le réseau
echo ""
echo -e "${YELLOW}🌐 Vérification de l'accès réseau...${NC}"

if nc -z -w 2 $MAC_IP 80 2>/dev/null; then
    echo -e "${GREEN}✓ Port 80 accessible depuis le réseau${NC}"
else
    echo -e "${YELLOW}⚠ Port 80 non accessible (vérifiez le pare-feu)${NC}"
fi

if nc -z -w 2 $MAC_IP 443 2>/dev/null; then
    echo -e "${GREEN}✓ Port 443 accessible depuis le réseau${NC}"
else
    echo -e "${YELLOW}⚠ Port 443 non accessible (vérifiez le pare-feu)${NC}"
fi

# Résumé
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         CONFIGURATION RÉSEAU TERMINÉE                       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "🌐 Accès réseau :"
echo "   • IP du Mac Mini : $MAC_IP"
echo "   • Domaine : *.white-wood.local"
echo ""
echo "📦 Services disponibles depuis n'importe quel appareil du réseau :"
echo "   • https://baserow.white-wood.local"
echo "   • https://n8n.white-wood.local"
echo "   • https://excalidraw.white-wood.local"
echo "   • https://metabase.white-wood.local"
echo "   • https://supabase.white-wood.local"
echo ""
echo "📝 Configuration des autres appareils :"
echo "   • iOS/Android : Paramètres WiFi > Serveur DNS > $MAC_IP"
echo "   • macOS : Préférences Système > Réseau > Avancé > DNS > $MAC_IP"
echo "   • Windows : Panneau de configuration > Réseau > Propriétés IPv4 > DNS > $MAC_IP"
echo "   • Linux : /etc/resolv.conf > nameserver $MAC_IP"
echo ""
echo "   Voir README-NETWORK.md pour plus de détails"
echo ""
echo "🔧 Gestion du service :"
echo "   • Arrêter : ./scripts/local/stop-network-access.sh"
echo "   • Logs : tail -f $LOG_FILE"
echo "   • PID : $PORT_FORWARD_PID"
echo ""
echo "🔐 Certificats SSL :"
echo "   • Les certificats sont auto-signés"
echo "   • Acceptez l'avertissement dans le navigateur"
echo ""
echo "🔍 Vérifier l'état :"
echo "   kubectl get pods"
echo "   kubectl get ingress"
echo "   kubectl get certificate"
echo ""
