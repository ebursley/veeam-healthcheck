# Agent Jobs — Managed and Standalone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make standalone (unmanaged) Veeam Agent jobs appear in the report's `jobInfo` with full sizing/configuration, and replace the "Endpoint Backup" / raw-enum collapse in `jobSummary` and `jobSessionSummaryByJob` with friendly per-type labels ("Windows Agent Backup", "Windows Agent Policy", "Windows Agent Standalone", and Linux/Mac equivalents).

**Architecture:** Add `TypeToString` to the `_Jobs.csv` projection in PowerShell and append standalone jobs (via `Get-VBRBackup | ?{IsAgentStandaloneJob} | .GetJob()`) to the existing iteration set so they flow through the same `CBackupJob` projection as managed jobs. In C#, introduce a small `AgentJobRecord` + `AgentJobAggregator` pair that reads `_Jobs.csv`, filters to agent job types, and resolves a `FriendlyType` using `TypeToString` (primary) with `CJobTypesParser` fallback; standalone rows derive `"… Standalone"` via a "Backup" → "Standalone" substitution. `CDataFormer` exposes `AgentJobs`. The three renderers (`CJobInfoTable`, `CJobSummaryTable`, `CJobSessionSummaryTable`) consume it.

**Tech Stack:** .NET 8.0 (Windows-only build), WPF, PowerShell 7 SDK, CsvHelper, xUnit + Moq.

**Spec:** `docs/superpowers/specs/2026-05-26-agent-jobs-managed-standalone-design.md` (committed on this branch).

**Upstream tracking issue:** VeeamHub/veeam-healthcheck#148.

---

## File structure

### New files

- `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobRecord.cs` — POCO carrying the normalized fields for one agent job (managed or standalone). One responsibility: shape of an agent job for downstream renderers.
- `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs` — static aggregator. One responsibility: turn `IEnumerable<CJobCsvInfos>` into `IReadOnlyList<AgentJobRecord>`, filtered to agent types, with `FriendlyType` resolved.
- `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs` — xUnit tests for the aggregator.
- `vHC/VhcXTests/Functions/Reporting/Html/DataFormers/CJobTypesParserTests.cs` — xUnit tests for the new parser cases.

### Modified files

- `vHC/HC_Reporting/Functions/Reporting/CsvHandlers/CJobCsvInfos.cs` — add `TypeToString` field at `[Index(43)]` with `[Optional]`.
- `vHC/HC_Reporting/Functions/Reporting/Html/DataFormers/CJobTypesParser.cs` — add `EpAgentBackup` → `"Windows Agent Backup"` and `EpAgentPolicy` → `"Windows Agent Policy"` cases.
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcJob.ps1` — append standalone jobs via `Get-VBRBackup | ?{IsAgentStandaloneJob} | .GetJob()`; add `TypeToString` to the projection.
- `vHC/HC_Reporting/Functions/Reporting/Html/CDataFormer.cs` — add `AgentJobs` property (lazy-cached, sourced from `AgentJobAggregator.Build`).
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobInfoTable.cs` — JSON capture loop uses `AgentJobs.FriendlyType` by `JobName` for agent rows; non-agent rows continue using `CJobTypesParser`.
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/CJobSummaryTable.cs` — drop the unconditional `"Agent Backup"` (from `_AgentBackupJob.csv`) and `"Unmanaged Agent"` (from `_EndpointJob.csv`) bucket adds; count agent buckets from `CDataFormer.AgentJobs.GroupBy(FriendlyType)`.
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobSessionSummaryTable.cs` — at the two `CJobTypesParser.GetJobType(stu.JobType)` call sites (lines 68 and 117), first look up the session's `JobName` in `CDataFormer.AgentJobs`; use its `FriendlyType` when matched, fall back to `CJobTypesParser.GetJobType()` otherwise.

---

## Conventions

- **TDD:** write failing test → verify failure → minimal implementation → verify pass → commit.
- **Test naming:** `[MethodUnderTest]_[Scenario]_[ExpectedBehavior]` (per CLAUDE.md).
- **Test runner:** `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~<ClassName>.<MethodName>"`.
- **Build:** `dotnet build vHC/HC.sln --configuration Debug`. Tests only compile on Windows.
- **Branch:** all work commits to `feature/agent-jobs-managed-standalone` (already created, tracking `origin/dev`).
- **Commits:** create a commit per task unless explicitly noted otherwise. Commit messages follow the existing convention (`fix(...)`, `feat(...)`, `test(...)`).

---

## Task 1: Add `TypeToString` field to `CJobCsvInfos`

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/CsvHandlers/CJobCsvInfos.cs:147` (append a new property after the existing `Platform` at `[Index(42)]`)

This unlocks the rest of the work: the new PowerShell column is harmless on old C# (CsvHelper ignores extra columns), but new C# without the property would fail to read the column. Adding the field first lets the aggregator tests in subsequent tasks have a place to set `TypeToString` on in-memory `CJobCsvInfos` instances.

- [ ] **Step 1.1: Add the property to `CJobCsvInfos`**

Insert immediately after the existing `Platform` property (line 147):

```csharp
        [Index(43)]
        [Optional]
        public string TypeToString { get; set; }
```

- [ ] **Step 1.2: Build to verify the change compiles**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: build succeeds with no new warnings related to this file.

- [ ] **Step 1.3: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/CsvHandlers/CJobCsvInfos.cs
git commit -m "feat(csv): add TypeToString column to CJobCsvInfos

Reads the Veeam-supplied human-readable job type label from _Jobs.csv,
matching the upcoming PowerShell projection change. Optional + last
index means existing CSVs without the column still parse cleanly."
```

---

## Task 2: Add `EpAgentBackup` and `EpAgentPolicy` cases to `CJobTypesParser`

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/DataFormers/CJobTypesParser.cs:22-78`
- Create: `vHC/VhcXTests/Functions/Reporting/Html/DataFormers/CJobTypesParserTests.cs`

These cases serve as the fallback when `TypeToString` is blank (legacy CSVs collected before Task 10's PowerShell change, or jobs where VBR returns empty for the property). The aggregator depends on them in Task 6.

- [ ] **Step 2.1: Write failing tests for the two new cases**

Create `vHC/VhcXTests/Functions/Reporting/Html/DataFormers/CJobTypesParserTests.cs`:

```csharp
using VeeamHealthCheck.Functions.Reporting.Html.DataFormers;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.DataFormers
{
    [Trait("Category", "JobTypes")]
    public class CJobTypesParserTests
    {
        [Fact]
        public void GetJobType_EpAgentBackup_ReturnsWindowsAgentBackup()
        {
            var result = CJobTypesParser.GetJobType("EpAgentBackup");
            Assert.Equal("Windows Agent Backup", result);
        }

        [Fact]
        public void GetJobType_EpAgentPolicy_ReturnsWindowsAgentPolicy()
        {
            var result = CJobTypesParser.GetJobType("EpAgentPolicy");
            Assert.Equal("Windows Agent Policy", result);
        }

        [Fact]
        public void GetJobType_NullInput_ReturnsOther()
        {
            var result = CJobTypesParser.GetJobType(null);
            Assert.Equal("Other", result);
        }

        [Fact]
        public void GetJobType_UnknownType_ReturnsInputAsIs()
        {
            var result = CJobTypesParser.GetJobType("UnknownType123");
            Assert.Equal("UnknownType123", result);
        }
    }
}
```

- [ ] **Step 2.2: Run the tests to verify they fail on the two new cases**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~CJobTypesParserTests"`
Expected: `GetJobType_EpAgentBackup_ReturnsWindowsAgentBackup` and `GetJobType_EpAgentPolicy_ReturnsWindowsAgentPolicy` FAIL (each currently returns the raw input via the default branch). The `Null` and `UnknownType` tests should pass even before the change.

