# Cost — Capstone Phoenix

All prices are AWS on-demand, `us-east-1`, as of build time. Actual bill may vary slightly by
exact usage and any free-tier credits still active on the account.

## Monthly cost breakdown

| Item | Qty | Unit cost | Monthly cost |
|---|---|---|---|
| EC2 t3.small (k3s server + 2 agents) | 3 | ~$0.0208/hr → ~$15.18/mo | **$45.54** |
| EBS gp3 root volume, 20GB | 3 | ~$0.08/GB-mo → $1.60/mo | **$4.80** |
| S3 bucket (Terraform remote state) | 1 | negligible (few KB stored) | **~$0.02** |
| DynamoDB table (state lock, pay-per-request) | 1 | negligible (a few requests/apply) | **~$0.10** |
| Data transfer (demo-scale traffic) | — | first 100GB/mo free (AWS free tier) | **~$0.00–1.00** |
| Control EC2 (separate instance used to run Terraform/Ansible/kubectl) | 1 | reused existing instance from a prior assignment | **$0** (already provisioned, or ~$8.35/mo if newly created as t2.micro/t3.micro) |

**Total: ≈ $50–60/month**, depending on whether the control machine is counted as new spend or
reused sunk cost.

Not itemized above because they cost nothing extra at this scale: Let's Encrypt certificates
(free), k3s itself (free, open source), Argo CD (free, open source), nip.io DNS (free).

## How I'd cut this in half

The single biggest lever is the 3 EC2 instances, which make up ~85% of the bill. Two changes
would roughly halve total spend without violating the "3 real nodes" requirement:

1. **Downsize to t3.micro for the 2 worker nodes** (keep the server at t3.small for headroom
   running Traefik + cert-manager + the control plane). Workers mostly just run 1-2 small
   containers each in this demo — t3.micro's 1GB RAM is tight but workable for TaskApp's actual
   footprint, cutting roughly $15/month off compute.
2. **Stop (not terminate) all 3 instances outside of active development/grading windows.**
   AWS doesn't charge for EC2 compute time while an instance is stopped — only the EBS volume
   keeps accruing at ~$1.60/instance/month. For a project only actively used a few hours a day
   during a 3-week window, this alone could cut the effective compute bill by 70-80%, at the
   cost of losing the nodes' public IPs on restart (workable here since nip.io's domain is
   IP-based — restarting would mean regenerating the Ingress/TLS cert for the new IP, a ~2 minute
   fix via the runbook).

Combined, these two changes bring the realistic monthly cost from ~$50 down to roughly $20-25
for a project used intermittently rather than kept running 24/7.
