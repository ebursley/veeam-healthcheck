# ADR 0016: Resolve Session-Level Friendly Type via JobName Lookup with Policy-Child Prefix Matching

* **Status:** Accepted
* **Date:** 2026-05-26
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

`CJobSessionSummaryTable` renders the `jobSessionSummary` and `jobSessionSummaryByJob` JSON sections. Per-session metrics (durations, success rate, change rate, dedup ratio, sizes) come from the SQL database via `CGlobals.DtParser.JobSessions`. Each session row exposes a `JobType` field — but for *every* agent session, this field is `EEndPoint`, regardless of whether the source job was a managed `EpAgentBackup`, a managed `EpAgentPolicy`, or a standalone `EndpointBackup` job.

`CJobTypesParser.GetJobType("EEndPoint")` returns `"Endpoint Backup"`. Before this work, every agent session — managed Backup, managed Policy, standalone — collapsed under that single label in the report. The user observed: *"in the job summary, they're bundled together under 'Endpoint Backup Jobs' where they are actually 'Windows Agent Backup', 'Windows Agent Policy', and 'Windows Agent Standalone'."*

The right friendly type for each session lives in `AgentJobRecord.FriendlyType` (see [ADR 0015](0015-hybrid-friendly-type-rule.md)) — but those records are keyed by *job*, not session. We need a join.

### Why `JobId` was not used

The session-row type (`CJobSessionInfo`) carries a `JobName` field but its `JobId` semantics weren't verified to match `CBackupJob.Id`. `JobName` is the de-facto join column already used throughout the renderer (`stuff.Where(x => x.JobName == ...)` patterns in `CJobSessSummaryHelper`). Switching to `JobId` would require auditing every caller to confirm ID parity; switching to `JobName` carries no such risk.

### Policy jobs emit per-machine child sessions

Veeam policy jobs spawn one child session per protected machine. The child session's `JobName` follows the convention `<ParentJobName> - <VmFqdn>`, e.g.:

- Parent session: `Managed-WindowsAgents-Policy` (one session for the policy run)
- Child session: `Managed-WindowsAgents-Policy - vtestvm02.lab.garagecloud.net` (one per VM)

`AgentJobs` contains the parent job (`Managed-WindowsAgents-Policy`), not the child names — so an exact-match lookup against `JobName` finds the parent session but misses the child sessions.

## Considered Options

### Option A — Accept the collapse, render `EEndPoint` as a single bucket
Don't change the session-level rendering. Group `jobSessionSummaryByJob` by raw `JobType` as today.

**Cons:** Directly contradicts the user-stated goal. Defeats the purpose of [ADR 0015](0015-hybrid-friendly-type-rule.md).

### Option B — Match sessions to jobs by `JobId`
Add `JobId` to `AgentJobRecord` and key the dictionary by it.

**Pros:** Robust against naming collisions (e.g. two jobs with very similar names).
**Cons:** Requires verifying the session DTO's `JobId` matches `CBackupJob.Id` across all session families (VM, Backup Copy, Agent, …). Not yet confirmed. Larger scope.

### Option C — Exact `JobName` match only
Use `AgentJobs.ToDictionary(a => a.JobName)` and look up `session.JobName`. Fall back to `CJobTypesParser.GetJobType(rawJobType)` when not found.

**Pros:** Simple. Works for non-policy agent sessions.
**Cons:** Misses policy child sessions (always shows `"Endpoint Backup"` for them). Verified live: child session `Managed-WindowsAgents-Policy - vtestvm02.lab.garagecloud.net` falls through to the parser.

### Option D — Exact match, fall through to prefix match on `" - "`, then parser fallback (chosen)
1. Try `agentJobsByName[session.JobName]`.
2. If not found, look for the first occurrence of `" - "` (space-dash-space) in `session.JobName`. Take the substring before that delimiter as the prefix and retry the lookup.
3. If still not found, fall back to `CJobTypesParser.GetJobType(rawJobType)`.

**Pros:** Resolves both parent and child policy sessions to the same `FriendlyType`. Non-policy sessions (no `" - "` in the name) and orphaned sessions (job deleted) still fall through to the parser, preserving existing behavior. The lookup is `O(1)` per session.
**Cons:** Couples to Veeam's child-session naming convention. If Veeam ever changes the delimiter from `" - "`, child sessions revert to the parser fallback (degraded, not broken).

## Decision

Option D. The resolution logic lives in `CJobSessionSummaryTable.ResolveSessionType()`:

```csharp
private string ResolveSessionType(
    Dictionary<string, AgentJobRecord> agentJobsByName,
    string jobName,
    string rawJobType)
{
    string lookupName = jobName ?? string.Empty;
    if (agentJobsByName.TryGetValue(lookupName, out var record))
    {
        return record.FriendlyType;
    }

    // Policy jobs emit per-machine child sessions with names like
    // "<ParentJobName> - <VmFqdn>".
    const string childDelimiter = " - ";
    int delim = lookupName.IndexOf(childDelimiter, StringComparison.Ordinal);
    if (delim > 0)
    {
        string prefix = lookupName.Substring(0, delim);
        if (agentJobsByName.TryGetValue(prefix, out var parentRecord))
        {
            return parentRecord.FriendlyType;
        }
    }

    return CJobTypesParser.GetJobType(rawJobType);
}
```

`RenderByJob` additionally **regroups** sessions by the resolved `FriendlyType` (not by raw `JobType`) before iterating. This produces distinct HTML section headings — `"Windows Agent Backup Jobs"`, `"Windows Agent Policy Jobs"`, `"Windows Agent Standalone Jobs"` — instead of the prior single `"Endpoint Backup Jobs"` heading.

`RenderFlat` does not regroup; it only replaces the `JobType` column value per row.

## Rationale

- **`JobName` is the existing join key.** No new schema, no ID-parity audit. The same dictionary is reused across both render paths (`RenderFlat` HTML/JSON, `RenderByJob` HTML/JSON, plus the grouping projection).
- **Prefix matching is cheap and convention-aligned.** Veeam's per-machine session naming has been stable across major VBR versions. The fallback chain ensures that even if the convention changes, behavior degrades gracefully (back to the parser label) rather than breaking the renderer.
- **Regrouping `RenderByJob` is the linchpin fix.** The section heading is what the user actually sees in the report. Replacing per-row labels without regrouping would leave the heading saying "Endpoint Backup Jobs" while individual rows showed different types — confusing.
- **Orphan sessions stay readable.** Sessions whose parent job has been deleted (no `AgentJobs` entry) fall through to `CJobTypesParser.GetJobType("EEndPoint")` → `"Endpoint Backup"`. Not ideal, but no worse than the previous behavior and reflects the reality that the original job context is gone.

## Consequences

### Positive
- Each session row in `jobSessionSummaryByJob` shows its actual friendly type. Live verification: managed-backup sessions show `"Windows Agent Backup"`, managed-policy parent and per-machine child sessions both show `"Windows Agent Policy"`, standalone sessions show `"Windows Agent Standalone"`.
- HTML section headings in `RenderByJob` separate managed-backup, managed-policy, and standalone into distinct sections — no more single "Endpoint Backup Jobs" bucket.
- Behavior preserved for non-agent sessions (Backup, Replica, etc. — they don't match agent `AgentJobs` entries and fall through to the parser as today).

### Neutral
- Orphaned sessions (parent job deleted) still display `"Endpoint Backup"` via the fallback. Reflects ground truth — we can't recover the original job's type once it's deleted. Acceptable.
- The dictionary is rebuilt three times across the two render methods (RenderFlat HTML, RenderFlat JSON, RenderByJob). `CDataFormer.AgentJobs` is itself lazy-cached so the underlying list materializes once per `CDataFormer` instance; the `ToDictionary` calls are O(n) over a small set.

### Negative
- Coupling to Veeam's `" - "` delimiter convention. If Veeam changes it, child sessions revert to the parser fallback (visible degradation in the report, not a runtime failure). Mitigation: integration test the next time we bump the supported VBR version.
- The `RenderByJob` regrouping changes the section-iteration order — now sorted by `FriendlyType` rather than by raw enum. No downstream consumer depends on the previous ordering.

## Validation

Live VBR test produced the following `jobSessionSummaryByJob` rows from a real report run (dev VBR with one managed-backup, one managed-policy, one standalone, plus one orphaned policy session from a deleted job):

| Session JobName | Resolved JobTypes |
|---|---|
| `Managed-WindowsAgents-Job` | `Windows Agent Backup` ✅ |
| `Managed-WindowsAgents-Policy` | `Windows Agent Policy` ✅ (exact match) |
| `Managed-WindowsAgents-Policy - vtestvm02.lab.garagecloud.net` | `Windows Agent Policy` ✅ (prefix match) |
| `Unmanaged-WindowsAgents-VTESTVM03` | `Windows Agent Standalone` ✅ |
| `Managed-WindowsAgent-Policy` (singular "Agent" — deleted job) | `Endpoint Backup` (parser fallback, as expected) |
| `Total` | `Other` (parser fallback for empty `JobType`, as expected) |

527/527 unit tests pass with no regressions.

Related: [ADR 0014](0014-standalone-agent-jobs-via-getbackup-getjob.md), [ADR 0015](0015-hybrid-friendly-type-rule.md).