- [ ] **Step 2.3: Add the two new cases to `CJobTypesParser`**

In `vHC/HC_Reporting/Functions/Reporting/Html/DataFormers/CJobTypesParser.cs`, inside the `switch (jobType)` block, immediately before the existing `case "EpAgentManagement":` line (around line 64):

```csharp
                case "EpAgentBackup":
                    return "Windows Agent Backup";
                case "EpAgentPolicy":
                    return "Windows Agent Policy";
```

- [ ] **Step 2.4: Run the tests to verify they now pass**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~CJobTypesParserTests"`
Expected: all four tests PASS.

- [ ] **Step 2.5: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/Html/DataFormers/CJobTypesParser.cs vHC/VhcXTests/Functions/Reporting/Html/DataFormers/CJobTypesParserTests.cs
git commit -m "feat(parser): map EpAgentBackup/EpAgentPolicy to friendly names

Adds Windows Agent Backup and Windows Agent Policy as the fallback
when TypeToString is unavailable on a job row. Includes unit tests."
```

---

## Task 3: Create `AgentJobRecord` POCO

**Files:**
- Create: `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobRecord.cs`

Simple data carrier. No tests for the type itself; behavior is tested via the aggregator in Tasks 4–9.

- [ ] **Step 3.1: Create the record file**

```csharp
namespace VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs
{
    /// <summary>
    /// Normalized view of a single Veeam Agent job (managed or standalone)
    /// for the report renderers. Produced by AgentJobAggregator.
    /// </summary>
    public class AgentJobRecord
    {
        public string JobName { get; set; }
        public string JobType { get; set; }
        public string FriendlyType { get; set; }
        public string RepoName { get; set; }
        public double SourceSizeGB { get; set; }
        public double OnDiskGB { get; set; }
        public string RetentionScheme { get; set; }
        public string RetainDays { get; set; }
        public string Encrypted { get; set; }
        public string CompressionLevel { get; set; }
        public string BlockSize { get; set; }
        public bool GfsEnabled { get; set; }
        public string GfsDetails { get; set; }
        public string ActiveFullEnabled { get; set; }
        public bool SyntheticFullEnabled { get; set; }
        public string BackupChainType { get; set; }
        public bool IndexingEnabled { get; set; }
        public string AAIPEnabled { get; set; }
        public string VSSEnabled { get; set; }
        public string VSSIgnoreErrors { get; set; }
        public string GuestFSIndexing { get; set; }
        public string Platform { get; set; }
    }
}
```

- [ ] **Step 3.2: Build to verify**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: build succeeds.

- [ ] **Step 3.3: Commit (deferred — combined with Task 4 commit to land aggregator + record together)**

No commit yet; the record makes no sense on its own. Stage the file and continue.

```bash
git add vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobRecord.cs
```

---

## Task 4: `AgentJobAggregator.Build` — filter to agent rows only

**Files:**
- Create: `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`
- Create: `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs`

Set up the aggregator skeleton and the first test: only rows whose `JobType` is in the agent set survive.

- [ ] **Step 4.1: Write the failing test**

Create `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs`:

```csharp
using System.Collections.Generic;
using System.Linq;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs;
using Xunit;

namespace VhcXTests.Functions.Reporting.DataFormers.AgentJobs
{
    [Trait("Category", "AgentJobs")]
    public class AgentJobAggregatorTests
    {
        [Fact]
        public void Build_NonAgentJobType_FiltersOut()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "VM-Backup-01", JobType = "Backup" },
                new() { Name = "VM-Replica-01", JobType = "Replica" },
                new() { Name = "Win-Agent-01", JobType = "EpAgentBackup", TypeToString = "Windows Agent Backup" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Single(result);
            Assert.Equal("Win-Agent-01", result[0].JobName);
        }
    }
}
```

- [ ] **Step 4.2: Run to verify it fails to compile (AgentJobAggregator doesn't exist yet)**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests"`
Expected: compile error — `AgentJobAggregator` is not defined.

- [ ] **Step 4.3: Implement the minimum aggregator skeleton**

Create `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`:

```csharp
using System.Collections.Generic;
using System.Linq;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;

namespace VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs
{
    /// <summary>
    /// Filters _Jobs.csv rows down to Veeam Agent jobs (managed and standalone)
    /// and resolves a human-readable FriendlyType for each.
    /// </summary>
    public static class AgentJobAggregator
    {
        private static readonly HashSet<string> AgentJobTypes = new()
        {
            "EpAgentBackup",
            "EpAgentPolicy",
            "EpAgentManagement",
            "ELinuxPhysical",
            "EndpointBackup",
        };

        public static IReadOnlyList<AgentJobRecord> Build(IEnumerable<CJobCsvInfos> rows)
        {
            if (rows == null)
            {
                return new List<AgentJobRecord>();
            }

            return rows
                .Where(r => r != null && r.JobType != null && AgentJobTypes.Contains(r.JobType))
                .Select(r => new AgentJobRecord
                {
                    JobName = r.Name,
                    JobType = r.JobType,
                })
                .ToList();
        }
    }
}
```

- [ ] **Step 4.4: Run the test to verify it passes**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_NonAgentJobType_FiltersOut"`
Expected: PASS.

- [ ] **Step 4.5: Commit (aggregator skeleton + record)**

```bash
git add vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/ vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/
git commit -m "feat(agent-jobs): add AgentJobRecord and AgentJobAggregator skeleton

Filters _Jobs.csv rows to the agent job-type set
(EpAgentBackup, EpAgentPolicy, EpAgentManagement, ELinuxPhysical,
EndpointBackup). Friendly-type resolution and field mapping land in
follow-up commits."
```

---

## Task 5: `FriendlyType` from `TypeToString` for managed agents

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`
- Modify: `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs`

When `TypeToString` is populated on a managed agent row, use it as `FriendlyType`.

- [ ] **Step 5.1: Add a failing test**

Append to `AgentJobAggregatorTests.cs` (inside the class):

```csharp
        [Fact]
        public void Build_ManagedAgentWithTypeToString_UsesTypeToString()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "Win-Agent-01", JobType = "EpAgentBackup", TypeToString = "Windows Agent Backup" },
                new() { Name = "Lin-Policy-01", JobType = "EpAgentPolicy", TypeToString = "Linux Agent Policy" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Equal("Windows Agent Backup", result.First(r => r.JobName == "Win-Agent-01").FriendlyType);
            Assert.Equal("Linux Agent Policy", result.First(r => r.JobName == "Lin-Policy-01").FriendlyType);
        }
```

- [ ] **Step 5.2: Run to verify it fails**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_ManagedAgentWithTypeToString_UsesTypeToString"`
Expected: FAIL — `FriendlyType` is null because the implementation doesn't set it.

- [ ] **Step 5.3: Implement `FriendlyType` resolution**

In `AgentJobAggregator.cs`, replace the `Select(r => new AgentJobRecord { JobName = r.Name, JobType = r.JobType })` block with:

```csharp
                .Select(r => new AgentJobRecord
                {
                    JobName = r.Name,
                    JobType = r.JobType,
                    FriendlyType = ResolveFriendlyType(r),
                })
```

