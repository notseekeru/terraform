# Argo CD 3 Upgrade: node stalls, cluster DNS outage, three failed applies (2026-10-15)

> Root cause for the episode that surfaced as chart and provider failures. Argo CD ended up on
> 3.5.5 with all Applications Synced. No data loss. All times are UTC.

## Summary

The `argo-cd` chart went from 7.7.0 to 10.10.5, which is Argo CD 2.13.0 to 3.5.5. That rollout
pulled about a gigabyte of images onto the single Pi node. The node stalled twice, the kubelet
restarted, and 1 second liveness probes turned the stall into a restart of every long-running
pod on the machine. CoreDNS lost all of its endpoints, so cluster DNS was down and Argo CD
reported `lookup argocd-repo-server on 10.43.0.10:53: connection refused` for every
Application. Three `terraform apply` runs failed on API timeouts while the chart manifests were
in fact being applied, which left the helm release record at `pending-upgrade` and then
`failed` on a cluster that was already upgraded.

## Timeline

| When (UTC) | Event |
| --- | --- |
| ~21:56 | `make plan MOD=k3s` for the chart bump. Plan is `0 to add, 2 to change, 0 to destroy` |
| ~22:00 to 22:15 | Apply 1. `ingress-nginx` modified after 5m40s, then `Error upgrading chart: create: failed to create: Timeout: request did not complete within requested timeout` at the 600s helm timeout |
| ~23:22 to 23:31 | Apply 2, after clearing the pending record. `Upgrade failed: pre-upgrade hooks failed: Hook pre-upgrade argo-cd/templates/redis-secret-init/job.yaml failed: Post .../jobs: http2: client connection lost` |
| 23:33:01 | Apply 3. Release record v3 created |
| 23:34:18 to 23:34:21 | Hook RBAC created: `redis-secret-init` ServiceAccount, Role, RoleBinding |
| 23:36:28 | Six NetworkPolicies created, the chart 10 default (`global.networkPolicy.create: true`) |
| 23:41:46 to 23:41:51 | All Argo CD workloads replaced with 3.5.5 images, dex 2.46.0, redis 8.6.4 |
| 23:41:47 | Kubelet restart: every node condition gets a new `lastTransitionTime`. `FailedScheduling ... 1 node(s) had untolerated taint(s)` lands at the same second, so the new pods could not schedule |
| ~23:44 to 23:54 | `argocd-server` liveness probe kills three containers, first `connection refused` then `context deadline exceeded` |
| ~23:47 | CoreDNS enters CrashLoopBackOff, 28 restarts on a pod created 2026-07-28. `kube-dns` reports no endpoints |
| 23:54 to 23:57 | Second node-wide stall. Every long-running container restarts: local-path-provisioner, ingress-nginx-controller, cloudflared, coredns, metrics-server, argocd-server, argocd-repo-server. Last restart 23:57:42 |
| ~23:58 to 00:00 | Apply 4, after deleting the v3 record and raising `timeout` to 1800. `Apply complete! Resources: 0 added, 2 changed, 0 destroyed` in 13s. Hook job completes 00:00:09 |
| 00:08 to 00:15 | Verification: `make plan MOD=k3s` reports `No changes`, five Applications `Synced`, CRDs byte-identical to v3.5.5 |

## Root cause

Three causes stack, and none of them is the chart or the provider version.

1. **Node capacity.** One node, 4 CPU, 8 GiB allocatable, k3s `v1.36.2+k3s1`. The rollout
   replaced seven workloads and pulled roughly a gigabyte of images. Every failed apply failed
   on a client timeout (`http2: client connection lost`, `cannot patch ... ClusterRole:
   Timeout`, `create: failed to create: Timeout`), never on a manifest error.
2. **One second probes.** Argo CD ships `timeoutSeconds: 1`, `periodSeconds: 10`,
   `failureThreshold: 3`, so about thirty seconds of API slowness kills a container. That is
   what turned a stall into a mass restart, and it is why CoreDNS ended in CrashLoopBackOff
   with an empty endpoint list. The old CoreDNS pod carried 28 restarts across 77 days.
3. **Helm record lifecycle.** With `wait` on and a 600s provider timeout, the abort landed
   after the manifests were applied and before helm finalized the release. Helm then refuses
   to upgrade over a `pending-*` record, and the record reads `failed` while the cluster is
   already upgraded.

