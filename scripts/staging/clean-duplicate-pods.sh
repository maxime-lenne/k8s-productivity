#!/usr/bin/env bash
# Nettoie les pods en double sur staging en remettant chaque déploiement à 1 replica.
# À lancer avec le kubeconfig pointant vers le cluster staging.
# Usage: ./scripts/staging/clean-duplicate-pods.sh [namespace]
# Par défaut namespace=staging.

set -e
NAMESPACE="${1:-staging}"

echo "Namespace: $NAMESPACE"
echo "Mise à 0 de tous les déploiements..."
kubectl scale deployment --all --replicas=0 -n "$NAMESPACE"

echo "Attente de la terminaison des pods (60s max)..."
for i in $(seq 1 30); do
  count=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
  if [ "$count" -eq 0 ]; then
    echo "Tous les pods sont terminés."
    break
  fi
  echo "  Pods restants: $count"
  sleep 2
done

echo "Remise à 1 replica de tous les déploiements..."
kubectl scale deployment --all --replicas=1 -n "$NAMESPACE"

echo "État actuel:"
kubectl get deployments -n "$NAMESPACE"
echo ""
kubectl get pods -n "$NAMESPACE"

echo ""
echo "Si des pods restent en Pending, exécuter: kubectl describe pod <nom> -n $NAMESPACE"
echo "Si supabase-kong a Init:CreateContainerConfigError, vérifier que le secret postgresql-secret existe et contient SUPABASE_DB_NAME, SUPABASE_DB_USER, SUPABASE_DB_PASSWORD."