Add the helper method to the class (after `Build`):

```csharp
        private static string ResolveFriendlyType(CJobCsvInfos row)
        {
            if (!string.IsNullOrEmpty(row.TypeToString))
            {
                return row.TypeToString;
            }

            // Fallback added in later steps.
            return row.TypeToString;
        }
```

Note: the fallback is still a stub; Task 6 implements it. Don't add `using` for `CJobTypesParser` yet.

- [ ] **Step 5.4: Run the test to verify it passes**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_ManagedAgentWithTypeToString_UsesTypeToString"`
Expected: PASS.

- [ ] **Step 5.5: Run the full test class to confirm no regression**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests"`
Expected: both tests pass.

No commit yet — Task 6 lands together.

---

## Task 6: `FriendlyType` falls back to `CJobTypesParser` when `TypeToString` is blank

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`
- Modify: `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs`

This is the hybrid rule's fallback leg, exercised when the PowerShell collection predates the `TypeToString` projection or the cmdlet returned blank.

- [ ] **Step 6.1: Add a failing test**

Append to `AgentJobAggregatorTests.cs`:

```csharp
        [Fact]
        public void Build_ManagedAgentMissingTypeToString_FallsBackToParser()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "Legacy-Agent-01", JobType = "EpAgentBackup", TypeToString = null },
                new() { Name = "Legacy-Agent-02", JobType = "EpAgentPolicy", TypeToString = "" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Equal("Windows Agent Backup", result.First(r => r.JobName == "Legacy-Agent-01").FriendlyType);
            Assert.Equal("Windows Agent Policy", result.First(r => r.JobName == "Legacy-Agent-02").FriendlyType);
        }
```

- [ ] **Step 6.2: Run to verify it fails**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_ManagedAgentMissingTypeToString_FallsBackToParser"`
Expected: FAIL — `FriendlyType` is null/empty because the stub fallback returns the same blank value.

- [ ] **Step 6.3: Implement the parser fallback**

In `AgentJobAggregator.cs`, add the using and replace the stub fallback:

```csharp
using VeeamHealthCheck.Functions.Reporting.Html.DataFormers;
```

Replace the `ResolveFriendlyType` body:

```csharp
        private static string ResolveFriendlyType(CJobCsvInfos row)
        {
            if (!string.IsNullOrEmpty(row.TypeToString))
            {
                return row.TypeToString;
            }

            return CJobTypesParser.GetJobType(row.JobType);
        }
```

- [ ] **Step 6.4: Run the test to verify it passes**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_ManagedAgentMissingTypeToString_FallsBackToParser"`
Expected: PASS.

- [ ] **Step 6.5: Run the full test class**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests"`
Expected: three tests pass.

- [ ] **Step 6.6: Commit (Tasks 5 + 6 together)**

```bash
git add vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs
git commit -m "feat(agent-jobs): resolve FriendlyType for managed agent rows

TypeToString from _Jobs.csv is the primary source; CJobTypesParser is
the fallback when TypeToString is blank (legacy CSVs or jobs where
VBR returns empty for the property)."
```

---

## Task 7: `FriendlyType` for standalone — substitute "Backup" with "Standalone"

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`
- Modify: `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs`

Standalone jobs (where `JobType == "EndpointBackup"`) need the trailing word "Backup" replaced with "Standalone" so "Windows Agent Backup" → "Windows Agent Standalone".

- [ ] **Step 7.1: Add failing tests covering Windows, Linux, and Mac**

Append to `AgentJobAggregatorTests.cs`:

```csharp
        [Fact]
        public void Build_StandaloneWindows_ReplacesBackupWithStandalone()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "Standalone-Win", JobType = "EndpointBackup", TypeToString = "Windows Agent Backup" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Equal("Windows Agent Standalone", result.Single().FriendlyType);
        }

        [Fact]
        public void Build_StandaloneLinux_ReplacesBackupWithStandalone()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "Standalone-Lin", JobType = "EndpointBackup", TypeToString = "Linux Agent Backup" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Equal("Linux Agent Standalone", result.Single().FriendlyType);
        }

        [Fact]
        public void Build_StandaloneMac_ReplacesBackupWithStandalone()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "Standalone-Mac", JobType = "EndpointBackup", TypeToString = "Mac Agent Backup" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Equal("Mac Agent Standalone", result.Single().FriendlyType);
        }

        [Fact]
        public void Build_StandaloneTypeToStringNotEndingInBackup_AppendsStandalone()
        {
            var rows = new List<CJobCsvInfos>
            {
                new() { Name = "Standalone-Unusual", JobType = "EndpointBackup", TypeToString = "Some Other Label" },
            };

            var result = AgentJobAggregator.Build(rows);

            Assert.Equal("Some Other Label Standalone", result.Single().FriendlyType);
        }
```

- [ ] **Step 7.2: Run to verify they fail**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_Standalone"`
Expected: all four FAIL — current code returns `TypeToString` verbatim.

- [ ] **Step 7.3: Implement the substitution**

In `AgentJobAggregator.cs`, update `ResolveFriendlyType`:

```csharp
        private static string ResolveFriendlyType(CJobCsvInfos row)
        {
            string baseLabel = !string.IsNullOrEmpty(row.TypeToString)
                ? row.TypeToString
                : CJobTypesParser.GetJobType(row.JobType);

            if (row.JobType == "EndpointBackup")
            {
                return ToStandaloneLabel(baseLabel);
            }

            return baseLabel;
        }

        private static string ToStandaloneLabel(string baseLabel)
        {
            if (string.IsNullOrEmpty(baseLabel))
            {
                return "Agent Standalone";
            }

            const string backupSuffix = " Backup";
            if (baseLabel.EndsWith(backupSuffix, System.StringComparison.Ordinal))
            {
                return baseLabel.Substring(0, baseLabel.Length - backupSuffix.Length) + " Standalone";
            }

            return baseLabel + " Standalone";
        }
```

- [ ] **Step 7.4: Run the new tests to verify they pass**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_Standalone"`
Expected: all four PASS.

- [ ] **Step 7.5: Run the full test class to confirm no regressions**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests"`
Expected: seven tests pass.

- [ ] **Step 7.6: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs
git commit -m "feat(agent-jobs): derive \"... Standalone\" FriendlyType for unmanaged jobs

JobType=EndpointBackup rows substitute the trailing \"Backup\" in their
TypeToString with \"Standalone\". Defensive fallback for unexpected
TypeToString values appends \" Standalone\"."
```

---

## Task 8: Map data fields from `CJobCsvInfos` into `AgentJobRecord`

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs`
- Modify: `vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs`

The renderer consumers need more than just JobName + FriendlyType. Map the columns the renderers use.

- [ ] **Step 8.1: Add a failing test exercising the field mapping**

Append to `AgentJobAggregatorTests.cs`:

