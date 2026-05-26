# ADR 0017: Roll Up Policy Per-VM Child Sessions Into Parent Row in jobSessionSummary

* **Status:** Accepted
* **Date:** 2026-05-27
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

Veeam policy jobs emit two kinds of session records to the VBR session database for every run:

1. An **orchestrator session** with `Name = "<ParentJobName>"`, short duration, zero `DataSize` / `BackupSize`. This is the scheduler / dispatch / finalization wrapper.
2. One or more **per-machine child sessions** with `Name = "<ParentJobName> - <VmFqdn>"`, long duration, populated sizes/dedup/compress ratios. This is where the actual backup work happens.

`CJobSessSummaryHelper.JobNameList()` returns distinct `session.Name` values, and `CJobSessSummary.JobSessionSummaryToXml()` iterates them producing one `CJobSummaryTypes` row per name. Two problems followed:

### Problem 1 — visible duplication in jobSessionSummary

For a policy that ran in the window, the report rendered **two rows** that meant one logical job:

| JobName | SessionCount | AvgBackupSize | MaxData | Dedup |
|---|---|---|---|---|
| `Managed-WindowsAgents-Policy` (orchestrator) | 2 | 0 | 0 | — |
| `Managed-WindowsAgents-Policy - vtestvm02.lab.garagecloud.net` (child) | 1 | 0.0169 | 0.0781 | 2.86x |

The orchestrator row's all-zero metrics misled readers. The child's `<Parent> - <Vm>` row didn't align with `jobInfo`, which already presents one row per managed policy.

### Problem 2 — latent `AvgChangeRate` denominator bug

