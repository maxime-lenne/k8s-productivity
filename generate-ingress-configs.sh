#!/bin/bash

# Usage: ./generate-ingress-configs.sh [local|staging|prod]
ENVIRONMENT=${1:-local}
ENV_FILE=".env.$ENVIRONMENT"
TARGET_DIR="environments/$ENVIRONMENT"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: $ENV_FILE file not found"
    echo "Veuillez copier .env.example en $ENV_FILE et adapter les valeurs."
    exit 1
fi

# Créer le dossier cible si besoin
mkdir -p "$TARGET_DIR"

# Load environment variables
set -a
source "$ENV_FILE"
set +a

# Generate ingress configuration for the specified environment
if [ "$ENVIRONMENT" == "local" ]; then
cat > "$TARGET_DIR/apps-ingress-local.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps-ingress-local
  annotations:
    cert-manager.io/cluster-issuer: ${CERT_MANAGER_LOCAL_ISSUER}
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
  - host: ${BASEROW_LOCAL_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: baserow
            port:
              number: 80
  - host: ${N8N_LOCAL_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 80
  tls:
  - hosts:
    - ${BASEROW_LOCAL_DOMAIN}
    - ${N8N_LOCAL_DOMAIN}
    secretName: apps-tls-local-cert
EOF
echo "Fichier d'ingress pour l'environnement local généré dans $TARGET_DIR/apps-ingress-local.yaml"

elif [ "$ENVIRONMENT" == "staging" ]; then
cat > "$TARGET_DIR/apps-ingress-staging.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps-ingress-staging
  annotations:
    cert-manager.io/cluster-issuer: ${CERT_MANAGER_STAGING_ISSUER}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
  - host: ${BASEROW_STAGING_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: baserow
            port:
              number: 80
  - host: ${N8N_STAGING_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 80
  tls:
  - hosts:
    - ${BASEROW_STAGING_DOMAIN}
    - ${N8N_STAGING_DOMAIN}
    secretName: apps-tls-staging-cert
EOF
echo "Fichier d'ingress pour l'environnement staging généré dans $TARGET_DIR/apps-ingress-staging.yaml"

elif [ "$ENVIRONMENT" == "prod" ]; then
cat > "$TARGET_DIR/apps-ingress-prod.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: apps-ingress
  annotations:
    cert-manager.io/cluster-issuer: ${CERT_MANAGER_PROD_ISSUER}
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: ${INGRESS_CLASS}
  rules:
  - host: ${BASEROW_PROD_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: baserow
            port:
              number: 80
  - host: ${N8N_PROD_DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service: # TODO: check if service name is correct
            name: n8n
            port:
              number: 80
  tls:
  - hosts:
    - ${BASEROW_PROD_DOMAIN}
    - ${N8N_PROD_DOMAIN}
    secretName: apps-tls-prod-cert
EOF
echo "Fichier d'ingress pour l'environnement prod généré dans $TARGET_DIR/apps-ingress-prod.yaml"

fi

# Instructions pour appliquer la configuration
echo "N'oublie pas d'appliquer le ConfigMap ingress-nginx-controller et le fichier d'ingress généré:"
echo "kubectl apply -f ingress-nginx-config.yaml"
echo "kubectl apply -f $TARGET_DIR/apps-ingress-$ENVIRONMENT.yaml"
echo "Redémarre le contrôleur ingress-nginx si tu as modifié la ConfigMap:"
echo "kubectl rollout restart deployment ingress-nginx-controller" 