## Why it read as a chart or provider failure

- The visible errors were `ClusterRole: Timeout`, `http2: client connection lost`,
  `does not support moving resource state across resource types` (from the earlier renames),
  and `another operation in progress`. None of them mention node stalls.
- The release record said `failed` while all pods were running 3.5.5, so Terraform and the
  cluster disagreed about reality.
- Argo CD reported its own DNS failures as `ComparisonError: failed to load target state`,
  which reads as an Argo CD bug rather than a dead CoreDNS.

## Blast radius

- Cluster DNS down for the CrashLoopBackOff window. Every Application went `Unknown`, and any
  new resolution of a Service name failed, including the apps reaching `postgres.database.svc`.
- Restarts across the node: local-path-provisioner 18, ingress-nginx-controller 14,
  cloudflared 13, metrics-server 12, argocd-server 4, argocd-repo-server 3, coredns 2.
- metrics-server down, so `kubectl top` returned `Metrics API not available` for a while.
- Argo CD API and UI unavailable while `argocd-server` crashlooped. Syncs continued through the
  application-controller, and no Application was lost or recreated.
- No data loss: PVCs, Postgres, secrets and CRDs untouched. `argocd-initial-admin-secret` from
  2026-07-29 is still the live credential.

## Recovery that worked

1. Delete the stuck record when the history shows `pending-upgrade` after an aborted client:
   `kubectl -n argocd delete secret sh.helm.release.v1.argocd.vN`.
2. Break a CoreDNS backoff by deleting its pod: `kubectl -n kube-system delete pod -l k8s-app=kube-dns`.
3. Raise `timeout` on `helm_release.argocd` (600 to 1800, commit `8b521a3`) and re-apply.
4. Apply the chart's CRDs by hand and verify them against the release that matches the running
   appVersion.
5. Confirm convergence with `make plan MOD=k3s` before walking away.

## Traps

- **Helm never upgrades CRDs.** Files under a chart's `crds/` directory are installed once and
  left alone on every later upgrade, so a chart bump leaves the old schema in place. Argo CD
  3.5.5 serves `v1alpha1` Applications from the 7.7.0 definition and works, but any field the
  old schema does not know is pruned without a message.
- **`hashicorp/kubernetes` 3.x has no `MoveState`.** `moved` blocks between the unversioned and
  `_v1` types fail at plan with `does not support moving resource state across resource types`.
  Both types still exist in 3.3.0, so the unversioned names stay and only warn.
- **`terraform init -backend=false` still dials the backend** when
  `infra/<mod>/.terraform/terraform.tfstate` exists, so it needs credentials or a cleared
  `.terraform` directory.
- **A failed helm run is not rolled back.** The manifest list is applied in order, so a later
  attempt can complete the upgrade while the previous record stays `failed`.
- **The expensive part is the image, not the semver.** A patch bump that moves an image tag
  costs the same churn as a major bump.

## What to do differently

- Pre-pull the new images on the node before the window, so the rollout is not also the
  download.
- Set the helm timeout from measured pull time, not the chart default: 1800s for `argo-cd`.
- Apply the CRDs first, from the argo-cd release that matches the chart's `appVersion`, then
  the chart.
- Raise the Argo CD probe timeouts through chart values. The defaults mean any thirty second
  hiccup restarts the whole component set.
- Run the window when nothing else needs the node, and confirm no Terraform process is still
  running before starting another attempt. The state lock is the only guard.
- Save one plan file per attempt and apply that file, so a retry cannot pick up a different
  diff than the one reviewed.

## Current state

Argo CD 3.5.5 on chart 10.10.5, helm release v3 `deployed`, CRDs byte-identical to v3.5.5, all
five Applications `Synced` and `Healthy`, `make plan MOD=k3s` reports `No changes`. Node Ready
with no pressure, no not-ready pods, nothing restarted since 23:57:42.

## Open

- Argo CD still runs the chart default probe timeouts.
- CRDs are a manual step on every chart bump, with no `make` target.
- The failed release revision v2 stays in the helm history. Harmless, and it is the record of
  what happened.
- The `aws` module holds an empty state, unrelated to this incident.

## Labels

`type:incident` · `impact:partial-outage` · `cause:node-capacity` · `component:kubelet` ·
`component:coredns` · `component:argocd` · `environment:homelab-k3s` · `resolved`
