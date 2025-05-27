#!/bin/bash

# Load environment variables
set -a
source .env
set +a

# Generate ingress-nginx ConfigMap
cat > ingress-nginx-config.yaml << EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: default
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
data:
  ssl-redirect: "${SSL_REDIRECT}"
  force-ssl-redirect: "${FORCE_SSL_REDIRECT}"
EOF

# Generate local ingress configuration
cat > apps-ingress-local.yaml << EOF
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

# Generate production ingress configuration
cat > apps-ingress-prod.yaml << EOF
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
          service:
            name: n8n
            port:
              number: 80
  tls:
  - hosts:
    - ${BASEROW_PROD_DOMAIN}
    - ${N8N_PROD_DOMAIN}
    secretName: apps-tls-prod-cert
EOF

# Apply configurations
echo "Applying ingress-nginx ConfigMap..."
kubectl apply -f ingress-nginx-config.yaml

echo "Applying ingress configurations..."
kubectl apply -f apps-ingress-local.yaml -f apps-ingress-prod.yaml

echo "Restarting ingress-nginx controller to apply ConfigMap changes..."
kubectl rollout restart deployment ingress-nginx-controller

echo "Configurations applied successfully!" 