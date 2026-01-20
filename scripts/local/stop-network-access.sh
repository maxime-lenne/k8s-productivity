#!/bin/bash

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🛑 Arrêt de l'accès réseau aux services Kubernetes${NC}"
echo ""

LOG_DIR="/tmp/k8s-logs"
PID_FILE="$LOG_DIR/network-port-forward.pid"

# Arrêter le port-forward réseau
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null 2>&1; then
        echo "   Arrêt du port-forward (PID: $PID)..."
        kill $PID 2>/dev/null || sudo kill $PID 2>/dev/null || true
        rm -f "$PID_FILE"
        echo -e "${GREEN}✓ Port-forward arrêté${NC}"
    else
        echo -e "${YELLOW}⚠ Port-forward déjà arrêté${NC}"
        rm -f "$PID_FILE"
    fi
else
    # Essayer de trouver et tuer tous les port-forwards
    PORT_FORWARD_PIDS=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)

    if [ -n "$PORT_FORWARD_PIDS" ]; then
        echo "   Arrêt des port-forwards existants..."
        echo "$PORT_FORWARD_PIDS" | xargs kill 2>/dev/null || true
        echo -e "${GREEN}✓ Port-forward(s) arrêté(s)${NC}"
    else
        echo -e "${YELLOW}⚠ Aucun port-forward actif trouvé${NC}"
    fi
fi

echo ""
echo -e "${GREEN}✓ Service réseau arrêté${NC}"
echo ""
echo "📝 Note :"
echo "   • dnsmasq continue de fonctionner en arrière-plan"
echo "   • Pour arrêter dnsmasq : sudo brew services stop dnsmasq"
echo "   • Pour redémarrer l'accès réseau : sudo ./scripts/local/setup-network-access.sh"
echo ""