```csharp
        [Fact]
        public void Build_PopulatesAllRenderedFields()
        {
            var row = new CJobCsvInfos
            {
                Name = "Win-Agent-Full",
                JobType = "EpAgentBackup",
                TypeToString = "Windows Agent Backup",
                RepoName = "BackupRepo1",
                OriginalSize = 1073741824 * 30.0,        // 30 GB exactly
                OnDiskGB = 17.27,
                RetentionType = "Days",
                RetentionCount = "30",
                RetainDaysToKeep = "7",
                StgEncryptionEnabled = "True",
                CompressionLevel = "5",
                BlockSize = "KbBlockSize1024",
                GfsWeeklyIsEnabled = true,
                GfsWeeklyCount = "4",
                GfsMonthlyEnabled = true,
                GfsMonthlyCount = "1",
                GfsYearlyEnabled = false,
                GfsYearlyCount = "0",
                EnableFullBackup = false,
                Algorithm = "Increment",
                TransformFullToSyntethic = true,
                IndexingType = "ExceptSpecifiedFolders",
                AAIPEnabled = "True",
                VSSEnabled = "True",
                VSSIgnoreErrors = "False",
                GuestFSIndexingEnabled = "False",
                Platform = "",
            };

            var record = AgentJobAggregator.Build(new[] { row }).Single();

            Assert.Equal("Win-Agent-Full", record.JobName);
            Assert.Equal("Windows Agent Backup", record.FriendlyType);
            Assert.Equal("BackupRepo1", record.RepoName);
            Assert.Equal(30.0, record.SourceSizeGB, 2);
            Assert.Equal(17.27, record.OnDiskGB, 2);
            Assert.Equal("Days", record.RetentionScheme);
            Assert.Equal("7", record.RetainDays);
            Assert.Equal("True", record.Encrypted);
            Assert.Equal("Optimal", record.CompressionLevel);
            Assert.Equal("1 MB", record.BlockSize);
            Assert.True(record.GfsEnabled);
            Assert.Equal("Weekly:4,Monthly:1", record.GfsDetails);
            Assert.Equal("False", record.ActiveFullEnabled);
            Assert.True(record.SyntheticFullEnabled);
            Assert.Equal("Forward Incremental", record.BackupChainType);
            Assert.True(record.IndexingEnabled);
            Assert.Equal("True", record.AAIPEnabled);
            Assert.Equal("True", record.VSSEnabled);
            Assert.Equal("False", record.VSSIgnoreErrors);
            Assert.Equal("False", record.GuestFSIndexing);
            Assert.Equal("", record.Platform);
        }

        [Fact]
        public void Build_RetentionScheme_CyclesShownAsPoints()
        {
            var row = new CJobCsvInfos
            {
                Name = "Cycles-Job",
                JobType = "EpAgentBackup",
                TypeToString = "Windows Agent Backup",
                RetentionType = "Cycles",
                RetentionCount = "14",
                RetainDaysToKeep = "0",
            };

            var record = AgentJobAggregator.Build(new[] { row }).Single();

            Assert.Equal("Points", record.RetentionScheme);
            Assert.Equal("14", record.RetainDays);
        }

        [Fact]
        public void Build_BackupChainType_SynteticAlgorithmYieldsReverseIncremental()
        {
            var row = new CJobCsvInfos
            {
                Name = "Reverse-Job",
                JobType = "EpAgentBackup",
                TypeToString = "Windows Agent Backup",
                Algorithm = "Syntethic",
            };

            var record = AgentJobAggregator.Build(new[] { row }).Single();

            Assert.Equal("Reverse Incremental", record.BackupChainType);
        }
```

- [ ] **Step 8.2: Run to verify failure**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests.Build_PopulatesAllRenderedFields"`
Expected: FAIL — most fields on the record are at their default values.

- [ ] **Step 8.3: Implement the field mapping**

In `AgentJobAggregator.cs`, expand the `Select` projection. Replace the existing `Select(r => new AgentJobRecord {...})` block with a call to a new `MapRow` method:

```csharp
            return rows
                .Where(r => r != null && r.JobType != null && AgentJobTypes.Contains(r.JobType))
                .Select(MapRow)
                .ToList();
```

Add the `MapRow` helper inside the class (above `ResolveFriendlyType`):

```csharp
        private static AgentJobRecord MapRow(CJobCsvInfos r)
        {
            bool gfsEnabled = r.GfsMonthlyEnabled || r.GfsWeeklyIsEnabled || r.GfsYearlyEnabled;
            var gfsDetailParts = new List<string>();
            if (r.GfsWeeklyIsEnabled)
            {
                gfsDetailParts.Add($"Weekly:{r.GfsWeeklyCount}");
            }
            if (r.GfsMonthlyEnabled)
            {
                gfsDetailParts.Add($"Monthly:{r.GfsMonthlyCount}");
            }
            if (r.GfsYearlyEnabled)
            {
                gfsDetailParts.Add($"Yearly:{r.GfsYearlyCount}");
            }

            string compressionLevel = r.CompressionLevel switch
            {
                "9" => "Extreme",
                "6" => "High",
                "5" => "Optimal",
                "4" => "Dedupe-Friendly",
                "0" => "None",
                _ => r.CompressionLevel,
            };

            string blockSize = r.BlockSize switch
            {
                "KbBlockSize1024" => "1 MB",
                "KbBlockSize512" => "512 KB",
                "KbBlockSize256" => "256 KB",
                "KbBlockSize4096" => "4 MB",
                "KbBlockSize8192" => "8 MB",
                _ => r.BlockSize,
            };

            bool syntheticFull = r.Algorithm == "Increment" && r.TransformFullToSyntethic;
            string backupChainType = r.Algorithm == "Syntethic" ? "Reverse Incremental" : "Forward Incremental";
            bool indexingEnabled = r.IndexingType != null && r.IndexingType != "None";
            string retentionScheme = r.RetentionType == "Cycles" ? "Points" : r.RetentionType;
            string retainDays = r.RetentionType == "Cycles" ? r.RetentionCount : r.RetainDaysToKeep;

            return new AgentJobRecord
            {
                JobName = r.Name,
                JobType = r.JobType,
                FriendlyType = ResolveFriendlyType(r),
                RepoName = r.RepoName,
                SourceSizeGB = System.Math.Round(r.OriginalSize / 1024.0 / 1024.0 / 1024.0, 2),
                OnDiskGB = System.Math.Round(r.OnDiskGB ?? 0, 2),
                RetentionScheme = retentionScheme,
                RetainDays = retainDays,
                Encrypted = r.StgEncryptionEnabled,
                CompressionLevel = compressionLevel,
                BlockSize = blockSize,
                GfsEnabled = gfsEnabled,
                GfsDetails = gfsEnabled ? string.Join(",", gfsDetailParts) : string.Empty,
                ActiveFullEnabled = r.EnableFullBackup.ToString(),
                SyntheticFullEnabled = syntheticFull,
                BackupChainType = backupChainType,
                IndexingEnabled = indexingEnabled,
                AAIPEnabled = r.AAIPEnabled ?? "",
                VSSEnabled = r.VSSEnabled ?? "",
                VSSIgnoreErrors = r.VSSIgnoreErrors ?? "",
                GuestFSIndexing = r.GuestFSIndexingEnabled ?? "",
                Platform = r.Platform ?? "",
            };
        }
```

Add `using System.Linq;` and `using System.Collections.Generic;` to the top of the file if not already present.

- [ ] **Step 8.4: Run the new tests to verify they pass**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~AgentJobAggregatorTests"`
Expected: all ten tests PASS.

- [ ] **Step 8.5: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregator.cs vHC/VhcXTests/Functions/Reporting/DataFormers/AgentJobs/AgentJobAggregatorTests.cs
git commit -m "feat(agent-jobs): map CJobCsvInfos fields into AgentJobRecord

