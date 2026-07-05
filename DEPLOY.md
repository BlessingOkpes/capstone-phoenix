# Capstone Phoenix — Deploying the App (Phase 4 onward)

Run all of this on your control EC2, with:
```bash
export KUBECONFIG=~/capstone-phoenix/infra/ansible/k3s.yaml
```
(do this in every new terminal session before running kubectl)

## Phase 4 — Namespace + Secret + ConfigMap

```bash
cd ~/capstone-phoenix
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/backend/configmap.yaml

kubectl create secret generic backend-secret \
  --from-literal=DATABASE_USER=taskapp \
  --from-literal=DATABASE_PASSWORD=taskapp123 \
  --from-literal=SECRET_KEY=$(openssl rand -base64 32) \
  -n taskapp
```

Note: the Secret is created imperatively (not a committed YAML file) — this is intentional,
matches the spec's split of committed non-secret config vs. runtime secret, and means
no plaintext password ever touches git.

## Phase 5 — Postgres

```bash
kubectl apply -f manifests/postgres/service.yaml
kubectl apply -f manifests/postgres/statefulset.yaml

# Wait for it to be ready
kubectl get pods -n taskapp -w
# Ctrl+C once postgres-0 shows Running/Ready
```

## Phase 6 — Migration Job

```bash
kubectl apply -f manifests/backend/migration-job.yaml
kubectl get jobs -n taskapp -w
# Ctrl+C once taskapp-migrate shows COMPLETIONS 1/1
```

**If the Job fails or the command is wrong:** check `kubectl logs job/taskapp-migrate -n taskapp`.
The Job's `command:` field (`flask db upgrade`) is a best guess based on Michael's guide —
verify against `cicd_dockerized/k8s-lesson/` in your repo for the exact command the reference
manifests use, and edit `manifests/backend/migration-job.yaml` if it's different.

## Phase 7 — Backend + Frontend

```bash
kubectl apply -f manifests/backend/deployment.yaml
kubectl apply -f manifests/backend/service.yaml
kubectl apply -f manifests/frontend/deployment.yaml
kubectl apply -f manifests/frontend/service.yaml

kubectl get pods -n taskapp -o wide -w
```

Wait until backend and frontend pods show `Running` and `2/2` Ready-looking status (1/1 per pod, 2 pods each).

**Screenshot `kubectl get pods -n taskapp -o wide`** — you need this for evidence (proves pods spread across different nodes).

### If backend CrashLoopBackOffs (known issue — DuplicateTable)
```bash
kubectl logs -l app=backend -n taskapp
```
If you see `DuplicateTable`, run:
```bash
kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp -d taskapp -c \
  "CREATE TABLE IF NOT EXISTS alembic_version (version_num VARCHAR(32) NOT NULL, CONSTRAINT alembic_version_pkc PRIMARY KEY (version_num));"
kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp -d taskapp -c \
  "INSERT INTO alembic_version (version_num) VALUES ('d5edfb30a373');"
kubectl rollout restart deployment/backend -n taskapp
```

### Verify backend health
```bash
kubectl run testcurl --image=alpine/curl --rm -it --restart=Never -n taskapp -- \
  curl -s http://backend-service:5000/api/health
```

### Fix admin password (known issue)
```bash
kubectl exec -it $(kubectl get pod -l app=backend -n taskapp -o name | head -1) -n taskapp -- \
  python3 -c "from werkzeug.security import generate_password_hash; print(generate_password_hash('admin123', method='pbkdf2:sha256'))"
```
Copy the hash it prints, then:
```bash
kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp -d taskapp -c \
  "UPDATE users SET password_hash = '<paste-hash-here>' WHERE username = 'admin';"
```

### Fix tasks table (known issue)
```bash
kubectl exec -it postgres-0 -n taskapp -- psql -U taskapp -d taskapp -c \
  "ALTER TABLE tasks ADD COLUMN priority VARCHAR(20) NOT NULL DEFAULT 'medium', ADD COLUMN status VARCHAR(20) NOT NULL DEFAULT 'todo', ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;"
```

