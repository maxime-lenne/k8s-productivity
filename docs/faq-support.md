# FAQ & Support

Ce document fournit des foires aux questions (FAQ), des conseils de dépannage et des procédures de maintenance pour l'environnement Kubernetes.

> Voir aussi : [Déploiement Local](./local-deployment.md) | [Déploiement Scaleway](./scaleway-deployment.md) | [Certificats & Secrets](./certificats-secrets.md)

## Table des matières

- [FAQ](#faq)
- [Maintenance](#maintenance)
- [Dépannage](#dépannage)
  - [Problèmes courants](#problèmes-courants)
  - [Problèmes spécifiques à PostgreSQL](#problèmes-spécifiques-à-postgresql)
  - [Problèmes avec Let's Encrypt](#problèmes-avec-lets-encrypt)
  - [Problèmes réseau local](#problèmes-réseau-local)
- [Commandes utiles](#commandes-utiles)

---

## FAQ

### Où trouver la procédure complète de déploiement ?

- **Local (Mac)** : Voir [Déploiement Local](./local-deployment.md)
- **Cloud (Scaleway)** : Voir [Déploiement Scaleway](./scaleway-deployment.md)

### Comment gérer les secrets, ingress et certificats ?

Voir [Certificats & Secrets](./certificats-secrets.md)

### Comment accéder aux services depuis un autre appareil ?

Utilisez le mode réseau du script `setup-access.sh` :

```bash
sudo ./scripts/local/setup-access.sh --network
```

Consultez la section [Accès réseau local](./local-deployment.md#accès-réseau-local-depuis-dautres-machines) pour plus de détails.

### Puis-je utiliser un autre domaine que `.white-wood.local` ?

Oui, modifiez :
1. `scripts/local/install-dnsmasq.sh` : changez `white-wood.local` par votre domaine
2. `environments/local/kustomization.yaml` : mettez à jour tous les domaines
3. Redéployez : `kubectl apply -k environments/local`

### Puis-je accéder aux services depuis l'extérieur de mon réseau local ?

Non, pas avec la configuration locale. Pour un accès externe :
- Configurez un VPN (Wireguard, Tailscale)
- Utilisez un tunnel (Cloudflare Tunnel, ngrok)
- Déployez sur un cloud avec un domaine public

### Le port-forward survit-il à un redémarrage ?

Non. Vous devez relancer le script après chaque redémarrage. Pour automatiser, créez un LaunchDaemon macOS (voir [local-deployment.md](./local-deployment.md)).

---

## Maintenance

### Redémarrage d'un service

```bash
kubectl rollout restart deployment <nom-du-service>
```

### Consultation des logs

```bash
# Logs d'un déploiement
kubectl logs -f deployment/<nom-du-service>

# Logs d'un pod spécifique
kubectl logs -f <nom-du-pod>

# Logs précédents (après un crash)
kubectl logs --previous <nom-du-pod>
```

### Mise à jour des images

```bash
# Mettre à jour une image
kubectl set image deployment/<service> <container>=<image>:<tag>

# Vérifier le rollout
kubectl rollout status deployment/<service>

# Revenir à la version précédente si problème
kubectl rollout undo deployment/<service>
```

### Suppression complète d'un environnement

```bash
# Via Kustomize (recommandé)
kubectl delete -k environments/<environnement>/

# Suppression manuelle
kubectl delete deployment baserow n8n postgresql redis
kubectl delete service baserow n8n postgresql redis
kubectl delete pvc --all  # Attention : supprime les données !
```

---

## Dépannage

### Problèmes courants

#### Les pods restent en état "Pending"

```bash
# Vérifier les events
kubectl get events --sort-by='.lastTimestamp'

# Vérifier les détails du pod
kubectl describe pod <nom-du-pod>

# Causes fréquentes :
# - Pas assez de ressources (CPU/mémoire)
# - PVC non provisionné
# - Image non trouvée
```

#### 0/1 nodes are available: 1 Insufficient memory (No preemption victims found)

Le nœud n’a pas assez de mémoire « allocatable » pour planifier le pod (les `requests` des pods déjà présents + ce pod dépassent la capacité du nœud).

**Déjà en place pour staging** : l’overlay `environments/staging` réduit les requêtes mémoire de PostgreSQL (128Mi), Baserow (512Mi) et Metabase (256Mi) pour tenir sur un petit nœud (ex. DEV1-S/M).

**Si le pod reste en Pending après un apply** :
1. Réappliquer le staging pour que les patches ressources soient pris en compte :  
   `kubectl apply -k environments/staging/ --validate=false`
2. Vérifier la capacité du nœud :  
   `kubectl describe node` (section Allocatable: memory)
3. Réduire encore les `requests` dans `environments/staging/kustomization.yaml` (patches similaires pour d’autres déploiements), ou **augmenter la taille du nœud** (ex. passer à un type plus gros sur Scaleway).

#### Les services ne sont pas accessibles

```bash
# Vérifier l'état de l'ingress
kubectl describe ingress -n <namespace>

# Vérifier les logs de l'ingress-controller
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller

# Vérifier l'état des certificats
kubectl describe certificate -n <namespace>
```

#### Les bases de données ne s'initialisent pas

```bash
# Vérifier les logs PostgreSQL
kubectl logs -l app=postgresql

# Vérifier que les secrets sont correctement montés
kubectl describe pod -l app=postgresql

# Vérifier les PVCs
kubectl get pvc
```

### Problèmes spécifiques à PostgreSQL

#### Problème de volume persistant

```bash
# Vérifier l'état des PVC
kubectl get pvc

# Vérifier les events liés aux PVC
kubectl get events | grep postgresql

# Vérifier les logs
kubectl logs -l app=postgresql
```

**Solutions** :
- Vérifier que le StorageClass est correctement configuré
- S'assurer que le PVC utilise la bonne StorageClass

#### Problème de permissions

```bash
# Vérifier les logs
kubectl logs -l app=postgresql

# Vérifier les permissions du volume
kubectl exec -it <postgresql-pod> -- ls -la /var/lib/postgresql/data
```

**Solution** : Ajouter un initContainer pour corriger les permissions :

```yaml
initContainers:
- name: init-chmod-data
  image: busybox
  command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
  volumeMounts:
  - name: postgresql-data
    mountPath: /var/lib/postgresql/data
```

#### Problème de connexion

```bash
# Vérifier les logs de connexion
kubectl logs -l app=postgresql

# Vérifier les variables d'environnement
kubectl describe pod <postgresql-pod>
```

**Solution** : Vérifier que les secrets et ConfigMaps sont correctement référencés.

#### Problème de performance

```bash
# Vérifier les ressources utilisées
kubectl top pod <postgresql-pod>

# Vérifier les limites de ressources
kubectl describe pod <postgresql-pod>
```

**Solution** : Ajuster les ressources dans le déploiement :

```yaml
resources:
  requests:
    memory: "1Gi"
    cpu: "500m"
  limits:
    memory: "2Gi"
    cpu: "1000m"
```

### Problèmes avec Let's Encrypt

#### Les certificats ne sont pas émis

```bash
kubectl describe certificate
kubectl describe challenges
kubectl get events | grep cert-manager
```

#### Vérifier l'accessibilité des domaines

```bash
curl -v http://votre-domaine/.well-known/acme-challenge/
```

#### Limites de taux atteintes

- Utilisez l'environnement staging de Let's Encrypt pour les tests
- Attendez que les limites soient réinitialisées

### Problèmes réseau local

#### Le DNS ne résout pas les domaines `.white-wood.local`

```bash
# Vérifier que dnsmasq est actif
brew services list | grep dnsmasq

# Tester la résolution DNS directement
dig @127.0.0.1 baserow.white-wood.local

# Vider le cache DNS macOS
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

#### Les services ne sont pas accessibles depuis le réseau

```bash
# Vérifier le port-forward
ps aux | grep "kubectl port-forward"

# Vérifier les logs
tail -f /tmp/k8s-logs/port-forward.log

# Tester la connectivité
nc -zv 192.168.x.x 80
nc -zv 192.168.x.x 444
```

#### Le pare-feu macOS bloque les connexions

```bash
# Autoriser kubectl
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/local/bin/kubectl
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/local/bin/kubectl
```

---

## Commandes utiles

### État général du cluster

```bash
# Voir tous les pods
kubectl get pods -A

# Voir les ressources d'un namespace
kubectl get all -n <namespace>

# Voir les events récents
kubectl get events --sort-by='.lastTimestamp'
```

### Diagnostic des pods

```bash
# Détails d'un pod
kubectl describe pod <pod-name>

# Logs en temps réel
kubectl logs -f <pod-name>

# Exécuter une commande dans un pod
kubectl exec -it <pod-name> -- /bin/sh
```

### Gestion des déploiements

```bash
# Voir l'historique des rollouts
kubectl rollout history deployment/<name>

# Rollback
kubectl rollout undo deployment/<name>

# Mise à l'échelle
kubectl scale deployment/<name> --replicas=3
```

### Gestion des secrets

```bash
# Lister les secrets
kubectl get secrets

# Voir le contenu d'un secret (base64)
kubectl get secret <name> -o yaml

# Décoder une valeur
kubectl get secret <name> -o jsonpath='{.data.<key>}' | base64 -d
```

### Réseau et ingress

```bash
# Voir les ingress
kubectl get ingress

# Voir les services
kubectl get svc

# Voir les endpoints
kubectl get endpoints
```

### Stockage

```bash
# Voir les PVCs
kubectl get pvc

# Voir les PVs
kubectl get pv

# Voir les StorageClasses
kubectl get storageclass
```

### Certificats

```bash
# Voir les certificats
kubectl get certificate

# Voir les issuers
kubectl get clusterissuer

# Voir les challenges en cours
kubectl get challenges
```
