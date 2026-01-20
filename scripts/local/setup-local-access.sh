#!/bin/bash

set -e

# Couleurs pour les messages
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Configuration automatique de l'accès local aux services Kubernetes${NC}"
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

# 1. Configuration de /etc/hosts
echo ""
echo -e "${YELLOW}📝 Configuration de /etc/hosts...${NC}"

# Vérifier si les entrées existent déjà avec la bonne IP (127.0.0.1)
HOSTS_CORRECT=$(grep -E "127\.0\.0\.1.*(baserow|n8n|excalidraw|metabase|supabase)\.local" /etc/hosts 2>/dev/null || true)

if [ -n "$HOSTS_CORRECT" ]; then
    # Vérifier s'il y a aussi des entrées incorrectes (255.255.255.255 ou autres IP)
    HOSTS_INCORRECT=$(grep -E "(255\.255\.255\.255|^[^#].*[^127\.0\.0\.1].*\.local)" /etc/hosts 2>/dev/null | grep -E "(baserow|n8n|excalidraw|metabase|supabase)\.local" || true)
    
    if [ -n "$HOSTS_INCORRECT" ]; then
        echo "   Nettoyage des anciennes entrées incorrectes dans /etc/hosts..."
        # Supprimer toutes les entrées .local (y compris celles avec 255.255.255.255)
        sudo sed -i '' '/baserow\.local\|n8n\.local\|excalidraw\.local\|metabase\.local\|supabase\.local/d' /etc/hosts
        # Ajouter les entrées correctes
        echo "127.0.0.1 baserow.local n8n.local excalidraw.local metabase.local supabase.local" | sudo tee -a /etc/hosts > /dev/null
        echo -e "${GREEN}✓ /etc/hosts corrigé${NC}"
    else
        echo -e "${GREEN}✓ /etc/hosts déjà configuré correctement${NC}"
    fi
else
    echo "   Nettoyage des anciennes entrées dans /etc/hosts..."
    # Supprimer toutes les entrées .local existantes (y compris celles avec 255.255.255.255)
    sudo sed -i '' '/baserow\.local\|n8n\.local\|excalidraw\.local\|metabase\.local\|supabase\.local/d' /etc/hosts
    
    echo "   Ajout des entrées dans /etc/hosts (nécessite votre mot de passe)..."
    if echo "127.0.0.1 baserow.local n8n.local excalidraw.local metabase.local supabase.local" | sudo tee -a /etc/hosts > /dev/null; then
        echo -e "${GREEN}✓ /etc/hosts configuré${NC}"
    else
        echo -e "${RED}❌ Impossible de modifier /etc/hosts${NC}"
        exit 1
    fi
fi

# 2. Vérifier que l'Ingress Controller est installé
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

# 3. Vérifier que cert-manager est installé
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

# 4. Vérifier que le port-forward n'est pas déjà actif
echo ""
echo -e "${YELLOW}🔌 Configuration du port-forward...${NC}"

PORT_FORWARD_PID=$(pgrep -f "kubectl port-forward.*ingress-nginx-controller" || true)

# Variables pour les ports (initialisées par défaut)
LOCAL_HTTP_PORT=""
LOCAL_HTTPS_PORT=""

# Vérifier si les ports 80/443 sont disponibles (nécessitent root)
# Si le script est exécuté avec sudo, on peut utiliser les ports privilégiés
CAN_USE_PRIVILEGED_PORTS=false
if [ "$EUID" -eq 0 ]; then
    CAN_USE_PRIVILEGED_PORTS=true
fi

if [ -n "$PORT_FORWARD_PID" ]; then
    echo -e "${GREEN}✓ Port-forward déjà actif (PID: $PORT_FORWARD_PID)${NC}"
    # Détecter les ports utilisés
    LOCAL_PORT=$(ps -p $PORT_FORWARD_PID -o args= | grep -oE '[0-9]+:[0-9]+' | head -1 | cut -d: -f1 || echo "80")
    if [ "$LOCAL_PORT" != "80" ] && [ "$LOCAL_PORT" != "8080" ]; then
        echo -e "${YELLOW}   Port local détecté: $LOCAL_PORT${NC}"
    fi
