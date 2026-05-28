# ADR 0019: Session Rollup via Info.PolicyName / Info.PolicyTag

* **Status:** Accepted
* **Date:** 2026-05-27
* **Decider:** Ben Thomas (@comnam90)
* **Consulted:** Claude Code (architecture review)
* **Supersedes:** ADR 0017 (the name-prefix rollup is replaced; this ADR's machinery solves the same problem more cleanly)

## Context and Problem Statement

ADR 0017 introduced a name-prefix rollup that grouped policy per-machine child sessions
(`"<Parent> - <Vm>"` / `"<Parent>\<Vm>"`) under their parent's row by parsing the session
name. The implementation in `CJobSessSummaryHelper.TryGetParentPrefix` picked the
leftmost separator and looked the resulting prefix up in a name set. This worked for the
canonical policy job name (e.g. `Managed-WindowsAgents-Policy`) but broke whenever the
parent name itself contained " - ":

- `Physical - Linux Servers` parent with children `Physical - Linux Servers - lab01...`
  produced prefix "Physical" (not in nameSet) → no rollup → duplicate row visible.
- `Backup Copy - Engineers CHC 02` parent with children
  `Backup Copy - Engineers CHC 02\Hyper-V - Management Services` produced prefix
  "Backup Copy" (not in nameSet) → child rendered as standalone row with the wrong
  JobType label.

Each follow-up commit (974a3b7, 0a8e05f, 07b9054, b39834d, dc5e163) fixed an adjacent
edge case in the same string-parsing surface. The pattern of recurring fixes signaled
the wrong architectural anchor.

## Evidence from VBR

Live probing of `Veeam.Backup.Core.CBackupSession` and `Veeam.Backup.Core.CBackupCopySession`
objects on a v13 lab showed that every session carries two nested properties that VBR
itself uses to track the parent relationship:

- `session.Info.PolicyName` (string)
- `session.Info.PolicyTag` (Guid)

On a child session, both fields point at the **parent**: `PolicyName` = parent's
JobName, `PolicyTag` = parent's JobId. On a parent or standalone session, the fields
either equal the session's own JobName / JobId (policy parents) or are empty (regular
Backup, Backup Copy orchestrator). This holds across both session classes and across
the fast and slow collection paths (ADR 0018).

`probe-session-properties.csv` and `probe-policy-link.csv` at the repo root document
the empirical verification across all three target job families (Linux Agent policy,
Backup Copy policy, regular Hyper-V Backup). Both files are removed in Task 9 once the
ADR is committed.

## Decision

Replace the name-prefix rollup with GUID-based grouping anchored on `Info.PolicyTag`.

**Collection side** (`Get-VhcSessionReport.ps1`): for every emitted session row, write
three new columns to `VeeamSessionReport.csv`:

- `JobId` — the session's own `$session.JobId`
- `PolicyName` — `$session.Info.PolicyName`, canonicalized to the current parent name
  via the existing JobId map (same handling as `$jobName`)
- `PolicyTag` — `$session.Info.PolicyTag`

**Schema** (`CJobSessionCsvInfos.cs`): columns at indices 17/18/19, marked `[Optional]`
for backward compatibility with imported pre-this-ADR CSVs.

**Data type** (`CJobSessionInfo.cs`): three matching properties — `Guid? JobId`,
`string PolicyName`, `Guid? PolicyTag`.

**Rollup** (`CSessionGroupKey.Of`): preference order

1. `PolicyTag` when populated and not equal to own `JobId` → child rolls up under
   the parent's job GUID.
2. `JobId` when populated → parent / standalone uses its own GUID.
3. Fall back to `name:<JobName>` for legacy CSVs without the new columns.

**Display name** (`CSessionGroupKey.DisplayName`): `PolicyName` if non-empty, else
`JobName`. The parent name flows through naturally because children carry the parent's
PolicyName.

`CJobSessSummary.JobSessionSummaryToXml` and `IndividualJobSessionsHelper.ParseIndividualSessions`
group sessions by `CSessionGroupKey.Of`. The previous parent/child detection,
`namesWithData` guard, algorithm-suffix stripping, and longest-prefix retry logic are
all deleted.

## Rationale

- **No string parsing.** Parent identity comes from a typed VBR property, not a
  delimiter convention. Parent names containing " - " or `\` no longer matter.
- **Stable across renames.** `PolicyTag` is a GUID; renaming the parent job doesn't
  change historical sessions' grouping. The display name picks up the canonical
  current name via the PS-layer `$jobIdMap` override.
- **Two session classes, two paths, same property.** Verified on
  `Veeam.Backup.Core.CBackupSession` (fast path) and `Veeam.Backup.Core.CBackupCopySession`
  (slow path BC). The collection layer doesn't need different rollup logic per path.
- **One fallback only.** `JobName` is used solely when neither GUID is populated
  (legacy imported CSVs). New collections never hit the fallback.
- **Smaller surface to maintain.** ~150 lines deleted; ~50 lines added.

## Consequences

### Positive
- Duplicate rows for parent-name-contains-" - " policies (Linux Agent, Backup Copy)
  disappear without a special case.
- Backup Copy child rows are absorbed into the parent and rendered with the parent's
  "Backup Copy" type from `_Jobs.csv` (no manual `parentToChildren.ContainsKey` check).
- Renamed jobs no longer produce two rows in `jobSessionSummary` — the GUID is the
  anchor, the name is just display.

### Neutral
- Imported CSVs from prior versions (no `JobId`/`PolicyName`/`PolicyTag` columns) fall
  back to grouping by `JobName`. Per-machine children show as separate rows in that
  fallback, the same as they did before the original ADR 0017 rollup landed. Acceptable
  because re-collection on the upgraded module restores correct grouping.

### Negative
- Couples session rollup to two VBR `Info` properties. Mitigated by the `[Optional]`
  CSV columns and the GUID-or-name fallback chain.

## Validation

Unit tests (`CSessionGroupKeyTEST`, two new cases in `CJobSessSummaryTEST`) cover:

- Linux Agent parent + 2 children → single rolled-up row.
- Hyper-V no-children Backup → single standalone row.
- BC parent with empty PolicyTag → uses own JobId.
- Legacy session (all GUIDs null) → falls back to JobName.
- DisplayName precedence.

End-to-end verification by re-running the report against the user's lab VBR and
confirming `jobSessionSummaryByJob.Rows` no longer contains the `Physical - Linux Servers - lab-m01-lnx01... (Incremental/Synthetic Full)` rows beside the parent.

## Related

- **ADR 0017** — predecessor, name-prefix rollup. Superseded.
- **ADR 0018** — fast-path session collection. Provides the same `Info.PolicyName`/`PolicyTag`
  property visibility on both paths.
- **ADR 0016** — `JobName`-based session-type lookup. The `" - "` convention used there
  is no longer load-bearing for rollup, but still used for friendly-type resolution.