Mirrors the formatting that CJobInfoTable applies (compression labels,
block-size labels, retention scheme \"Points\" for cycles, GFS detail
string, derived synthetic-full + backup-chain flags) so renderers can
consume the record without re-deriving."
```

---

## Task 9: Update `Get-VhcJob.ps1` — enumerate standalone jobs and project `TypeToString`

**Files:**
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcJob.ps1`

Two changes: append standalone agent jobs into `$Jobs` and add the `TypeToString` column to the `Select-Object` projection so it lands in `_Jobs.csv`.

- [ ] **Step 9.1: Modify the script**

In `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcJob.ps1`:

Replace the existing block at lines 36–41:

```powershell
    try {
        $Jobs = Get-VBRJob -WarningAction SilentlyContinue
    } catch {
        Write-LogFile "Main jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhciModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
```

With:

```powershell
    try {
        $Jobs = Get-VBRJob -WarningAction SilentlyContinue
    } catch {
        Write-LogFile "Main jobs collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhciModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }

    # Standalone (unmanaged) agent jobs are not returned by Get-VBRJob.
    # Enumerate them via the backup objects they own; .GetJob() returns
    # a CBackupJob with the same shape Get-VBRJob produces, so they flow
    # through the projection below unchanged.
    try {
        $standaloneBackups = Get-VBRBackup -WarningAction SilentlyContinue |
            Where-Object { $_.IsAgentStandaloneJob -eq $true }
        if ($standaloneBackups) {
            $standaloneJobs = @($standaloneBackups | ForEach-Object { $_.GetJob() } | Where-Object { $_ })
            if ($standaloneJobs.Count -gt 0) {
                Write-LogFile "Standalone agent jobs collected: $($standaloneJobs.Count)"
                $Jobs = @($Jobs) + $standaloneJobs
            }
        }
    } catch {
        Write-LogFile "Standalone agent job collection failed: $($_.Exception.Message)" -LogLevel "ERROR"
        Add-VhciModuleError -CollectorName 'Jobs' -ErrorMessage $_.Exception.Message
    }
```

Then add `TypeToString` to the `Select-Object` projection. After the `'Platform'` block ending at the closing `}}` on line 156, add a comma and the new entry. The complete change replaces the closing of the `Select-Object` chain at lines 151–156:

Find this block (current text):

```powershell
            @{n = 'Platform';                      e = {
                $key = if ($Job.Name) { $Job.Name.ToLowerInvariant() } else { '' }
                if ($script:PlatformMap -and $script:PlatformMap.ContainsKey($key)) {
                    $script:PlatformMap[$key]
                } else { '' }
            }}
```

Replace with:

```powershell
            @{n = 'Platform';                      e = {
                $key = if ($Job.Name) { $Job.Name.ToLowerInvariant() } else { '' }
                if ($script:PlatformMap -and $script:PlatformMap.ContainsKey($key)) {
                    $script:PlatformMap[$key]
                } else { '' }
            }},
            @{n = 'TypeToString';                  e = { $Job.TypeToString } }
```

- [ ] **Step 9.2: Run the integration PowerShell test that exercises this script**

The repo has integration tests at `vHC/VhcXTests/Integration/PSScriptIntegrationTests.cs` and unit tests at `vHC/VhcXTests/Integration/VhcModuleUnitTests.cs`. Run them to confirm the script still imports and produces valid output:

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~PSScriptIntegrationTests|FullyQualifiedName~VhcModuleUnitTests"`
Expected: PASS (no functional regression introduced by the additions).

- [ ] **Step 9.3: Spot-check on the live VBR (Windows host required)**

This is a manual sanity check on the real VBR server (the host this is being developed on). Skip on non-Windows / non-VBR dev machines.

Run a one-liner that imports the module, calls the function in isolation, and checks the output. Connect to VBR in the same call (PowerShell shell state does not persist between tool calls):

```powershell
Connect-VBRServer -ErrorAction Stop
Import-Module "<repo-root>/vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/vHC-VbrConfig.psd1"
Initialize-VhcModule -ReportPath "$env:TEMP/vhc-test" -VBRServer "TEST"
Get-VhcJob -VBRVersion 13
Get-Content "$env:TEMP/vhc-test/TEST_Jobs.csv" | Select-Object -First 2
```

Expected: the CSV header line includes `TypeToString` as the last column; the data rows include a row for the standalone agent (use the known standalone job name from `Get-VBRBackup | ?{IsAgentStandaloneJob}` on the dev machine).

- [ ] **Step 9.4: Commit**

```bash
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcJob.ps1
git commit -m "feat(collection): include standalone agent jobs and TypeToString in _Jobs.csv

Standalone agent jobs are enumerated via Get-VBRBackup |
?{IsAgentStandaloneJob} | .GetJob(), which returns a CBackupJob with
the same shape as Get-VBRJob output. They flow through the existing
projection unchanged. TypeToString is added to the Select-Object
projection so the C# aggregator can resolve friendly type labels."
```

---

## Task 10: Add `AgentJobs` property to `CDataFormer`

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/CDataFormer.cs`

Expose the aggregator output once, lazily computed, so the three renderers can read from a single cached collection per `CDataFormer` instance.

- [ ] **Step 10.1: Add the property and backing field**

Open `vHC/HC_Reporting/Functions/Reporting/Html/CDataFormer.cs`. After the existing private cache fields (around line 58, after `_cachedServerScrub`), add:

```csharp
        private IReadOnlyList<AgentJobRecord> _cachedAgentJobs;
```

Add the using at the top of the file (group with the existing `VeeamHealthCheck.Functions.Reporting.*` usings near line 15):

```csharp
using VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs;
```

Then add the public property near the other public surface. Place it immediately after the constructor (after the closing `}` of the constructor at line 79):

```csharp
        /// <summary>
        /// Unified view of all Veeam Agent jobs (managed and standalone) sourced
        /// from _Jobs.csv. Filtered and friendly-typed by AgentJobAggregator.
        /// Cached for the lifetime of this CDataFormer instance.
        /// </summary>
        public IReadOnlyList<AgentJobRecord> AgentJobs
        {
            get
            {
                if (_cachedAgentJobs == null)
                {
                    var rows = new CCsvParser().JobCsvParser();
                    _cachedAgentJobs = AgentJobAggregator.Build(rows);
                }
                return _cachedAgentJobs;
            }
        }
```

- [ ] **Step 10.2: Build to verify**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: build succeeds, no new warnings.

- [ ] **Step 10.3: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/Html/CDataFormer.cs
git commit -m "feat(dataformer): expose AgentJobs collection on CDataFormer

Lazy-cached IReadOnlyList<AgentJobRecord> sourced from _Jobs.csv via
AgentJobAggregator. Consumed by the three job renderers in follow-up
commits."
```

---