else
    # Créer un fichier de log pour le port-forward
    LOG_FILE="/tmp/k8s-port-forward.log"
    
    if [ "$CAN_USE_PRIVILEGED_PORTS" = true ]; then
        echo "   Démarrage du port-forward sur les ports 80 et 443 (nécessite sudo)..."
        # Essayer avec les ports privilégiés
        sudo kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 443:443 > "$LOG_FILE" 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 2
        if ps -p $PORT_FORWARD_PID > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Port-forward démarré sur ports 80/443 (PID: $PORT_FORWARD_PID)${NC}"
            echo "   Logs disponibles dans: $LOG_FILE"
        else
            echo -e "${YELLOW}⚠ Échec avec ports privilégiés, utilisation de ports alternatifs...${NC}"
            CAN_USE_PRIVILEGED_PORTS=false
        fi
    fi
    
    if [ "$CAN_USE_PRIVILEGED_PORTS" = false ]; then
        # Utiliser des ports non privilégiés
        LOCAL_HTTP_PORT=8080
        LOCAL_HTTPS_PORT=8443
        echo "   Démarrage du port-forward sur ports $LOCAL_HTTP_PORT/$LOCAL_HTTPS_PORT (non privilégiés)..."
        echo -e "${YELLOW}   Note: Vous devrez utiliser http://excalidraw.local:$LOCAL_HTTP_PORT ou configurer un proxy${NC}"
        
        kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller $LOCAL_HTTP_PORT:80 $LOCAL_HTTPS_PORT:443 > "$LOG_FILE" 2>&1 &
        PORT_FORWARD_PID=$!
        
        sleep 2
        
        if ps -p $PORT_FORWARD_PID > /dev/null; then
            echo -e "${GREEN}✓ Port-forward démarré sur ports $LOCAL_HTTP_PORT/$LOCAL_HTTPS_PORT (PID: $PORT_FORWARD_PID)${NC}"
            echo "   Logs disponibles dans: $LOG_FILE"
            echo ""
            echo -e "${YELLOW}⚠ IMPORTANT: Utilisez les ports suivants :${NC}"
            echo "   • http://excalidraw.local:$LOCAL_HTTP_PORT"
            echo "   • https://excalidraw.local:$LOCAL_HTTPS_PORT"
        else
            echo -e "${RED}❌ Échec du démarrage du port-forward${NC}"
            echo "   Vérifiez les logs: $LOG_FILE"
            if [ -f "$LOG_FILE" ]; then
                echo ""
                echo "   Dernières lignes du log :"
                tail -5 "$LOG_FILE" | sed 's/^/   /'
            fi
            exit 1
        fi
    fi
fi

# 5. Vérifier que les certificats sont générés
echo ""
echo -e "${YELLOW}🔐 Vérification des certificats SSL...${NC}"

# Attendre que les certificats soient générés (peut prendre quelques secondes)
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

# 6. Test de connectivité
echo ""
echo -e "${YELLOW}🧪 Test de connectivité...${NC}"

sleep 2

# Détecter le port utilisé
if [ -n "$LOCAL_HTTPS_PORT" ]; then
    TEST_URL="https://excalidraw.local:$LOCAL_HTTPS_PORT"
    TEST_HTTP_URL="http://excalidraw.local:$LOCAL_HTTP_PORT"
else
    TEST_URL="https://excalidraw.local"
    TEST_HTTP_URL="http://excalidraw.local"
fi

if curl -s -k -o /dev/null -w "%{http_code}" "$TEST_URL" >/dev/null 2>&1; then
    HTTP_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" "$TEST_URL")
    if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
        echo -e "${GREEN}✓ Services accessibles via HTTPS${NC}"
    else
        echo -e "${YELLOW}⚠ Services accessibles mais code HTTP: $HTTP_CODE${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Impossible de tester la connectivité (normal si les pods ne sont pas encore prêts)${NC}"
fi

# Résumé
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         CONFIGURATION TERMINÉE AVEC SUCCÈS                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "📦 Services disponibles :"
if [ -n "$LOCAL_HTTPS_PORT" ]; then
    echo "   • https://excalidraw.local:$LOCAL_HTTPS_PORT"
    echo "   • https://baserow.local:$LOCAL_HTTPS_PORT"
    echo "   • https://n8n.local:$LOCAL_HTTPS_PORT"
    echo "   • https://metabase.local:$LOCAL_HTTPS_PORT"
    echo "   • https://supabase.local:$LOCAL_HTTPS_PORT"
    echo ""
    echo -e "${YELLOW}⚠ Note: Ports non privilégiés utilisés ($LOCAL_HTTP_PORT/$LOCAL_HTTPS_PORT)${NC}"
    echo "   Pour utiliser les ports 80/443, exécutez le script avec sudo :"
    echo "   sudo ./scripts/local/setup-local-access.sh"
else
    echo "   • https://excalidraw.local"
    echo "   • https://baserow.local"
    echo "   • https://n8n.local"
    echo "   • https://metabase.local"
    echo "   • https://supabase.local"
fi
echo ""
echo "📝 Notes importantes :"
echo "   • Le port-forward tourne en arrière-plan (PID: $PORT_FORWARD_PID)"
echo "   • Pour arrêter le port-forward : ./scripts/local/stop-local-access.sh"
echo "   • Les certificats SSL sont auto-signés (avertissement dans le navigateur normal)"
echo "   • Pour accepter les certificats, cliquez sur 'Avancé' puis 'Continuer'"
echo ""
echo "🔍 Vérifier l'état :"
echo "   kubectl get pods"
echo "   kubectl get ingress"
echo "   kubectl get certificate"
echo ""