`CJobSessSummary.JobSessionSummaryToXml` computes `info.UsedVmSizeTB` by looking up `j` (the row's JobName) in `_Jobs.csv`:

```csharp
var jobInfo = csv.JobCsvParser().Where(x => x.Name == j).FirstOrDefault();
if (jobInfo != null) info.UsedVmSizeTB = jobInfo.OriginalSize / 1024 / 1024 / 1024 / 1024;
```

For a child row, `j = "<Parent> - <VmFqdn>"`. That name does **not** exist in `_Jobs.csv` (which holds parent jobs only), so the lookup misses and `UsedVmSizeTB` stays at 0. The AvgChangeRate fallback then divides by `MaxDataSize` instead:

```csharp
if (avgIncrDataTB > 0 && info.UsedVmSizeTB > 0)
    info.AvgChangeRate = Math.Round(avgIncrDataTB / info.UsedVmSizeTB * 100, 2);
else if (avgIncrDataTB > 0 && info.MaxDataSize > 0)
    info.AvgChangeRate = Math.Round(avgIncrDataTB / info.MaxDataSize * 100, 2);  // wrong denominator
```

`MaxDataSize` is the largest full-backup data size seen in the window — not the source VM size — so the ratio is meaningless. The bug stayed latent only because `avgIncrDataTB` happened to be 0 on the test dataset; it would surface as soon as any policy ran an incremental.

Both problems share the same root cause: the helper treats parent and child as independent jobs.

## Considered Options

### Option A — Hide child rows at the renderer

Filter `<Parent> - <Vm>` rows out of `CJobSessionSummaryTable`. Quick to implement, fixes the duplication.

**Cons:** The parent's all-zero orchestrator row is still rendered (misleading). The `AvgChangeRate` denominator bug is unchanged because the renderer doesn't recompute the math — the wrong value is already baked into the child's `CJobSummaryTypes` and dropping the row just hides the result. The data also stays wrong in the JSON capture if a consumer reads from there.

### Option B — Roll up at the renderer

Post-process `CJobSummaryTypes` rows in `CJobSessionSummaryTable` to merge parent + children into a single row. Recompute aggregates from the per-row values.

**Cons:** Same `AvgChangeRate` problem as Option A — the children's already-computed `AvgChangeRate` carries the wrong denominator, and the renderer can't recompute correctly without access to raw incremental data sizes (which only `SessionStats` sees). Also, simple averaging across parent + children dilutes results because the parent's zero-data sessions enter as weight-zero entries that still affect simple averages of dedup/compress ratios.

### Option C — Roll up at the source (chosen)

Modify `CJobSessSummary.JobSessionSummaryToXml` to detect parent/child pairs by `" - "` prefix match (consistent with ADR 0016's session-type lookup), then for each parent that has children: aggregate **only the children's sessions** under the parent's name and skip the orchestrator's no-data sessions entirely. Drop the children's rows from output. Add a `SessionStats(IEnumerable<string>)` overload to the helper so the aggregation can span multiple names.

**Pros:**
- Single row per policy, matching `jobInfo`.
- `AvgChangeRate` math becomes correct automatically because the row's identity is the parent name, so `_Jobs.csv` lookup populates `UsedVmSizeTB` correctly and the children's `IncrementalDataSize` is divided by the parent's source size.
- Orchestrator sessions (which have no useful data) never enter the aggregation, so averages of sizes / dedup / compress reflect actual work.
- One change point benefits all four downstream paths: `RenderFlat` HTML, `RenderFlat` JSON (`jobSessionSummary`), `RenderByJob` HTML, `RenderByJob` JSON (`jobSessionSummaryByJob`).

**Cons:** More invasive than Options A and B — modifies the helper's API surface and the source-side iteration logic. Also creates an implicit dependency on Veeam's `" - "` delimiter convention (already established as a convention in ADR 0016).

## Decision

Option C. Implemented in `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummary.cs` and `CJobSessSummaryHelper.cs`:

```csharp
// CJobSessSummaryHelper.cs
public SessionStats SessionStats(string jobName)
{
    return this.SessionStats(new[] { jobName });
}

public SessionStats SessionStats(IEnumerable<string> jobNames)
{
    var names = new HashSet<string>(jobNames ?? Array.Empty<string>(), StringComparer.Ordinal);
    SessionStats stats = new SessionStats();
    if (names.Count == 0) return stats;

    foreach (var session in this.JobSessionInfoList())
    {
        double diff = (DateTime.Now - session.CreationTime).TotalDays;
        if (names.Contains(session.Name) && diff < CGlobals.ReportDays)
        {
            // ... unchanged accumulation logic
        }
    }
    return stats;
}
```

```csharp
// CJobSessSummary.JobSessionSummaryToXml — parent/child detection + selective aggregation
var allNames = helper.JobNameList().Distinct().ToList();
var nameSet = new HashSet<string>(allNames.Where(n => n != null), StringComparer.Ordinal);
var parentToChildren = new Dictionary<string, List<string>>(StringComparer.Ordinal);
var childNames = new HashSet<string>(StringComparer.Ordinal);
foreach (var name in allNames)
{
    if (name == null) continue;
    int delim = name.IndexOf(" - ", StringComparison.Ordinal);
    if (delim <= 0) continue;
    var prefix = name.Substring(0, delim);
    if (!nameSet.Contains(prefix)) continue;
    childNames.Add(name);
    if (!parentToChildren.TryGetValue(prefix, out var list))
    {
        list = new List<string>();
        parentToChildren[prefix] = list;
    }
    list.Add(name);
}

foreach (var j in allNames)
{
    if (childNames.Contains(j)) continue;  // child rows are absorbed into parent

    // For parents with children, aggregate only the children's sessions.
    // For orphan parents and standalone jobs, aggregate the row's own sessions.
    var namesToAggregate = parentToChildren.TryGetValue(j, out var children) && children.Count > 0
        ? (IEnumerable<string>)children
        : new[] { j };
    SessionStats thisSession = helper.SessionStats(namesToAggregate);
    // ... rest of per-row logic unchanged; `j` remains the parent name for _Jobs.csv lookup
}
```

Orphan parents — a parent name with no children visible in the window, e.g. a deleted job whose orchestrator sessions still appear within `ReportDays` — keep their existing per-name row so visibility of the orphan isn't lost.

## Rationale

- **Aggregate where the raw session data lives.** `SessionStats` already iterates the raw `CGlobals.DtParser.JobSessions` list, so extending it to filter by a set of names is a one-line change that gives the rollup loop access to every session attribute (DataSize, IncrementalDataSize, dedup/compress raw values). Doing the rollup at the renderer would force a separate aggregation path that re-derives these from per-row averages — more code and less accurate.
- **Skipping orchestrator sessions matches their meaning.** Orchestrator sessions are scheduling wrappers, not work units. Including them in size/duration averages would mean "average across N runs including the no-op wrappers" — not useful to a reader. Including them in `SessionCount` would inflate the run count.
- **Parent name as row identity is the right anchor.** `_Jobs.csv` is keyed by parent name. The `AvgChangeRate` calculation needs `UsedVmSizeTB`, which only the parent's `_Jobs.csv` entry provides. Keeping the row identity as the parent name makes that lookup succeed without further changes.
- **Consistency with the friendly-type lookup pattern.** ADR 0016 already established the `" - "` prefix-match convention for resolving session-level FriendlyType. This change reuses the same convention — same parser, same delimiter, same fallback semantics. A future maintainer reading either ADR sees the convention is consistent.

## Consequences

### Positive
- One row per managed policy in `jobSessionSummary` and `jobSessionSummaryByJob`, matching `jobInfo`'s row count.
- `AvgChangeRate` divides children's incremental data by the parent's source-VM size — the mathematically correct ratio.
- Reduced reader confusion: no more all-zero "policy" rows next to a populated `<Parent> - <Vm>` row.
- Total `SessionCount` no longer counts orchestrator wrappers. Verified live: dropped from 6 to 5 on the dev VBR (excluded two orchestrator sessions from `Managed-WindowsAgents-Policy`).

### Neutral
- Orphan parents (deleted jobs with lingering orchestrator sessions) still display the orchestrator's all-zero metrics. Acceptable because there are no children to roll up and dropping the orphan would lose visibility of stale state.
- Couples session aggregation to Veeam's `" - "` delimiter convention (same coupling already accepted by ADR 0016).
- A policy job that ran but produced no per-VM sessions in the window (zero protected machines, or all machines excluded) will render as an orphan-style parent row with the orchestrator's zero data. Indistinguishable from a deleted job at that point; both should be rare.

### Negative
- The aggregation set excludes orchestrator sessions, so `SessionCount` reflects the number of per-VM backup attempts rather than the number of policy invocations. A user expecting "how many times did the policy fire?" may need to look elsewhere (event log, parent session count in raw DB). The rendered metric is arguably more useful operationally but worth flagging.

## Validation

Live testing on dev VBR after the change:

- `jobSessionSummaryByJob` for `Managed-WindowsAgents-Policy` shows `SessionCount=1`, `AvgBackupSize=0.0169`, `MaxBackupSize=0.0169`, `MaxDataSize=0.0781`, `AvgDedupRatio=2.86x` — these are the child session's actual values, now correctly attributed to the parent name. Prior output: `SessionCount=2`, all sizes/ratios zero.
- The `Managed-WindowsAgents-Policy - vtestvm02.lab.garagecloud.net` row that previously sat alongside the parent is gone.
- `Total` SessionCount dropped from 6 to 5, reflecting that the two orchestrator sessions are no longer counted.
- `Unmanaged-WindowsAgents-VTESTVM03` (standalone, no children — exercises the "standalone job" code path) renders unchanged with `AvgChangeRate=4.34%` confirming the calculation works through `_Jobs.csv`'s source size correctly.
- `Managed-WindowsAgent-Policy` (singular "Agent" — a deleted job whose orchestrator sessions persist with no children in the window) renders as an orphan parent row, unchanged behavior.
- All 527 unit tests pass.

Related: [ADR 0016](0016-jobname-based-session-type-lookup.md) — same `" - "` convention used to resolve session FriendlyType in the renderer. [ADR 0015](0015-hybrid-friendly-type-rule.md) — the FriendlyType produced for the rolled-up row.
