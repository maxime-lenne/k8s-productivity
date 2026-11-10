#!/usr/bin/env bash
# Supprime puis recrée l'environnement STAGING sur le cluster Scaleway.
# N'effectue aucune action sur l'environnement de production.
#
# Prérequis :
#   - KUBECONFIG pointant vers le cluster (ex. export KUBECONFIG=./environments/staging/kubeconfig-k8s-productivity.yaml)
#   - kubectl et kustomize disponibles
#
# Usage : depuis la racine du repo :
#   ./scripts/staging/recreate-staging.sh

set -e
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
STAGING_DIR="environments/staging"
NAMESPACE="staging"

echo "=== Environnement ciblé : STAGING uniquement (aucune action sur prod) ==="
echo "Répertoire overlay : $STAGING_DIR"
echo ""

# 1. Suppression de l'environnement staging
echo "1. Suppression des ressources staging (kubectl delete -k $STAGING_DIR)..."
kubectl delete -k "$STAGING_DIR" 2>/dev/null || true
echo "   Attente de la fin de la suppression (30s)..."
sleep 30

# 2. S'assurer que le namespace existe
echo "2. Création du namespace $NAMESPACE si besoin..."
kubectl create namespace "$NAMESPACE" 2>/dev/null || true

# 3. Réappliquer la configuration staging
echo "3. Application de la configuration staging (kubectl apply -k $STAGING_DIR --validate=false)..."
kubectl apply -k "$STAGING_DIR" --validate=false

echo ""
echo "4. Vérification rapide :"
kubectl get all -n "$NAMESPACE" 2>/dev/null | head -30
echo ""
kubectl get ingress,certificate,sealedsecret -n "$NAMESPACE" 2>/dev/null || true
echo ""
echo "=== Staging recréé. Pour suivre les pods : kubectl get pods -n staging -w ==="
