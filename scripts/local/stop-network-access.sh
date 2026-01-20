#!/bin/bash
# scripts/local/stop-network-access.sh
# Script pour arrêter l'accès réseau local

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}🛑 Arrêt de l'accès réseau local...${NC}"
echo ""

# Arrêter le port-forward
if [ -f /tmp/k8s-port-forward-network.pid ]; then
    PID=$(cat /tmp/k8s-port-forward-network.pid)
    if ps -p $PID > /dev/null 2>&1; then
        echo "   Arrêt du port-forward (PID: $PID)..."
        kill $PID 2>/dev/null || true
        rm /tmp/k8s-port-forward-network.pid
        echo -e "${GREEN}✓ Port-forward arrêté${NC}"
    else
        echo -e "${YELLOW}⚠ Port-forward déjà arrêté${NC}"
        rm /tmp/k8s-port-forward-network.pid
    fi
else
    # Essayer de trouver et arrêter le port-forward manuellement
    PORT_FORWARD_PID=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)
    if [ -n "$PORT_FORWARD_PID" ]; then
        echo "   Arrêt du port-forward (PID: $PORT_FORWARD_PID)..."
        kill $PORT_FORWARD_PID 2>/dev/null || true
        echo -e "${GREEN}✓ Port-forward arrêté${NC}"
    else
        echo -e "${YELLOW}⚠ Aucun port-forward actif${NC}"
    fi
fi

# Arrêter dnsmasq (optionnel)
read -p "Arrêter dnsmasq aussi? (o/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]; then
    if command -v brew >/dev/null 2>&1; then
        if sudo brew services list | grep -q "dnsmasq.*started"; then
            echo "   Arrêt de dnsmasq..."
            sudo brew services stop dnsmasq
            echo -e "${GREEN}✓ dnsmasq arrêté${NC}"
        else
            echo -e "${YELLOW}⚠ dnsmasq n'est pas démarré${NC}"
        fi
    fi
fi

echo ""
echo -e "${GREEN}✅ Arrêt terminé${NC}"

