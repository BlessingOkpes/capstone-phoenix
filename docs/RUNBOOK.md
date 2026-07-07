# Runbook — Capstone Phoenix

All commands assume you're on the control machine (an EC2 instance with Terraform, Ansible,
AWS CLI, and kubectl installed), inside a clone of this repo.

## 0. Zero to running

```bash
# 1. Bootstrap remote state (ONE TIME ONLY, before terraform init)
cd infra/terraform
chmod +x bootstrap-backend.sh
./bootstrap-backend.sh
# copy the printed bucket name into backend.tf, replacing REPLACE-WITH-YOUR-BUCKET-NAME

# 2. Set your admin IP (for SSH + k3s API access)
cp terraform.tfvars.example terraform.tfvars
curl -s ifconfig.me   # copy this IP
# edit terraform.tfvars: admin_cidr = "<that-ip>/32"

# 3. Provision the 3 nodes
terraform init
terraform apply

# 4. Bring up the cluster
cd ../ansible
chmod +x generate_inventory.sh
ansible-galaxy collection install -r requirements.yml
./generate_inventory.sh
ansible-playbook -i inventory.ini install-k3s.yml

# 5. Verify
export KUBECONFIG=$(pwd)/k3s.yaml
kubectl get nodes   # expect 3 nodes, all Ready

# 6. Deploy the app
cd ../..
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/backend/configmap.yaml
kubectl create secret generic backend-secret \
  --from-literal=DATABASE_USER=taskapp \
  --from-literal=DATABASE_PASSWORD=taskapp123 \
  --from-literal=SECRET_KEY=$(openssl rand -base64 32) \
  -n taskapp
kubectl apply -f manifests/postgres/service.yaml
kubectl apply -f manifests/postgres/statefulset.yaml
kubectl apply -f manifests/backend/migration-job.yaml
kubectl apply -f manifests/backend/deployment.yaml
kubectl apply -f manifests/backend/service.yaml
kubectl apply -f manifests/frontend/deployment.yaml
kubectl apply -f manifests/frontend/service.yaml

# 7. TLS
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml
# edit manifests/ingress/cluster-issuer.yaml with your real email
# edit manifests/ingress/ingress.yaml with your nip.io domain (terraform output nip_io_domain)
kubectl apply -f manifests/ingress/cluster-issuer.yaml
kubectl apply -f manifests/ingress/ingress.yaml

# 8. GitOps
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
# edit gitops/taskapp-application.yaml with your GitHub username, commit + push it
kubectl apply -f gitops/taskapp-application.yaml

# 9. Advanced
kubectl apply -f manifests/backend/hpa.yaml
kubectl apply -f manifests/backend/pdb.yaml
```

After step 6, an admin user needs to be seeded manually (the migration only builds schema,
not data):
```bash
kubectl exec -it $(kubectl get pod -l app=backend -n taskapp -o name | head -1) -n taskapp -- \
  python3 -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('admin123', method='pbkdf2:sha256'))"
# copy the hash, then:
kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp -d taskapp -c \
  "INSERT INTO users (username, password_hash, created_at) VALUES ('admin', '<hash>', NOW());"
```

## Scaling

```bash
# Manual scale (will be overwritten by HPA if CPU crosses the threshold)
kubectl scale deployment/backend -n taskapp --replicas=3

# Change HPA thresholds: edit manifests/backend/hpa.yaml, commit + push — Argo CD applies it
```

## Rolling back a bad deploy

```bash
kubectl rollout history deployment/backend -n taskapp
kubectl rollout undo deployment/backend -n taskapp
# or to a specific revision:
kubectl rollout undo deployment/backend -n taskapp --to-revision=<N>
```

Since GitOps owns the cluster, the more correct rollback is: `git revert` the bad commit in this
repo and push — Argo CD's `selfHeal: true` will reconcile the cluster back to that state
automatically within its next sync cycle (or force it immediately, see below).

## Recovering from a dead worker node

The cluster tolerates losing a worker with zero manual intervention needed — Kubernetes
reschedules affected pods to remaining nodes automatically (proven live via
`kubectl drain <node> --ignore-daemonsets --delete-emptydir-data`, see `docs/EVIDENCE/`).
To bring a node back after maintenance:
```bash
kubectl uncordon <node-name>
```
If a node is truly gone (terminated, not just drained), re-run the Ansible playbook against a
freshly Terraform-provisioned replacement — it's idempotent, so re-running it against the
existing 2 healthy nodes makes no changes to them.

## Recovering from a dead backend pod

Kubernetes restarts it automatically (`restartPolicy: Always` is the Deployment default) if the
liveness probe fails. To force it manually:
```bash
kubectl delete pod -l app=backend -n taskapp
```

## Recovering from a bad migration

```bash
kubectl logs job/taskapp-migrate -n taskapp   # see what failed
kubectl delete job taskapp-migrate -n taskapp
# fix manifests/backend/migration-job.yaml if the command itself was wrong, commit + push
kubectl apply -f manifests/backend/migration-job.yaml
```

Known bug hit during this build: the schema migration ran cleanly, but the app doesn't seed a
default admin account — see the manual `INSERT` step above.

## Forcing an immediate Argo CD sync (instead of waiting for the ~3 min poll)

```bash
kubectl patch application taskapp -n argocd --type merge \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

## Viewing the Argo CD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then, from your local machine, tunnel to it over SSH:
```bash
ssh -i <key>.pem -L 8080:localhost:8080 ubuntu@<control-ec2-ip>
```
Browse to `https://localhost:8080`, accept the self-signed cert warning, log in with `admin` and:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```