## Phase 8 — Ingress + TLS

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

# Wait for cert-manager pods to be ready (takes ~1 min)
kubectl get pods -n cert-manager -w
```

Edit `manifests/ingress/cluster-issuer.yaml` — replace `youremail@example.com` with your real email.

Edit `manifests/ingress/ingress.yaml` — replace both `TASKAPP_DOMAIN` placeholders with your actual
nip.io domain (from Terraform output `nip_io_domain`, e.g. `taskapp.44.192.62.66.nip.io`).

```bash
kubectl apply -f manifests/ingress/cluster-issuer.yaml
kubectl apply -f manifests/ingress/ingress.yaml

kubectl get certificate -n taskapp -w
# Ctrl+C once READY shows True (can take 1-2 minutes)
```

Test it:
```bash
curl -s https://taskapp.<YOUR-IP>.nip.io/api/health
```

**Screenshot `curl -vI https://taskapp.<YOUR-IP>.nip.io`** showing the valid cert — required evidence.

## Phase 9 — GitOps with Argo CD

First, commit and push everything so Argo CD has something to sync from:
```bash
cd ~/capstone-phoenix
git add manifests/ gitops/ infra/
git status   # confirm no .pem, .tfstate, or terraform.tfvars-with-secrets staged
git commit -m "app: core TaskApp manifests, ingress+TLS, GitOps config"
git push
```

Install Argo CD:
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.10.0/manifests/install.yaml
kubectl get pods -n argocd -w
# Ctrl+C once all argocd pods show Running
```

Get the admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Edit `gitops/taskapp-application.yaml` — replace `<your-github-username>` with your real GitHub username, then:
```bash
git add gitops/taskapp-application.yaml
git commit -m "gitops: point Argo CD Application at my fork"
git push

kubectl apply -f gitops/taskapp-application.yaml
```

View the UI (in a new terminal, keep this one open):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```
Then in your browser (you'll need to either open this port in your EC2 security group temporarily,
or set up an SSH tunnel from your laptop — ask me if you're not sure which).

Log in with username `admin` and the password from above. Confirm it shows **Synced** and **Healthy**.

**Prove GitOps works (required demo):** make a small change to a manifest (e.g. change an HPA
threshold), `git commit && git push`, then watch Argo CD auto-sync within ~3 minutes without you
running any `kubectl apply`. Screenshot before/after.

## Phase 10 — Advanced: HPA + PDB

```bash
kubectl apply -f manifests/backend/hpa.yaml
kubectl apply -f manifests/backend/pdb.yaml

kubectl get hpa -n taskapp
kubectl get pdb -n taskapp
```

**Screenshot both** — required evidence. securityContext is already baked into the backend/frontend
Deployments (3rd Advanced item, already done).

## Phase 11 — Failover demo

Terminal 1:
```bash
while true; do curl -s -o /dev/null -w "%{http_code}\n" https://taskapp.<YOUR-IP>.nip.io/api/health; sleep 0.5; done
```

Terminal 2 (need a second SSH session into the control EC2):
```bash
kubectl get nodes    # find a worker node name
kubectl drain <worker-node-name> --ignore-daemonsets --delete-emptydir-data
```

Watch Terminal 1 — should show continuous `200`s. Screenshot/record this — it's your live failover demo.

```bash
kubectl get pods -n taskapp -o wide   # confirm pods rescheduled
kubectl uncordon <worker-node-name>   # bring the node back
```

## Phase 12 — Docs + submission

Fill in `docs/ARCHITECTURE.md`, `docs/RUNBOOK.md`, `docs/COST.md`, put screenshots in `docs/EVIDENCE/`,
commit, push, and submit via the Google form linked in the assignment doc.
