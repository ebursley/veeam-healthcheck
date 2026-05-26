# ADR 0015: Hybrid Friendly-Type Resolution for Agent Jobs (TypeToString → Parser → Standalone Substitution)

* **Status:** Accepted
* **Date:** 2026-05-26
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)

## Context and Problem Statement

`CJobTypesParser.GetJobType()` is the central enum-to-display-string mapper. Before this work, three problems made it unsuitable as the sole source of friendly type labels for agent jobs:

1. **Missing cases.** The parser had no entry for `EpAgentBackup` or `EpAgentPolicy` (the `JobType` values that managed Windows-agent jobs carry in `_Jobs.csv`). Both fell through to the default branch, surfacing the raw enum name in the report. The user-facing `jobSummary` ended up with strings like `"EpAgentBackup: 1"`, `"EpAgentPolicy: 1"`.

2. **Single-enum collapse for `EEndPoint`.** Session-level `JobType` is `EEndPoint` for *both* managed Windows-agent-backup and standalone-agent sessions. A static enum→string map cannot distinguish them. The parser returned `"Endpoint Backup"` for everything, lumping managed Backup, managed Policy, and standalone sessions under one label in `jobSessionSummaryByJob`.

3. **Drift from Veeam Console.** Veeam's own UI labels these jobs `"Windows Agent Backup"`, `"Windows Agent Policy"`, `"Windows Agent Standalone"` (and Linux/Mac equivalents). Hand-maintaining that list in `CJobTypesParser` means lagging behind every Veeam SDK release.

Meanwhile, `Veeam.Backup.Core.CBackupJob` exposes a `TypeToString` property that already produces the Veeam Console label (e.g. `"Windows Agent Backup"`). The PowerShell projection in `Get-VhcJob.ps1` can carry this value into `_Jobs.csv` as a new column.

The standalone case has one extra wrinkle: `TypeToString` returns `"Windows Agent Backup"` for *both* a managed-windows-agent-backup job and a standalone job — VBR's internal naming doesn't disambiguate them via this string. The disambiguating signal is the `JobType` enum (`"EndpointBackup"` for standalone, `"EpAgentBackup"` for managed). Future agent-type additions (Linux/Mac variants, new platforms) need a rule that handles all three cases cohesively.

## Considered Options

### Option A — Centralized C# mapping
Extend `CJobTypesParser.GetJobType()` with explicit cases for every known agent `JobType` enum value, plus a separate code path that detects standalone-ness from row context.

**Pros:** Deterministic, testable, single source of truth.
**Cons:** Drifts from Veeam Console wording on every SDK release. New agent types (e.g. a future "Container Agent Backup") require a manual code update before they appear with friendly labels.

### Option B — `TypeToString` only
Pipe `TypeToString` from the VBR cmdlets into `_Jobs.csv`. Render it as-is in the report.

**Pros:** Tracks Veeam Console naming automatically.
**Cons:** Fragile — depends on the new CSV column being present in every collection. Legacy CSVs (collected before the projection change) would have an empty `TypeToString` and render blank labels. No way to distinguish managed-Backup from Standalone (both have `TypeToString = "Windows Agent Backup"`).

### Option C — Hybrid: `TypeToString` primary, parser fallback, standalone substitution (chosen)
- Use `TypeToString` from the CSV when present.
- Fall back to `CJobTypesParser.GetJobType(JobType)` when `TypeToString` is blank or absent (legacy CSVs, or rows where VBR returned empty).
- When `JobType == "EndpointBackup"`, substitute the trailing ` Backup` in the resolved label with ` Standalone` (defensive: if the label does not end in ` Backup`, append ` Standalone`).

**Pros:** Tracks Veeam Console naming when `TypeToString` is populated; deterministic fallback for legacy data; the substitution handles all platforms uniformly (`"Windows Agent Backup"` → `"Windows Agent Standalone"`, `"Linux Agent Backup"` → `"Linux Agent Standalone"`, etc.).
**Cons:** Two code paths to reason about (primary + fallback). The "Backup" suffix convention is implicit and must hold for new agent types.

