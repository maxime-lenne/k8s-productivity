# FAQ, Dépannage & Maintenance

Ce document fournit des foires aux questions (FAQ), des conseils de dépannage et des procédures de maintenance pour l'environnement Kubernetes, en tenant compte de l'utilisation de **Kustomize** pour la gestion des configurations et de **Sealed Secrets** pour les secrets.

> Voir aussi : [Déploiement & Scaleway](./deploiement-scaleway.md) | [Ingress, certificats & secrets](./ingress-certificats-secrets.md)

## Table des matières
- [FAQ](#faq)
- [Maintenance](#maintenance)
- [Dépannage](#dépannage)
  - [Problèmes courants](#problèmes-courants)
  - [Problèmes spécifiques à PostgreSQL sur Scaleway](#problèmes-spécifiques-à-postgresql-sur-scaleway)
  - [Problèmes avec Let's Encrypt](#problèmes-avec-lets-encrypt)

## FAQ

**Q : Où trouver la procédure complète de déploiement ?**

R : Voir [Déploiement & Scaleway](./deploiement-scaleway.md)

**Q : Comment gérer les secrets, ingress et certificats ?**

R : Voir [Ingress, certificats & secrets](./ingress-certificats-secrets.md)

(Ajoute ici d'autres questions fréquentes selon tes besoins)

## Maintenance

### Redémarrage d'un service

Pour redémarrer un service spécifique :
```bash
kubectl rollout restart deployment <nom-du-service>
```

### Consultation des logs

Pour voir les logs d'un service :
```bash
kubectl logs -f deployment/<nom-du-service>
```

### Suppression complète de l'environnement

Pour supprimer tous les composants d'un environnement géré par Kustomize, la méthode recommandée est d'utiliser `kubectl delete -k` :

```bash
kubectl delete -k environments/<environnement>/
```

Remplacez `<environnement>` par le nom du répertoire de l'environnement (par exemple, `staging`).

Vous pouvez également supprimer les ressources individuellement si nécessaire, mais veillez à la cohérence :
```bash
kubectl delete deployment baserow n8n postgresql redis
kubectl delete service baserow n8n postgresql redis
# ... autres ressources comme PVCs, ConfigMaps, Secrets (incluant les SealedSecrets), etc.
# Soyez prudent lors de la suppression individuelle, surtout avec les PVCs si vous voulez conserver les données.
```

## Dépannage

### Problèmes courants

1. Si les pods restent en état "Pending" :
   - Vérifiez les events : `kubectl get events`
   - Vérifiez les logs : `kubectl describe pod <nom-du-pod>`

2. Si les services ne sont pas accessibles :
   - Vérifiez l'état de l'ingress : `kubectl describe ingress`
   - Vérifiez les logs de l'ingress-controller : `kubectl logs -n ingress-nginx deployment/ingress-nginx-controller`
   - Vérifiez l'état des certificats : `kubectl describe certificate`

3. Si les bases de données ne s'initialisent pas correctement :
   - Vérifiez les logs PostgreSQL : `kubectl logs -l app=postgresql`
   - Vérifiez que les secrets sont correctement montés : `kubectl describe pod <nom-du-pod-postgresql>`

### Problèmes spécifiques à PostgreSQL sur Scaleway

1. **Problème de volume persistant** :
   ```bash
   # Vérifier l'état des PVC
   kubectl get pvc
   
   # Vérifier les events liés aux PVC
   kubectl get events | grep postgresql
   
   # Vérifier les logs du pod PostgreSQL
   kubectl logs -l app=postgresql
   ```

   Solutions possibles :
   - Vérifier que le StorageClass est correctement configuré :
     ```yaml
     apiVersion: storage.k8s.io/v1
     kind: StorageClass
     metadata:
       name: csi-csi-high-speed
     provisioner: csi.scaleway.com
     parameters:
       type: b_ssd
     ```
   - S'assurer que le PVC utilise la bonne StorageClass :
     ```yaml
     apiVersion: v1
     kind: PersistentVolumeClaim
     metadata:
       name: postgresql-data
     spec:
       storageClassName: csi-csi-high-speed
       accessModes:
         - ReadWriteOnce
       resources:
         requests:
           storage: 10Gi
     ```

2. **Problème de permissions** :
   ```bash
   # Vérifier les logs du pod PostgreSQL
   kubectl logs -l app=postgresql
   
   # Vérifier les permissions du volume
   kubectl exec -it <postgresql-pod> -- ls -la /var/lib/postgresql/data
   ```

   Solutions possibles :
   - Ajouter un initContainer pour corriger les permissions :
     ```yaml
     spec:
       initContainers:
       - name: init-chmod-data
         image: busybox
         command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
         volumeMounts:
         - name: postgresql-data
           mountPath: /var/lib/postgresql/data
       volumes:
       - name: postgresql-data
         persistentVolumeClaim:
           claimName: postgresql-data
     ```

3. **Problème de connexion** :
   ```bash
   # Vérifier les logs de connexion
   kubectl logs -l app=postgresql
   
   # Vérifier les variables d'environnement injectées dans le pod
   kubectl describe pod <postgresql-pod>
   ```

   Les variables d'environnement pour la connexion à PostgreSQL (comme `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`) sont lues à partir de ConfigMaps et Secrets gérés par Kustomize et Sealed Secrets. Vérifiez que les clés et les noms des Secrets/ConfigMaps référencés dans le déploiement de base (`base/postgresql/postgresql-deployment.yaml`) correspondent bien aux noms des ressources générées/déchiffrées dans l'environnement cible (comme défini dans `environments/<environnement>/kustomization.yaml`).

   Solutions possibles :
   - Vérifier les valeurs dans la ConfigMap et le Secret générés par Kustomize/Sealed Secrets pour l'environnement.
   - S'assurer que les références (`valueFrom.secretKeyRef`, `valueFrom.configMapKeyRef`) dans le déploiement de base sont correctes.

4. **Problème de redémarrage** :
   ```bash
   # Vérifier l'historique des redémarrages
   kubectl describe pod <postgresql-pod>
   
   # Vérifier les logs précédents
   kubectl logs -l app=postgresql --previous
   ```

   Solutions possibles :
   - Ajouter des probes de liveness et readiness :
     ```yaml
     livenessProbe:
       exec:
         command:
         - pg_isready
         - -U
         - postgres
       initialDelaySeconds: 30
       periodSeconds: 10
     readinessProbe:
       exec:
         command:
         - pg_isready
         - -U
         - postgres
       initialDelaySeconds: 5
       periodSeconds: 2
     ```

5. **Problème de performance** :
   ```bash
   # Vérifier les ressources utilisées
   kubectl top pod <postgresql-pod>
   
   # Vérifier les limites de ressources
   kubectl describe pod <postgresql-pod>
   ```

   Solutions possibles :
   - Ajuster les ressources :
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

1. Si les certificats ne sont pas émis :
   ```bash
   kubectl describe certificate
   kubectl describe challenges
   ```

2. Vérifiez que vos domaines sont accessibles :
   ```bash
   curl -v http://votre-domaine/.well-known/acme-challenge/
   ```

3. Limites de taux atteintes :
   - Utilisez l'environnement staging pour les tests
   - Attendez que les limites soient réinitialisées pour la production 

## Gestion multi-environnement

La gestion multi-environnement est assurée par **Kustomize**. Référez-vous à la section dédiée dans le [README.md](../README.md#gestion-multi-environnement-avec-kustomize) principal pour plus de détails sur la structure et le fonctionnement des overlays. 