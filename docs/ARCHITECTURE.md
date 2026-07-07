# Architecture — Capstone Phoenix (TaskApp on Kubernetes)

## Overview

TaskApp runs on a self-provisioned 3-node k3s cluster on AWS, replacing the earlier
single-EC2 + Portainer deployment. The goal of every change described below is the same:
remove the assumptions that only hold when everything lives on one box.

## Node topology

```
                         Internet
                             |
                    (80/443 only, public)
                             |
                    ┌────────▼────────┐
                    │   k3s server     │  control-plane
                    │  (also runs      │  172.31.5.245
                    │   Traefik +      │
                    │   cert-manager)  │
                    └────────┬────────┘
                             │ private VPC network (172.31.0.0/16)
              ┌──────────────┼──────────────┐
              │                             │
     ┌────────▼────────┐          ┌────────▼────────┐
     │   k3s agent 1     │          │   k3s agent 2    │
     │  (worker)         │          │  (worker)        │
     └───────────────────┘          └──────────────────┘
```

- **1 control-plane (k3s server)** + **2 workers (k3s agents)** — real multi-node scheduling,
  not a single-node cluster pretending to be distributed.
- All 3 nodes are t3.small EC2 instances in the default VPC, same subnet, same security group.
- Only ports **22** (restricted to the control/admin machine's IP), **80**, and **443** are open
  to the internet. The Kubernetes API (**6443**) and node-to-node ports (**8472** Flannel VXLAN,
  **10250** kubelet) are **security-group-internal only** — reachable by cluster members via a
  self-referencing SG rule, never exposed publicly. This is stricter than opening those ports to
  the whole VPC CIDR: only the 3 nodes that are actually members of this SG can reach each other
  on those ports, not anything else that happens to later launch in the same VPC.

## Request flow

```
Browser
  │  HTTPS (taskapp.<server-ip>.nip.io)
  ▼
Let's Encrypt-issued cert, terminated at Traefik (k3s's built-in Ingress controller)
  │
  ├─ path /api/*  → backend-service (ClusterIP) → backend Deployment (2 pods, Flask)
  │                                                     │
  │                                                     ▼
  │                                              postgres (headless Service)
  │                                                     │
  │                                                     ▼
  │                                              postgres-0 (StatefulSet, PVC-backed)
  │
  └─ path /*      → frontend-service (ClusterIP) → frontend Deployment (2 pods, nginx/React)
```

- **DNS**: nip.io resolves `taskapp.<public-ip>.nip.io` straight back to the server's public IP —
  no DNS registrar needed, and Let's Encrypt issues a real certificate for it since it's a genuine,
  resolvable hostname.
- **TLS**: cert-manager watches the `ClusterIssuer` + `Ingress` resources and automatically
  requests/renews a Let's Encrypt certificate via the HTTP-01 challenge, routed through Traefik.
- **Same-origin routing**: `/api` and `/` share one Ingress and one domain, avoiding CORS
  complexity entirely — chosen over separate `api.<domain>` because there's no cross-origin
  browser restriction to work around, and it's one less DNS name / cert to manage.

## What each Core requirement fixes (the single-server assumption it breaks)

| Requirement | Single-server assumption it removes |
|---|---|
| Multi-node cluster | "the app only ever runs on one machine" |
| Postgres StatefulSet + PVC | "the database's disk is always the same disk" — a Pod can be deleted and rescheduled without losing data, because storage is decoupled from the Pod's lifecycle |
| 2+ replicas, spread across nodes (topologySpreadConstraints) | "there's only one copy of the app, so if it dies, it's just down" — and specifically, that both replicas could land on the same node and share its failure |
| Migrations as a separate Job | "only one process ever runs migrations at once" — at 2+ replicas, running `alembic upgrade head` in each container's entrypoint races on the same schema change |
| Liveness/readiness/startup probes | "the process being alive means it's ready for traffic" — a pod can be running but not yet able to serve requests (e.g. still connecting to Postgres) |
| Resource requests/limits | "this box has unlimited RAM/CPU for this one app" — without limits, one runaway container can starve its neighbors on a shared node |
| RollingUpdate maxUnavailable:0 | "a deploy can just take the app down for a few seconds" |
| Ingress + real TLS | "there's one server with one IP, so a self-signed cert and manual redeploys are fine" |
| Pinned image tags | "whatever's running now is what I tested" — `:latest` can silently change under you |

## Known limitation: Traefik is a single replica

k3s installs Traefik (the Ingress controller) as a single pod by default. During the failover
demo, draining the node Traefik happened to be running on caused a brief (~1-2 second) `000`
response while it rescheduled, before backend/frontend traffic resumed normally. Every other
component (backend, frontend, Postgres) tolerated the drain with zero dropped requests. Scaling
Traefik to 2 replicas would close this gap; not done here to keep node count at the required
minimum of 3 and control cost — see `COST.md`.

## GitOps

Argo CD watches `manifests/` in this repo (recursively — an early bug where only the top-level
`namespace.yaml` was being picked up was found and fixed by adding `directory.recurse: true` to
the `Application` spec). All cluster state is reconciled from git; the only exception is the
`backend-secret` Kubernetes Secret, created imperatively via `kubectl create secret` rather than
committed to git in plaintext.
