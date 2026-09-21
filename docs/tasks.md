# Kubernetes Productivity Environment Improvement Tasks

This document contains a prioritized list of tasks to improve the Kubernetes productivity environment. Each task is marked with a checkbox that can be checked off when completed.

## Architecture Improvements

1. [x] Implement Helm charts for the entire application stack
   - [x] Create a parent chart with dependencies for all components
   - [x] Convert existing Kubernetes manifests to Helm templates
   - [x] Add configurable values.yaml files for different environments

2. [ ] Implement a proper CI/CD pipeline
   - [x] Set up GitHub Actions or similar CI/CD tool
   - [x] Create workflows for testing, building, and deploying
   - [ ] Implement environment-specific deployments (dev, staging, prod)

3. [ ] Implement a backup and restore strategy
   - [x] Set up automated backups for PostgreSQL databases (CronJob `postgres-backup`, daily at 01:00, tested manually on 2026-09-21)
   - [x] Configure backup retention policies (script removes dumps older than 7 days)
   - [ ] Create and document restore procedures
   - [ ] Test backup and restore processes

4. [ ] Implement monitoring and alerting
   - [ ] Deploy Prometheus and Grafana for monitoring
   - [ ] Create dashboards for key metrics
   - [ ] Set up alerts for critical issues
   - [ ] Implement logging with Elasticsearch, Fluentd, and Kibana (EFK) or similar

5. [ ] Implement high availability for critical components
   - [ ] Configure PostgreSQL with replication
   - [ ] Set up Redis with sentinel or cluster mode
   - [ ] Ensure proper pod disruption budgets and anti-affinity rules

## Security Improvements

6. [ ] Enhance secret management
   - [x] Implement a secrets management solution (HashiCorp Vault, Sealed Secrets, etc.)

7. [ ] Implement network policies
   - [ ] Define and apply restrictive network policies for all components
   - [ ] Limit pod-to-pod communication to necessary paths only
   - [ ] Secure ingress traffic with proper TLS settings

8. [ ] Implement pod security policies
   - [ ] Define and apply security contexts for all pods
   - [ ] Restrict container capabilities
   - [ ] Implement read-only root filesystems where possible

9. [ ] Implement proper RBAC
   - [ ] Create service accounts with minimal permissions
   - [ ] Define roles and role bindings for different components
   - [ ] Implement namespace isolation

10. [ ] Implement security scanning
    - [ ] Set up container image scanning
    - [ ] Implement Kubernetes manifest validation
    - [ ] Perform regular security audits

## Code and Configuration Improvements

11. [ ] Improve environment variable management
    - [ ] Validate required environment variables in scripts
    - [ ] Provide better default values and examples
    - [ ] Add comments explaining each variable's purpose

12. [ ] Implement health checks and probes
    - [ ] Add liveness and readiness probes to all deployments
    - [ ] Configure appropriate probe settings (timeouts, periods, etc.)
    - [ ] Implement startup probes for slow-starting applications

13. [ ] Improve resource management
    - [ ] Review and optimize resource requests and limits
    - [ ] Implement horizontal pod autoscaling
    - [ ] Configure pod disruption budgets

14. [ ] Refactor shell scripts
    - [ ] Add proper error handling
    - [ ] Implement logging
    - [ ] Add usage documentation
    - [ ] Make scripts more modular and reusable

15. [ ] Implement persistent storage for Redis
    - [x] Add PersistentVolumeClaim for Redis data
    - [x] Configure Redis to use persistent storage (AOF enabled, `/data` on `redis-data`)
    - [ ] Ensure proper backup and restore procedures

## Documentation Improvements

16. [ ] Create comprehensive deployment documentation
    - [ ] Document prerequisites and dependencies
    - [ ] Create step-by-step deployment guides
    - [ ] Document configuration options and customization

17. [ ] Create architecture documentation
    - [ ] Create architecture diagrams
    - [ ] Document component interactions
    - [ ] Document data flows

18. [ ] Create operational documentation
    - [ ] Document monitoring and alerting procedures
    - [ ] Create troubleshooting guides
    - [ ] Document backup and restore procedures
    - [ ] Create runbooks for common operational tasks

19. [ ] Create developer documentation
    - [ ] Document local development setup
    - [ ] Create contribution guidelines
    - [ ] Document testing procedures

20. [ ] Implement documentation versioning
    - [ ] Ensure documentation is versioned with code
    - [ ] Create a process for keeping documentation up-to-date
    - [ ] Add changelog documentation

## Testing Improvements

21. [ ] Implement automated testing
    - [ ] Create unit tests for scripts
    - [ ] Implement integration tests for the entire stack
    - [ ] Set up end-to-end testing

22. [ ] Implement chaos testing
    - [ ] Test resilience to pod failures
    - [ ] Test resilience to node failures
    - [ ] Test resilience to network issues

23. [ ] Implement load testing
    - [ ] Create load testing scenarios
    - [ ] Establish performance baselines
    - [ ] Identify and address performance bottlenecks

24. [ ] Implement security testing
    - [ ] Perform penetration testing
    - [ ] Implement regular vulnerability scanning
    - [ ] Test security controls and policies