## Task 11: `CJobInfoTable` JSON capture — use `FriendlyType` for agent rows

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobInfoTable.cs`

Today, line 429 calls `CJobTypesParser.GetJobType(job.JobType)` for every job in the JSON capture. Look up each agent job's `JobName` in `CDataFormer.AgentJobs` to source the `FriendlyType` instead; non-agent jobs continue to use `CJobTypesParser`.

Standalone agent rows are already in `source` after Task 9 (they're in `_Jobs.csv`), so the existing iteration picks them up — no new emission loop needed.

- [ ] **Step 11.1: Modify the JSON capture loop**

Open `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobInfoTable.cs`. The JSON capture block is at lines 370–451. Above the `foreach (var job in source)` loop (line 378), add a dictionary built from `CDataFormer.AgentJobs`:

Find this section starting around line 373:

```csharp
                CCsvParser csvparser = new();
                var source = csvparser.JobCsvParser().ToList();
                List<string> headers = new() { "JobName", ... };
                List<List<string>> rows = new();

                foreach (var job in source)
                {
```

Insert immediately after `List<List<string>> rows = new();` and before `foreach (var job in source)`:

```csharp
                var agentJobsByName = this.df.AgentJobs
                    .ToDictionary(
                        a => a.JobName ?? string.Empty,
                        a => a,
                        System.StringComparer.OrdinalIgnoreCase);
```

Then replace the existing line:

```csharp
                        CJobTypesParser.GetJobType(job.JobType),
```

(at approximately line 429, inside the `rows.Add(new List<string> { ... })` call) with:

```csharp
                        agentJobsByName.TryGetValue(job.Name ?? string.Empty, out var agentRecord)
                            ? agentRecord.FriendlyType
                            : CJobTypesParser.GetJobType(job.JobType),
```

Add `using System.Linq;` to the top of the file if not already present (it should already be there).

- [ ] **Step 11.2: Build to verify**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: build succeeds.

- [ ] **Step 11.3: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobInfoTable.cs
git commit -m "feat(jobinfo): use AgentJobs FriendlyType for agent rows in jobInfo JSON

Agent job rows pick up TypeToString-derived names (\"Windows Agent
Backup\", \"Windows Agent Standalone\", etc.) by name lookup against
CDataFormer.AgentJobs. Non-agent rows continue using CJobTypesParser."
```

---

## Task 12: `CJobSummaryTable` — drop dual sourcing, count via `AgentJobs`

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/CJobSummaryTable.cs`

Today, lines 37 and 40 add unconditional buckets ("Agent Backup", "Unmanaged Agent") that double-count managed agents and pre-collapse standalone agents under a generic label. Remove those adds and let the natural per-type bucket creation pick up the friendly types from `AgentJobs`.

- [ ] **Step 12.1: Modify `JobSummaryTable()`**

Open `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/CJobSummaryTable.cs`.

Replace the existing method body (lines 17–84). The new version:
1. Drops the `agentBackups` and `endpointJobs` sources and their bucket adds.
2. Uses `CDataFormer.AgentJobs.GroupBy(FriendlyType)` to add agent buckets.
3. Skips agent job types in the existing per-type loop (they're already covered by the AgentJobs grouping).

Replace the file's class body with:

```csharp
using System;
using System.Collections.Generic;
using System.Linq;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs;
using VeeamHealthCheck.Functions.Reporting.Html;
using VeeamHealthCheck.Functions.Reporting.Html.DataFormers;
using VeeamHealthCheck.Shared;
using static VeeamHealthCheck.Functions.Collection.DB.CModel;

namespace VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables
{
    internal class CJobSummaryTable
    {
        // Agent job types are counted via CDataFormer.AgentJobs grouped by FriendlyType.
        // They must be excluded from the generic per-type loop to avoid double-counting.
        private static readonly HashSet<string> AgentJobTypes = new()
        {
            "EpAgentBackup",
            "EpAgentPolicy",
            "EpAgentManagement",
            "ELinuxPhysical",
            "EndpointBackup",
        };

        public CJobSummaryTable() { }

        public Dictionary<string, int> JobSummaryTable()
        {
            Dictionary<string, int> typeAndCount = new();

            try
            {
                CCsvParser csv = new();
                var backupJobs = csv.JobCsvParser().ToList();
                var pluginJobs = csv.GetDynamicPluginJobs();
                var catalystJobs = csv.GetDynamicCatalystJob();
                var cdpJobs = csv.GetDynamicCdpJobs();
                var nasBackupJobs = csv.GetDynamicNasBackup();
                var nasBcj = csv.GetDynamicNasBCJ();
                var sureBackup = csv.GetDynamicSureBackupJob();
                var tapeJobs = csv.GetTapeJobInfoFromCsv();

                typeAndCount.Add("Plugin", pluginJobs.Count());
                typeAndCount.Add("Catalyst Copy", catalystJobs.Count());
                typeAndCount.Add("CDP", cdpJobs.Count());
                typeAndCount.Add("File Backup", nasBackupJobs.Count());
                typeAndCount.Add("File Backup - Copy", nasBcj.Count());
                typeAndCount.Add("SureBackup", sureBackup.Count());
                typeAndCount.Add("Tape", tapeJobs.Count());

                // Agent jobs (managed + standalone) come from the unified AgentJobs view,
                // grouped by FriendlyType. This replaces the previous "Agent Backup" /
                // "Unmanaged Agent" buckets which double-counted managed jobs.
                var dataFormer = new CDataFormer();
                foreach (var grouping in dataFormer.AgentJobs.GroupBy(a => a.FriendlyType))
                {
                    if (!typeAndCount.ContainsKey(grouping.Key))
                    {
                        typeAndCount.Add(grouping.Key, grouping.Count());
                    }
                }

                var types = backupJobs.Select(x => x.JobType).Distinct().ToList();

                try
                {
                    foreach (var bType in types)
                    {
                        if (bType == "NasBackup" || bType == "NasBackupCopy")
                        {
                            continue;
                        }

                        if (AgentJobTypes.Contains(bType))
                        {
                            continue;
                        }

                        var realType = CJobTypesParser.GetJobType(bType);
                        if (!typeAndCount.ContainsKey(realType))
                        {
                            try
                            {
                                typeAndCount.Add(realType, backupJobs.Count(x => x.JobType == bType));
                            }
                            catch (Exception ex) { CGlobals.Logger.Error(ex.Message); }
                        }
                    }
                }
                catch (Exception ex) { CGlobals.Logger.Error(ex.Message); }

                foreach (string dbType in Enum.GetNames(typeof(EDbJobType)))
                {
                    string humanReadable = CJobTypesParser.GetJobType(dbType);
                    if (!typeAndCount.ContainsKey(humanReadable))
                    {
                        typeAndCount.Add(humanReadable, 0);
                    }
                }

                typeAndCount = typeAndCount.OrderBy(x => x.Key).ToDictionary(x => x.Key, x => x.Value);
            }
            catch (Exception ex) { CGlobals.Logger.Error(ex.Message); }

            return typeAndCount;
        }
    }
}
```

- [ ] **Step 12.2: Build to verify**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: build succeeds. (If `using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables` was previously implicit, the explicit usings cover it.)

- [ ] **Step 12.3: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/CJobSummaryTable.cs
git commit -m "fix(jobsummary): count agent jobs via AgentJobs to drop double-counting

Removes the unconditional \"Agent Backup\" and \"Unmanaged Agent\" bucket
adds (sourced from _AgentBackupJob.csv and _EndpointJob.csv, which
overlap with _Jobs.csv on managed agents). Agent buckets are now built
from CDataFormer.AgentJobs grouped by FriendlyType, producing distinct
\"Windows Agent Backup\", \"Windows Agent Policy\", \"Windows Agent
Standalone\" counts with no overlap."
```

---

## Task 13: `CJobSessionSummaryTable` — resolve `FriendlyType` per session at all five call sites

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobSessionSummaryTable.cs`

Per-session metrics continue to come from the database (`CGlobals.DtParser.JobSessions`). The session-level `JobType` enum collapses managed and standalone agent sessions to the same value (`EEndPoint` for both), so a parser lookup alone cannot tell them apart. Resolve a `FriendlyType` per session via `JobName` lookup against `CDataFormer.AgentJobs`, falling back to `CJobTypesParser.GetJobType(session.JobType)` when no match.

This affects five call sites:
- **RenderFlat — line 68:** the `JobType` cell in the HTML row.
- **RenderFlat — line 117:** the `JobTypes` value in the `jobSessionSummary` JSON section.
- **RenderByJob — line 141 (and downstream loop at 147–160):** the grouping key driving section headings. Re-group by `FriendlyType` instead of raw enum so managed and standalone agents render in separate sections.
- **RenderByJob — line 230:** the `JobType` cell in the per-session HTML row inside each grouped section.
- **RenderByJob — line 345:** the `JobTypes` value in the `jobSessionSummaryByJob` JSON section.

The re-grouping in `RenderByJob` is the linchpin fix for the "everything renders as Endpoint Backup Jobs" complaint — grouping on the friendly type produces separate sections for "Windows Agent Backup Jobs", "Windows Agent Policy Jobs", "Windows Agent Standalone Jobs", etc.

- [ ] **Step 13.1: Add the using and a shared resolver helper**

Open `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobSessionSummaryTable.cs`.

Add to the using block at the top of the file (alongside existing usings):

```csharp
using VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs;
```

Add a private helper method inside the class. Place it immediately above `RenderFlat` (after the constructor at line 23):

```csharp
        private Dictionary<string, AgentJobRecord> BuildAgentJobsByName()
        {
            return this.df.AgentJobs
                .ToDictionary(
                    a => a.JobName ?? string.Empty,
                    a => a,
                    StringComparer.OrdinalIgnoreCase);
        }

        private string ResolveSessionType(
            Dictionary<string, AgentJobRecord> agentJobsByName,
            string jobName,
            string rawJobType)
        {
            if (agentJobsByName.TryGetValue(jobName ?? string.Empty, out var record))
            {
                return record.FriendlyType;
            }
            return CJobTypesParser.GetJobType(rawJobType);
        }
```

Add `using System;` if not already present (for `StringComparer`). The existing file already imports `System.Collections.Generic` and `System.Linq`.

- [ ] **Step 13.2: Update `RenderFlat` — replace both call sites**

In `RenderFlat(bool scrub)`, immediately after the line `var stuff = this.df.ConvertJobSessSummaryToXml(scrub);` (line 34), insert:

```csharp
                var agentJobsByName = this.BuildAgentJobsByName();
```

Replace the existing line 68:

```csharp
                        string jobType = CJobTypesParser.GetJobType(stu.JobType);
```

with:

```csharp
                        string jobType = this.ResolveSessionType(agentJobsByName, stu.JobName, stu.JobType);
```

The second `stuff` retrieval at line 94 is inside the JSON capture try-block. Immediately after that line, insert:

```csharp
                var agentJobsByNameJson = this.BuildAgentJobsByName();
```

Replace the existing line 117:

```csharp
                    CJobTypesParser.GetJobType(stu.JobType),
```

with:

```csharp
                    this.ResolveSessionType(agentJobsByNameJson, stu.JobName, stu.JobType),
```

- [ ] **Step 13.3: Update `RenderByJob` — re-group by FriendlyType, replace per-row + JSON call sites**

In `RenderByJob(bool scrub)`, replace lines 140–141:

```csharp
                var stuff = this.df.ConvertJobSessSummaryToXml(scrub);
                var jobTypes = stuff.Select(x => x.JobType).Distinct().ToList();
```

with:

```csharp
                var stuff = this.df.ConvertJobSessSummaryToXml(scrub);
                var agentJobsByName = this.BuildAgentJobsByName();

                // Annotate each session with its FriendlyType, then group by that label.
                // Managed and standalone agents share session-level JobType (EEndPoint) and
                // would otherwise collapse into one section; grouping by FriendlyType keeps
                // them separate ("Windows Agent Backup Jobs" vs "Windows Agent Standalone
                // Jobs", etc.).
                var annotated = stuff
                    .Select(s => new
                    {
                        Session = s,
                        FriendlyType = this.ResolveSessionType(agentJobsByName, s.JobName, s.JobType),
                    })
                    .ToList();

                var sessionGroups = annotated
                    .GroupBy(x => x.FriendlyType ?? string.Empty)
                    .ToList();
```

Replace the existing `foreach (var jType in jobTypes)` block at lines 147–160. The new loop uses the grouping; the inner `var res = stuff.Where(x => x.JobType == jobType).ToList();` at line 169 is replaced by iterating the group directly. Here's the full replacement block from line 147 through line 169:

Replace:

```csharp
                    foreach (var jType in jobTypes)
                    {
                        if (CGlobals.DEBUG)
                        {
                            this.log.Debug("Job Type = " + jType);
                        }

                        bool skipTotals = false;
                        var jobType = jType;

                        if (string.IsNullOrEmpty(jType))
                        {
                            jobType = "Summary of All";
                        }

                        var realType = CJobTypesParser.GetJobType(jobType);

                        string sectionHeader = realType ?? "Summary of All";

                        string jobTable = this.form.SectionStartWithButton("jobTable-" + realType.ToLower().Replace(" ", "-"), sectionHeader + " Jobs", string.Empty);
                        s += jobTable;
                        s += this.SetJobSessionsHeaders();
                        var res = stuff.Where(x => x.JobType == jobType).ToList();
```

With:

```csharp
                    foreach (var grp in sessionGroups)
                    {
                        if (CGlobals.DEBUG)
                        {
                            this.log.Debug("Job Type = " + grp.Key);
                        }

                        bool skipTotals = false;
                        string sectionHeader = string.IsNullOrEmpty(grp.Key) ? "Summary of All" : grp.Key;
                        string sectionSlug = sectionHeader.ToLower().Replace(" ", "-");

                        string jobTable = this.form.SectionStartWithButton("jobTable-" + sectionSlug, sectionHeader + " Jobs", string.Empty);
                        s += jobTable;
                        s += this.SetJobSessionsHeaders();
                        var res = grp.Select(x => x.Session).ToList();
```

Inside the inner `foreach (var stu in res)` block, the filter `if (stu.JobType != jobType && stu.JobName != "Totals") { continue; }` at line 201 no longer applies (the group already contains exactly the right sessions). Replace lines 201–204:

```csharp
                            if (stu.JobType != jobType && stu.JobName != "Totals")
                            {
                                continue;
                            }
```

with:

```csharp
                            // No JobType filter needed — sessions are already grouped by FriendlyType.
```

Replace line 230:

```csharp
                                string jt = CJobTypesParser.GetJobType(stu.JobType);
```

with:

```csharp
                                string jt = this.ResolveSessionType(agentJobsByName, stu.JobName, stu.JobType);
```

For the JSON capture block at the bottom of `RenderByJob` (the try-block at lines 319–352), the existing `var stuff = this.df.ConvertJobSessSummaryToXml(scrub);` at line 321 is a second retrieval. Reuse the existing `agentJobsByName` from above by moving the dictionary build OR rebuild it. Simpler: rebuild. Immediately after line 322 `var ordered = stuff.OrderBy(stu => stu.JobName).ToList();`, insert:

```csharp
                var agentJobsByNameJson = this.BuildAgentJobsByName();
```

Replace line 345:

```csharp
                    CJobTypesParser.GetJobType(stu.JobType),
```

with:

```csharp
                    this.ResolveSessionType(agentJobsByNameJson, stu.JobName, stu.JobType),
```

- [ ] **Step 13.4: Build to verify**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: build succeeds.

If `CS0103` (`stu.JobName` not found) appears: confirm `stu.JobName` exists by reading the session DTO at `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/JobSessionSummaryRow.cs` — `JobName` is at line 32 and `JobType` at line 32-ish, both present.

If `CS0234` (namespace not found) appears for `AgentJobRecord`: confirm the using `VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs;` is present at the top.

- [ ] **Step 13.5: Commit**

```bash
git add "vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Jobs Info/CJobSessionSummaryTable.cs"
git commit -m "feat(jobsessions): resolve FriendlyType per session and regroup RenderByJob

Session-level JobType (EEndPoint) collapses managed and standalone
agent sessions, so a parser lookup alone cannot distinguish them.
Resolve a FriendlyType per session via JobName lookup against
CDataFormer.AgentJobs (with CJobTypesParser as fallback), and regroup
RenderByJob by FriendlyType so managed agent backup, agent policy,
and standalone sessions render in separate sections. Applied to all
five JobType display sites (RenderFlat HTML + JSON, RenderByJob
section heading + per-row cell + JSON)."
```

---

## Task 14: Full build, full test suite, manual end-to-end verification

**Files:** none (verification only)

Run the entire suite and the live VBR report against the dev VBR to confirm the three JSON sections behave as the spec describes.

- [ ] **Step 14.1: Full build**

Run: `dotnet build vHC/HC.sln --configuration Debug`
Expected: success, zero new warnings.

- [ ] **Step 14.2: Full test suite**

Run: `dotnet test vHC/VhcXTests/VhcXTests.csproj`
Expected: all tests pass, including the new `CJobTypesParserTests` and `AgentJobAggregatorTests`.

- [ ] **Step 14.3: Generate a real report against the local VBR**

From a PowerShell session on the VBR host, run the built executable in headless mode (the GUI is the alternative; either produces the same JSON output):

```powershell
$exe = Get-ChildItem -Recurse -Filter "VeeamHealthCheck.exe" -Path "vHC" | Select-Object -First 1 -ExpandProperty FullName
& $exe --silent
```

Inspect the most recent JSON output:

```powershell
Get-ChildItem "Veeam Health Check Report_VBR_*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
```

If the project uses a different default output directory on this dev machine (e.g. `C:\temp\vHC\...`), search there. The JSON filename pattern is always `Veeam Health Check Report_VBR_<host>_<timestamp>.json`.

- [ ] **Step 14.4: Verify `jobInfo` includes the standalone agent**

Open the resulting JSON and confirm:
- A row exists in `jobInfo.Rows` whose `JobName` matches the known standalone agent (e.g. `Unmanaged-WindowsAgents-VTESTVM03`).
- That row's `JobType` column is `"Windows Agent Standalone"` (not `"EndpointBackup"`, not `"Endpoint Backup"`, not empty).
- That row's `SourceSizeGB` and `OnDiskGB` are non-zero (matching the values shown in `jobSessionSummaryByJob` for the same job).

- [ ] **Step 14.5: Verify `jobSummary`**

Confirm:
- Buckets like `"Windows Agent Backup"`, `"Windows Agent Policy"`, `"Windows Agent Standalone"` (and Linux/Mac equivalents if present) appear.
- No bucket is named `"EpAgentBackup"`, `"EpAgentPolicy"`, `"Agent Backup"`, or `"Unmanaged Agent"` for the new agent categories.
- Total of agent buckets equals the count of agent rows in `jobInfo`.

- [ ] **Step 14.6: Verify `jobSessionSummaryByJob`**

Confirm:
- Each row's `JobTypes` column reflects its job's friendly type (e.g. `"Windows Agent Backup"` for managed-backup sessions, `"Windows Agent Standalone"` for the unmanaged one).
- No row collapses to a generic `"Endpoint Backup"` for an agent session.

- [ ] **Step 14.7: Verify nothing else regressed**

Confirm non-agent sections (`backupServer`, `serverSummary`, `managedServers`, `repos`, `sobr`, `extents`, `capextents`, `archextents`, `protectedWorkloads`, `missingJobs`) are present and look unchanged in structure.

- [ ] **Step 14.8: Final commit if any tweaks were made during verification**

If verification revealed any small fixes, commit them with descriptive messages.

```bash
git status
```

If there are no further changes, the feature branch is ready. Push and open the PR:

```bash
git push -u origin feature/agent-jobs-managed-standalone
gh pr create --base dev --title "Agent jobs: surface standalone in jobInfo, fix friendly type labels" --body "$(cat <<'EOF'
## Summary

Fixes three issues in how the VBR report renders Veeam Agent jobs:

- `jobInfo` now includes standalone (unmanaged) agent rows with full sizing/configuration, sourced via `Get-VBRBackup | ?{IsAgentStandaloneJob} | .GetJob()` so they flow through the same projection as managed jobs.
- `jobSummary` no longer double-counts managed agents (the previous "Agent Backup" bucket from `_AgentBackupJob.csv` overlapped with `EpAgentBackup`/`EpAgentPolicy` from `_Jobs.csv`); buckets now read "Windows Agent Backup", "Windows Agent Policy", "Windows Agent Standalone", etc.
- `jobSessionSummaryByJob` no longer collapses every agent session to "Endpoint Backup"; each row reflects its job's actual friendly type.

Design: `docs/superpowers/specs/2026-05-26-agent-jobs-managed-standalone-design.md`
Implementation plan: `docs/superpowers/plans/2026-05-26-agent-jobs-managed-standalone.md`

Relates to upstream issue VeeamHub/veeam-healthcheck#148.

## Test plan

- [ ] `dotnet build vHC/HC.sln --configuration Debug` succeeds
- [ ] `dotnet test vHC/VhcXTests/VhcXTests.csproj` passes (includes new `AgentJobAggregatorTests` and `CJobTypesParserTests`)
- [ ] Manual report run shows standalone agent in `jobInfo` with non-zero sizes
- [ ] `jobSummary` has distinct friendly-type buckets and no double-count
- [ ] `jobSessionSummaryByJob` shows correct per-row friendly type

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Spec coverage check (self-review by the plan author)

Each goal from the spec maps to a task above:

- **`jobInfo` contains standalone with non-zero sizes** — Task 9 puts standalone rows in `_Jobs.csv`; Task 11 ensures the JSON capture treats them correctly. Verified in Step 14.4.
- **`jobSummary` shows distinct friendly buckets, no double-count** — Task 12. Verified in Step 14.5.
- **`jobSessionSummaryByJob` shows correct friendly type per row** — Task 13. Verified in Step 14.6.
- **Generic across Windows/Linux/Mac** — Tasks 7 covers the substitution rule for all three; tests `Build_StandaloneWindows/Linux/Mac_ReplacesBackupWithStandalone` lock it in.
- **Hybrid naming (TypeToString primary, parser fallback)** — Tasks 5 (primary) and 6 (fallback) with explicit tests.
- **No double-count of managed agents** — Task 12 removes both overlapping sources.
- **TypeToString deprecation note / `Get-VBRJob` future migration** — out of scope per spec, documented in spec only.

Out-of-scope items confirmed not addressed in the plan:
- `missingJobs` section — no task. Consistent with spec.
- Removing `_AgentBackupJob.csv` / `_EndpointJob.csv` collection — `Get-VhciAgentJob.ps1` is untouched. Consistent with spec.
- Migration off `Get-VBRJob` for agent types — no task. Consistent with spec.
