# Nodefs Disk Pressure: 10 hours of eviction, read as a network fault (2026-10-05)

> Root cause for the episode that surfaced as "ArgoCD keeps crashing", a missing PreSync
> hook, and pods vanishing. No data loss. All times are node-local (UTC+08:00); the node
> reports them as `PST` but the offset is +08:00.

## Summary

The k3s node ran out of room on nodefs. The kubelet entered ephemeral-storage eviction at
2026-10-05 07:52 and evicted 359 to 360 pods per hour, one every ten seconds, for ten hours.
It never cleared, because the space was held by something kubelet cannot delete, so its
reclaim loop had nothing to reclaim. Two `systemctl restart k3s` interrupted the loop without
freeing a byte. The cluster went fully dead at 2026-10-06 05:47 and recovered only when 24G
was deleted from `~/.pi/agent/ayu/checkpoints/sessions`.

## Timeline

| When (local) | Event |
| --- | --- |
| 10-05 07:52 | First ephemeral-storage eviction. Sustained 359 to 360/hour until 17:00 |
| 10-05 18:01:42 | `systemctl restart k3s`, loop stops |
| 10-05 20:13:10 | Second `systemctl restart k3s`, loop stops again |
| 10-06 05:47:36 | Pressure returns with only critical pods left, so the kubelet loops on `cannot evict a critical pod` every 10s |
| 10-06 06:00:37 | 24G deleted. Condition clears after `evictionPressureTransitionPeriod` (5m) |

## Root cause

`~/.pi/agent/ayu/checkpoints/sessions` held 24G: one git repo per agent session, written by
the `@ayulab/pi-rewind` extension, which does not garbage-collect by design. nodefs is a
single 58G filesystem shared with the kubelet and everything else on the host. Usage reached
87%, leaving 7.6G free.

## Why it could not clear itself

The kubelet only evicts pods it manages, and every pod that could be evicted had already
been evicted by hour one. From then on it had only its own critical pods in the ranking,
which it refuses to kill, so the loop repeated with nothing to do. Meanwhile the
`node.kubernetes.io/disk-pressure:NoSchedule` taint blocked every replacement pod from
scheduling. New pods pending plus old pods evicted is the whole outage.

## Thresholds that made this opaque

| Setting | Value | Effect |
| --- | --- | --- |
| `evictionHard.nodefs.available` | 5% | Trigger, about 2.9G free on this disk |
| `evictionMinimumReclaim.nodefs.available` | 10% | Kubelet keeps reclaiming to about 8.8G (15% total) |
| `evictionPressureTransitionPeriod` | 5m | How long pressure must ease before the condition clears |

The danger line is therefore around 85% used, not 100%. Observed confirmation: at 05:47 the
kubelet evicted while `available: 3265548Ki` sat above the 5% trigger of
`3087226311`, which is the reclaim floor doing the work.

## Why it read as a network or ArgoCD failure

- The taint blocks scheduling, so ArgoCD components go Pending, then `ErrImagePull`, then
  `OutOfSync` and `Degraded`. Nothing in that chain mentions disk.
- Mass rescheduling makes 15+ pods pull at once, so the kubelet reports `ErrImagePull: pull
  QPS exceeded`, which reads as a registry or network fault.
- `maxterview-migrate` was evicted twice. The kubelet ranks pods by usage against requests,
  and this Job declares none, so it goes first. Its `hook-delete-policy: BeforeHookCreation`
  then removes the Job before the next sync attempt, so the hook appears to have "gone
  missing" on its own.
- No network fault appears in the journal. The only nearby network errors are the CoreDNS
  SERVFAIL for external names, a separate pre-existing issue.

## What a k3s restart does not do

Restarting k3s restarts the kubelet, which drops the `DiskPressure` condition and its taint,
so pods schedule normally again. It frees no nodefs space. Recovery is temporary by
construction: the disk refills and the loop returns, which is exactly the 07:52, 18:01 and
20:13 pattern above.

## Current state

Fixed by deleting the checkpoint store and bounding the workloads:
`gitops` commit `3e39a1b` adds a `LimitRange` for ephemeral storage to every app namespace
and a `sizeLimit` on the Alloy WAL volume; `ayu.checkpoint.maxFileMB` and checkpoint excludes
are set in `~/.pi/agent/settings.json`.

## Open

- **No alerting exists for this host.** Nothing watches disk or memory, so the outage was
  found by noticing the site was down, ten hours after it started. Disk, `MemAvailable` and
  ArgoCD sync health are the three signals worth having.
- **The Minecraft server holds a 3G heap on the same 8G box as production**, with no swap
  active and roughly 1.7G free. A memory spike reproduces this outage through
  `MemoryPressure` and the same taint mechanism.
- **Journal retention.** Logs for this incident begin 10-04 14:11, so the days before it
  cannot be reconstructed. Any future postmortem has the same blind spot.
