# FAQ, Dépannage & Maintenance

> Voir aussi : [Déploiement & Scaleway](./deploiement-scaleway.md) | [Ingress, certificats & secrets](./ingress-certificats-secrets.md)

## Table des matières
- [FAQ](#faq)
- [Maintenance](#maintenance)
- [Dépannage](#dépannage)
  - [Problèmes courants](#problèmes-courants)
  - [Problèmes spécifiques à PostgreSQL sur Scaleway](#problèmes-spécifiques-à-postgresql-sur-scaleway)
  - [Problèmes avec Let's Encrypt](#problèmes-avec-lets-encrypt)
- [Gestion multi-environnement](#gestion-multi-environnement)

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

Pour supprimer tous les composants :
```bash
kubectl delete deployment baserow n8n postgresql redis
kubectl delete service baserow n8n postgresql redis
kubectl delete pvc --all
kubectl delete configmap postgresql-config init-script
kubectl delete secret postgresql-secret redis-secret baserow-secret apps-tls-cert
kubectl delete certificate apps-tls-cert
kubectl delete clusterissuer selfsigned-issuer
helm uninstall ingress-nginx
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.3/cert-manager.yaml
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
   
   # Vérifier les variables d'environnement
   kubectl describe pod <postgresql-pod>
   ```

   Solutions possibles :
   - Vérifier que les variables d'environnement sont correctement définies :
     ```yaml
     env:
     - name: POSTGRES_USER
       valueFrom:
         secretKeyRef:
           name: postgresql-secret
           key: username
     - name: POSTGRES_PASSWORD
       valueFrom:
         secretKeyRef:
           name: postgresql-secret
           key: password
     - name: POSTGRES_DB
       valueFrom:
         secretKeyRef:
           name: postgresql-secret
           key: database
     ```

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

Pour changer d'environnement (local, staging, prod), il suffit de générer les secrets et ingress avec l'argument correspondant :

```bash
./generate-secrets.sh staging
./generate-ingress-configs.sh staging
```

Vérifiez que le fichier `.env.staging` (ou `.env.local`, `.env.prod`) est bien présent et adapté à votre environnement. Les scripts chargeront automatiquement le bon fichier.

En cas de problème, vérifiez les logs des scripts et la présence des fichiers d'environnement. 