## Decision

Option C. Implemented in `AgentJobAggregator.ResolveFriendlyType` and `AgentJobAggregator.ToStandaloneLabel` at `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`. The aggregator is the single owner of friendly-type resolution; all renderers consume it through the `AgentJobRecord.FriendlyType` field.

Two cases were added to `CJobTypesParser.GetJobType()` to make the fallback path produce sensible labels for the legacy-CSV scenario:

- `EpAgentBackup` → `"Windows Agent Backup"`
- `EpAgentPolicy` → `"Windows Agent Policy"`
- `EndpointBackup` → `"Agent Backup"` (paired with the substitution rule, this yields `"Agent Standalone"` for legacy standalone rows with blank `TypeToString`)

## Rationale

- **Console parity automatic, not manual.** `TypeToString` is Veeam's own canonical label. Tracking it means we get new types (Linux Agent Policy, Mac Agent Backup, future variants) without a code change.
- **Robust to legacy CSVs.** A collection captured before the projection change still renders sensibly via the parser fallback — no blank labels, no raw enum strings.
- **Standalone disambiguation lives in one rule.** The `JobType == "EndpointBackup"` check + `Backup → Standalone` substitution covers every platform without hard-coding `"Windows"` / `"Linux"` / `"Mac"` anywhere in C# or PowerShell. Veeam's `TypeToString` already carries the platform; we just transform the suffix.
- **Testable.** The aggregator is a pure function over `IEnumerable<CJobCsvInfos>`. 17 unit tests cover the primary path, fallback path, substitution for Windows/Linux/Mac, defensive fallback for non-`Backup`-ending labels, and the standalone-fallback-through-parser chain.

## Consequences

### Positive
- `jobSummary`, `jobInfo`, and `jobSessionSummaryByJob` now show Veeam-Console-aligned labels (`"Windows Agent Backup"`, `"Windows Agent Policy"`, `"Windows Agent Standalone"`).
- New agent platforms appear with correct labels automatically as soon as Veeam supports them — no code change needed.
- Removing the dual sourcing in `CJobSummaryTable` (see Task 12) is now safe: friendly buckets come from a single `GroupBy(FriendlyType)`, eliminating the prior double-count.

### Neutral
- The "Backup" suffix convention is implicit in the substitution rule. If Veeam ever introduces an agent type whose `TypeToString` does not end in `"Backup"`, the defensive fallback (`baseLabel + " Standalone"`) produces a less-clean label. Acceptable: the result is still readable.
- The fallback path uses `CJobTypesParser.GetJobType`, which lives outside the aggregator. Future maintenance must keep the parser cases in sync with the agent enum set in `AgentJobAggregator.AgentJobTypes`.

### Negative
- Two code paths to reason about. A reader must understand that `TypeToString` is primary and the parser is fallback — not interchangeable.

## Validation

- Unit tests in `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs` and `vHC/VhcXTests/Functions/Reporting/Html/DataFormers/CJobTypesParserTests.cs` cover all six combinations of (primary/fallback) × (managed/standalone) × (Windows/Linux/Mac).
- Live VBR end-to-end test confirms:
  - Managed `EpAgentBackup` row with `TypeToString="Windows Agent Backup"` → `FriendlyType="Windows Agent Backup"`.
  - Managed `EpAgentPolicy` row with `TypeToString="Windows Agent Policy"` → `FriendlyType="Windows Agent Policy"`.
  - Standalone `EndpointBackup` row with `TypeToString="Windows Agent Backup"` → `FriendlyType="Windows Agent Standalone"`.
- Verified `jobSummary` shows three distinct friendly buckets with correct counts (no double-counting), and `Total Jobs = 4` matches the actual agent-job count.

Related: [ADR 0014](0014-standalone-agent-jobs-via-getbackup-getjob.md) explains how standalone jobs are sourced so they have a `TypeToString` to feed this rule. [ADR 0016](0016-jobname-based-session-type-lookup.md) explains how the resolved `FriendlyType` is wired into session-level rendering.
