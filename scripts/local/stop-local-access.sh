#!/bin/bash

# Script pour arrêter le port-forward et nettoyer

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🛑 Arrêt du port-forward...${NC}"

# Trouver et arrêter le port-forward
PORT_FORWARD_PID=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)

if [ -n "$PORT_FORWARD_PID" ]; then
    kill $PORT_FORWARD_PID
    echo -e "${GREEN}✓ Port-forward arrêté (PID: $PORT_FORWARD_PID)${NC}"
else
    echo "   Aucun port-forward actif"
fi

echo ""
echo "Note : Les entrées dans /etc/hosts ne sont pas supprimées automatiquement."
echo "       Pour les supprimer, éditez /etc/hosts manuellement."