25. [ ] Implement compliance testing
    - [ ] Identify applicable compliance requirements
    - [ ] Implement tests for compliance verification
    - [ ] Create compliance documentation and reports

## Local Cluster Stabilization (follow-up of 2026-09-21)

Context: the local Docker Desktop cluster was crash-looping (Docker VM at 8 GB with 116 % memory limits, swap full). The VM is now at 16 GB / 8 CPU / 2 GB swap, PVs are `Retain`, and a manual backup exists in `~/k8s-backups/20260921-115518/`. HTTPS is now exposed on port **444** and HTTP on **8080** (80 and 443 are used by the `houblons-nous` project on the same machine).

26. [ ] Push the local commits (branch `add-excalidraw-metabase-supabase`) and open a PR
    - [x] Commit the pending changes (backup CronJob + Redis PVC, port 444 + kong/realtime limits, shared Claude settings, port-forward removal)
    - [ ] Push and open the PR against `main`

27. [ ] Watch the cluster for regressions (24-48 h)
    - [ ] Check `kubectl get pods -A` for growing restart counters
    - [ ] Baseline that cannot be reset (static pods / DaemonSets): `kube-scheduler` 2213, `kube-controller-manager` 2188, `kindnet` 11, `kube-proxy` 10
    - [ ] If a pod restarts, inspect `lastState` (OOMKilled vs. probe failure) before changing limits
    - [ ] Install metrics-server (`kubectl top` currently fails: "Metrics API not available")

28. [ ] Keep the local cluster from colliding with the `houblons-nous` project (other project, same machine)
    - [x] The Docker container `baserow` is NOT a duplicate: it is `houblons-nous` (compose project `houblon-nous`, `~/Documents_non_icloud/workspace_python/houblon-nous`), served at `https://houblons-nous.white-wood.tech` through a Cloudflare tunnel (`cloudflared`) whose origin is `http://localhost:80`. Never stop/remove it from this repo
    - [x] It publishes host ports 80 and 443, so the local cluster must not: it uses 8080 (HTTP) and 444 (HTTPS)
    - [ ] Its container was left without any network after the Docker Desktop restart (no published port, tunnel gets a 404): recreate it from its project with `docker compose up -d --force-recreate` (data is on the host bind mount `data/db/data`, not in the container)
    - [ ] Add a check in `setup-access.sh` that warns if a container other than the load balancer publishes 8080/444
    - [ ] Do NOT run `docker system prune` / `docker volume prune` (volume `baserow_data` belongs to houblons-nous; `baudelet-dev_postgres_data` looks unused but may hold data)

29. [ ] Make backups survive the cluster
    - [ ] Copy dumps out of the `postgres-backup-data` PVC (it is local to the cluster) to the Mac or remote storage
    - [ ] Test `scripts/backup/postgres-restore.sh` against a fresh backup (restore into a scratch database)
    - [ ] Replace `bitnamilegacy/kubectl:1.33` (unmaintained mirror, kubectl 1.33 vs. server 1.35) with a maintained image that has a shell
    - [ ] Keep `~/k8s-backups/` until a restore has been validated

30. [ ] Make PV retention declarative
    - [ ] The 5 existing PVs were patched to `Retain` by hand; new PVs from the `standard` (local-path) class are still `Delete`
    - [ ] Create a `Retain` StorageClass for local and use it in the local overlay (PVC `storageClassName` is immutable: plan a migration)

31. [ ] Finish the port 444 migration
    - [x] Run `setup-access.sh` end to end in local mode (`kubectl port-forward` removed: the Docker Desktop load balancer publishes 8080/444 and the script only checks it)
    - [ ] The load balancer listens on all interfaces, so "local" mode is no longer restricted to this machine: decide whether that is acceptable (macOS firewall or another approach otherwise)
    - [ ] `scripts/local/stop-access.sh` only kills leftover port-forwards now and has nothing left to stop: delete it (and its mentions in README / docs) or repurpose it
    - [ ] Verify `--network` mode (dnsmasq + `0.0.0.0`) with port 444 from another device
    - [ ] Align Supabase public URLs: `GOTRUE_SITE_URL` / `API_EXTERNAL_URL` (`http://localhost:3000`) and Studio `http://localhost:4000` should point to `https://supabase.white-wood.local:444`
    - [ ] Check `scripts/staging/*` and staging/prod docs: they must keep 443

32. [ ] Tune resources per environment
    - [ ] Baserow: request 2 Gi / limit 4 Gi is heavy for local; set a lower limit in the local overlay
    - [ ] Base limits for kong (512 Mi) and realtime (256 Mi) are too low and only fixed in the local overlay: check staging/prod
    - [ ] Check why `supabase-secret` shows `configured` on every `kubectl apply -k` (make sure placeholder values never overwrite live secrets)
    - [ ] Document the minimum Docker Desktop resources for the local stack (>= 12 GB RAM recommended) in `docs/local-deployment.md`
    - [ ] Find out what scaled `metabase` to 0 replicas on 2026-09-21 (not done manually) and whether a script does it
