# Container Name Reservation Livelock: 6 pods dead for 2h14m after a power cut (2026-10-12)

> Root cause for the episode that surfaced as "ArgoCD is having a meltdown". No data loss.
> All times are node-local (UTC+08:00); the node reports them as `PST` but the offset is
> +08:00.

## Summary

The node, running k3s `v1.36.2+k3s1` on containerd `2.3.2-k3s2`, lost power and came back at
12:47:33. During the kubelet's first pod sync it issued two `CreateContainer` calls for the
same container name and the same attempt index. containerd reserved that name for whichever
call won and rejected the other with `FailedPrecondition: failed to reserve container name ...
check if another CreateContainer request is in progress`. For six pods the kubelet recorded
the rejection and kept the previous, exited container's ID, so on every later sync it
recomputed the same attempt index, hit the same live reservation, and failed again. It does
not converge. 3520 pod syncs failed over 2h14m, ending when the six pods were deleted and
recreated on new UIDs.

## Timeline

| When (local) | Event |
| --- | --- |
| 12:47:33 | Node boots after a power cut |
| 12:47:52 | Kubelet initializes the container manager |
| 12:47:59 | First reservation failure, `argocd-server` |
| 12:48:00 | The six affected containers are created and start running |
| 12:48:01 | Reservation failures begin for all six and continue for 2h14m |
| 15:02:03 | Last reservation failure, six pods deleted |
| 15:02:05 | Postgres shuts down cleanly (`database system was shut down`) |
| 15:02:11 | Postgres ready to accept connections |
| 15:05 | All five Applications `Synced` + `Healthy` |

## Root cause

containerd reserves a container name for the duration of a create, so a second concurrent
create for the same name cannot proceed. The kubelet issued both calls. Which of the two it
kept is the entire failure, and the one pod that recovered proves it:

| Pod | Kubelet's recorded container ID | Container in containerd | Outcome |
| --- | --- | --- | --- |
| `argocd-server` | `407aa9ed`, attempt 6, Running | `407aa9ed`, attempt 6, Running | Adopted after 2 failed syncs |
| `argocd-repo-server` | `46e6528e`, attempt 5, Exited | `5b374c17`, attempt 6, Running | Never adopted, 595 failed syncs |

Both pods hit the identical attempt 6 collision. For `argocd-server` the recorded ID matched
the winner, so the kubelet adopted the running container and moved on. For `argocd-repo-server`
the recorded ID was the previous attempt, already exited and removed by the kubelet itself at
12:48:01. The kubelet therefore believed no container existed, recomputed attempt 6, and
containerd refused it because attempt 6 was running. Both sides behave correctly; the livelock
lives in the gap between them.

Why the kubelet issued the duplicate create is not established here.

## Why it did not clear itself

The kubelet reconciles containers by ID, not by name, so a container it has no ID for is
invisible to it and is never considered a match for the one it wants. The attempt index it
requests comes from the restart count, which never advanced because no container ever failed
to start. Every retry therefore asked for the same name, and the reservation for that name
belongs to a container that is running and will not be released. Retries per pod ran from 541
to 599 with no progress.

## Blast radius

Six pods, every one of them running under containerd for the whole outage: `metrics-server`
(599 failed syncs), `maxterview-backend` (597), `maxterview-frontend` (595),
`argocd-repo-server` (595), `postgres-0` (591) and `cloudflared` (541).

`postgres-0` was listening on 5432 with nine processes throughout, so the database was up and
unreachable rather than down. Its Service had no endpoints because the pod was never Ready.
On recovery it shut down cleanly on SIGTERM, `database system was shut down` with no WAL
recovery, so no data was at risk.

## Why it read as an ArgoCD failure

`argocd-repo-server` at 0/1 Ready is removed from its Service endpoints, and the application
controller cannot generate manifests without it. Every Application went `Unknown` and the
controller skipped auto-sync with `Skipping auto-sync: application status is Unknown`. None of
that chain mentions the kubelet or the container runtime.

The other five victims made it read as several unrelated faults at once: a dead database, a
dead metrics server, a dead tunnel and two dead app pods, with the tunnel and metrics symptoms
starting before the ArgoCD one. Every pod managed by ArgoCD was healthy; all six victims were
hand-installed workloads, which is why no amount of reconciliation would have fixed this.

## Journal retention

`docs/incident-2026-10-05-nodefs-disk-pressure-eviction.md` records that logs for a past
incident could not be reconstructed. The same blind spot applied here:
`journalctl --list-boots` shows a single boot, so the previous boot is gone, and a wrapped
`dmesg` ring buffer was all that remained.

The cause is that `raspberrypi-sys-mods` ships
`/usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf` setting `Storage=volatile`.
This is deliberate Raspberry Pi policy rather than a misconfiguration.

Overriding it does not work on this image. With the vendor file moved aside, `Storage=persistent`
the only active setting according to `systemd-analyze cat-config systemd/journald.conf`, and
`/var/log/journal/<machine-id>/` created and writable by root, `systemd-journald` still opened
only the runtime journal and logged no error. All changes were reverted and the node is back on
`Storage=volatile`. Do not retry this without new information. The directory's access ACL is
also malformed, carrying one named-user entry with uid `0xffffffff`; it was not established as
a cause and root writes there normally.

## Current state

The six pods were deleted, so their replacements carry new UIDs, new sandboxes and new
container names, and no reservation conflicts. All five Applications are `Synced` + `Healthy`.
Nothing was added: no reaper for stuck pods, and no journald change.

The remedy, should this recur, is to delete the pods stuck in `CreateContainerError` whose
message contains `failed to reserve container name`.

## Open

- **The duplicate `CreateContainer` is unexplained.** k3s issue #7690 carries the same error
  string, was closed as not reproducible, and is still being reported. No configuration was
  found that prevents it.
- **A k3s restart was not tried.** Whether restarting `k3s` would release the reservations is
  unverified, so it was not attempted; deleting the pods is the only remedy demonstrated here.
- **Exposure is per boot, not per deploy.** The oldest pod on the node is 76 days old and there
  are 152 deployment commits in the last 90 days, with no earlier occurrence. This one followed
  a hard stop, where containerd's metadata describes containers whose tasks are already gone.
