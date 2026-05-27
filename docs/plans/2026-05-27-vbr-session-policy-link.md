# VBR Session Rollup via Info.PolicyName/PolicyTag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the name-prefix-based session rollup with GUID-based grouping using `Info.PolicyName` / `Info.PolicyTag` properties from VBR sessions, eliminating an entire class of edge-case bugs (parent names containing " - ", policy children with backslash separators, longest-prefix collisions, rename canonicalization).

**Architecture:** The Veeam PowerShell collector captures three new fields per session — `session.JobId`, `session.Info.PolicyName`, `session.Info.PolicyTag` — and writes them to `VeeamSessionReport.csv` as new positional columns 17/18/19. The C# layer parses them into `CJobSessionInfo`, then a new `CSessionGroupKey` helper computes `id:<PolicyTag>` for children (rolls them up under the parent's GUID) or `id:<JobId>` for parents/standalone (`name:<JobName>` is the legacy-CSV fallback). `CJobSessSummary.JobSessionSummaryToXml` and `IndividualJobSessionsHelper.ParseIndividualSessions` switch from `BuildNameRollup` to `GroupBy(CSessionGroupKey.Of)`. The old name-prefix code (`TryGetParentPrefix`, `BuildNameRollup`, `StripAlgorithmSuffix`, `namesWithData` guard) is deleted.

**Tech Stack:** PowerShell 7 (Pester v5), .NET 8.0 / C# (xUnit), CsvHelper for CSV mapping.

**Branch:** Work on the current branch `fix/vbr-session-fast-path`. Do not create a new branch.

**Validation source:** `probe-session-properties.csv` and `probe-policy-link.csv` at the repo root confirm the property semantics — see also the bottom of `docs/adr/0019-policy-link-based-session-rollup.md` (created in Task 8).

---

## File Structure

**Modify:**
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.ps1` — capture & emit JobId/PolicyName/PolicyTag
- `vHC/HC_Reporting/Functions/Reporting/CsvHandlers/CJobSessionCsvInfos.cs` — three new `[Index]`/`[Optional]` columns
- `vHC/HC_Reporting/Functions/Reporting/DataTypes/CJobSessionInfo.cs` — three new properties
- `vHC/HC_Reporting/Functions/Reporting/DataTypes/CDataTypesParser.cs` — map the new CSV columns onto `CJobSessionInfo`
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummary.cs` — rewrite the rollup loop
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummaryHelper.cs` — delete obsolete name-prefix functions
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/IndividualJobSessionsHelper.cs` — use the new grouping

**Create:**
- `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CSessionGroupKey.cs` — pure grouping helper
- `vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CSessionGroupKeyTEST.cs` — unit tests for the helper
- `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.Tests.ps1` — Pester tests for the new CSV columns
- `docs/adr/0019-policy-link-based-session-rollup.md` — ADR documenting the change

**Delete (after all tests pass):**
- The probe scripts `probe-session-properties.ps1`, `probe-policy-link.ps1`, and the two output CSVs at the repo root.

---

### Task 1: Capture PolicyName/PolicyTag/JobId in Get-VhcSessionReport

**Files:**
- Create: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.Tests.ps1`
- Modify: `vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.ps1`

- [ ] **Step 1: Write the failing Pester test**

Create `Get-VhcSessionReport.Tests.ps1` with the following content:

```powershell
#Requires -Version 7.0
# Pester v5 tests for Get-VhcSessionReport - new JobId/PolicyName/PolicyTag columns.

BeforeAll {
    $publicDir = Split-Path -Parent $PSCommandPath
    . $PSCommandPath.Replace('.Tests.ps1', '.ps1')
    . (Join-Path $publicDir 'Write-LogFile.ps1')

    # Set script-scoped ReportPath so Export-Csv has somewhere to land
    $script:tempDir = Join-Path ([IO.Path]::GetTempPath()) "vhc-session-test-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $script:tempDir | Out-Null
    Set-Variable -Name 'ReportPath' -Value $script:tempDir -Scope Script
}

AfterAll {
    if (Test-Path $script:tempDir) { Remove-Item -Recurse -Force $script:tempDir }
}

Describe 'GVSR-1: Session CSV includes JobId/PolicyName/PolicyTag columns' {

    BeforeEach {
        Mock Write-LogFile -MockWith { }
        Mock Get-VBRJob               -MockWith { @() }
        Mock Get-VBRComputerBackupJob -MockWith { @() }
        Mock Get-VBREPJob             -MockWith { @() }
        Mock Get-VhciSessionLogWithTimeout -MockWith { @() }

        # Fake task that Get-VBRTaskSession will return for our fake session
        $parentGuid = [guid]'02fe84bc-7394-42b5-bdb2-81a56190d8c5'
        $childGuid  = [guid]'592c44dc-861c-48fc-b70e-e9916c790222'
        $script:parentSession = [pscustomobject]@{
            Name = 'Physical - Linux Servers'
            JobId = $parentGuid
            Info = [pscustomobject]@{ PolicyName = 'Physical - Linux Servers'; PolicyTag = $parentGuid }
        }
        $script:childSession  = [pscustomobject]@{
            Name = 'Physical - Linux Servers - lab-m01-lnx01 (Incremental)'
            JobId = $childGuid
            Info = [pscustomobject]@{ PolicyName = 'Physical - Linux Servers'; PolicyTag = $parentGuid }
        }

        $script:fakeTask = [pscustomobject]@{
            Name = 'lab-m01-lnx01'
            Status = 'Success'
            JobName = 'Physical - Linux Servers - lab-m01-lnx01'
            ObjectPlatform = [pscustomobject]@{ IsEpAgentPlatform = $true; Platform = 'EpAgent' }
            JobSess = [pscustomobject]@{
                IsRetryMode = $false
                CreationTime = (Get-Date).AddDays(-1)
                BackupStats = [pscustomobject]@{ BackupSize = 100; DataSize = 200; DedupRatio = 1; CompressRatio = 1 }
                Progress = [pscustomobject]@{
                    TransferedSize = 0; ReadSize = 0;
                    Duration = [timespan]::FromMinutes(5);
                    BottleneckInfo = [pscustomobject]@{ Source=0; Proxy=0; Network=0; Target=0; Bottleneck=0 }
                }
                Info = [pscustomobject]@{ SessionAlgorithm = 1 }
            }
            WorkDetails = [pscustomobject]@{ TaskAlgorithm = 'Increment'; WorkDuration = [timespan]::FromMinutes(5) }
        }
        Mock Get-VBRTaskSession -MockWith { @($script:fakeTask) }
    }

    It 'writes PolicyName and PolicyTag equal to the parent for a child session' {
        Get-VhcSessionReport -BackupSessions @($script:childSession)

        $csvPath = Join-Path $script:tempDir 'VeeamSessionReport.csv'
        Test-Path $csvPath | Should -BeTrue
        $rows = Import-Csv -Path $csvPath
        $rows.Count | Should -BeGreaterThan 0
        $rows[0].PolicyName | Should -Be 'Physical - Linux Servers'
        $rows[0].PolicyTag  | Should -Be '02fe84bc-7394-42b5-bdb2-81a56190d8c5'
        $rows[0].JobId      | Should -Be '592c44dc-861c-48fc-b70e-e9916c790222'
    }

    It 'leaves PolicyName/PolicyTag empty when Info has no PolicyName' {
        $bareSession = [pscustomobject]@{
            Name = 'Hyper-V - Engineers CHC 01'
            JobId = [guid]'68621a52-2a9c-4fc5-a3f4-acc1c2caa44e'
            Info = [pscustomobject]@{ PolicyName = ''; PolicyTag = [guid]::Empty }
        }
        Get-VhcSessionReport -BackupSessions @($bareSession)

        $rows = Import-Csv -Path (Join-Path $script:tempDir 'VeeamSessionReport.csv')
        $rows[0].PolicyName | Should -Be ''
        $rows[0].PolicyTag  | Should -Match '^(00000000-0000-0000-0000-000000000000)?$'
        $rows[0].JobId      | Should -Be '68621a52-2a9c-4fc5-a3f4-acc1c2caa44e'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```powershell
Invoke-Pester -Path "vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.Tests.ps1" -Output Detailed
```

Expected: FAIL — `Expected 'Physical - Linux Servers' but got $null` (the column doesn't exist yet).

- [ ] **Step 3: Implement the CSV columns**

In `Get-VhcSessionReport.ps1`, modify the ordered hashtable at lines 111-138. After the existing canonicalization-by-`$jobIdMap` block (around line 109), add PolicyName/PolicyTag capture with the same canonicalization, then add three keys to the row:

```powershell
                # Capture parent-link properties exposed by VBR on every session.
                # Children carry the parent's PolicyTag (GUID) and PolicyName,
                # enabling the C# layer to roll up per-machine sessions under the
                # parent without any name-prefix parsing. See ADR 0019.
                $policyName = ''
                $policyTag  = [guid]::Empty
                try { if ($session.Info.PolicyName) { $policyName = $session.Info.PolicyName } } catch {}
                try { if ($session.Info.PolicyTag)  { $policyTag  = $session.Info.PolicyTag  } } catch {}

                # If the PolicyTag points at a currently-active job, canonicalize
                # the PolicyName to the job's current Name (handles renames the
                # same way $jobName is already canonicalized above).
                if ($policyTag -ne [guid]::Empty -and $jobIdMap.ContainsKey($policyTag)) {
                    $policyName = $jobIdMap[$policyTag]
                }
```

Then in the `[ordered]@{ ... }` hashtable starting at line 111, after `'JobAlgorithm' = $task.JobSess.Info.SessionAlgorithm`, add three new entries (the trailing comma on the previous line is required):

```powershell
                    'JobAlgorithm'      = $task.JobSess.Info.SessionAlgorithm
                    'JobId'             = if ($session.JobId) { "$($session.JobId)" } else { '' }
                    'PolicyName'        = $policyName
                    'PolicyTag'         = if ($policyTag -ne [guid]::Empty) { "$policyTag" } else { '' }
```

Also update the header-only-CSV fallback at lines 153-158 to include the same three keys:

```powershell
        $headerLine = ([pscustomobject][ordered]@{
            'JobName'=''; 'VMName'=''; 'Status'=''; 'IsRetry'=''; 'ProcessingMode'='';
            'JobDuration'=''; 'TaskDuration'=''; 'TaskAlgorithm'=''; 'CreationTime'='';
            'BackupSizeGB'=''; 'DataSizeGB'=''; 'DedupRatio'=''; 'CompressRatio'='';
            'BottleneckDetails'=''; 'PrimaryBottleneck'=''; 'JobType'=''; 'JobAlgorithm'='';
            'JobId'=''; 'PolicyName'=''; 'PolicyTag'=''
        } | ConvertTo-Csv -NoTypeInformation | Select-Object -First 1)
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
Invoke-Pester -Path "vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.Tests.ps1" -Output Detailed
```

Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.ps1 \
        vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig/Public/Get-VhcSessionReport.Tests.ps1
git commit -m "feat(session-report): emit JobId/PolicyName/PolicyTag for GUID-based rollup"
```

---

### Task 2: Add the three new columns to CJobSessionCsvInfos

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/CsvHandlers/CJobSessionCsvInfos.cs`

- [ ] **Step 1: Add the three properties**

At the end of the class, after `JobAlgorithm` (currently `[Index(16)]`), add:

```csharp
        [Index(17)]
        [Optional]
        public string JobId { get; set; }

        [Index(18)]
        [Optional]
        public string PolicyName { get; set; }

        [Index(19)]
        [Optional]
        public string PolicyTag { get; set; }
```

`[Optional]` (from `CsvHelper.Configuration.Attributes`) preserves backward compatibility with imported CSVs that lack the columns.

- [ ] **Step 2: Build to verify the class compiles**

```bash
dotnet build vHC/HC.sln --configuration Debug
```

Expected: success.

- [ ] **Step 3: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/CsvHandlers/CJobSessionCsvInfos.cs
git commit -m "feat(csv): add JobId/PolicyName/PolicyTag columns to session CSV schema"
```

---

### Task 3: Add CJobSessionInfo properties and map from the CSV

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/DataTypes/CJobSessionInfo.cs`
- Modify: `vHC/HC_Reporting/Functions/Reporting/DataTypes/CDataTypesParser.cs`

- [ ] **Step 1: Write the failing test**

Append a test to `vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CJobSessSummaryTEST.cs`, inside the existing class (before its final `}`):

```csharp
        [Fact]
        public void CDataTypesParser_Maps_NewCsvColumns_OntoCJobSessionInfo()
        {
            // Arrange: write a session CSV with the three new columns populated.
            var integrationDir = Path.Combine(Path.GetTempPath(), "VhcPolicyLink_" + Guid.NewGuid().ToString());
            var integrationVbrDir = VbrCsvSampleGenerator.CreateTestDataDirectory(integrationDir);

            var csv = "\"JobName\",\"VmName\",\"Status\",\"IsRetry\",\"ProcessingMode\",\"JobDuration\",\"TaskDuration\",\"Alg\",\"CreationTime\",\"BackupSize\",\"DataSize\",\"DedupRatio\",\"CompressionRation\",\"BottleneckDetails\",\"PrimaryBottleneck\",\"JobType\",\"JobAlgorithm\",\"JobId\",\"PolicyName\",\"PolicyTag\"\r\n" +
                      "\"Physical - Linux Servers - lab01 (Incremental)\",\"lab01\",\"Success\",\"False\",\"\",\"00:10:00\",\"00:10:00\",\"Increment\",\"2026-05-20 01:00:00\",\"100\",\"200\",\"\",\"\",\"\",\"\",\"EpAgentManagement\",\"\",\"592c44dc-861c-48fc-b70e-e9916c790222\",\"Physical - Linux Servers\",\"02fe84bc-7394-42b5-bdb2-81a56190d8c5\"";
            // CreateCsvFile is at VbrCsvSampleGenerator.cs:616 - existing helper used by
            // CapacityTierXmlFromCsv_UsesStatusFromCapTierCsv (CJobSessSummaryTEST.cs:350).
            VbrCsvSampleGenerator.CreateCsvFile(integrationVbrDir, "VeeamSessionReport.csv", csv);

            var previousImport = VeeamHealthCheck.CGlobals.IMPORT;
            var previousImportPath = VeeamHealthCheck.CGlobals.IMPORT_PATH;
            var previousResolvedPath = VeeamHealthCheck.Shared.CVariables.ResolvedImportPath;
            var previousParser = VeeamHealthCheck.CGlobals.DtParser;

            try
            {
                VeeamHealthCheck.CGlobals.IMPORT = true;
                VeeamHealthCheck.CGlobals.IMPORT_PATH = integrationVbrDir;
                VeeamHealthCheck.Shared.CVariables.ResolvedImportPath = integrationVbrDir;
                VeeamHealthCheck.CGlobals.DtParser = new VeeamHealthCheck.Functions.Reporting.DataTypes.CDataTypesParser();

                var sessions = VeeamHealthCheck.CGlobals.DtParser.JobSessions;

                Assert.NotNull(sessions);
                Assert.Single(sessions);
                var row = sessions[0];
                Assert.Equal(Guid.Parse("592c44dc-861c-48fc-b70e-e9916c790222"), row.JobId);
                Assert.Equal("Physical - Linux Servers", row.PolicyName);
                Assert.Equal(Guid.Parse("02fe84bc-7394-42b5-bdb2-81a56190d8c5"), row.PolicyTag);
            }
            finally
            {
                VeeamHealthCheck.CGlobals.IMPORT = previousImport;
                VeeamHealthCheck.CGlobals.IMPORT_PATH = previousImportPath;
                VeeamHealthCheck.Shared.CVariables.ResolvedImportPath = previousResolvedPath;
                VeeamHealthCheck.CGlobals.DtParser = previousParser;
                VbrCsvSampleGenerator.CleanupTestDirectory(integrationDir);
            }
        }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~CDataTypesParser_Maps_NewCsvColumns_OntoCJobSessionInfo"
```

Expected: FAIL — `CJobSessionInfo` does not have a `JobId`/`PolicyName`/`PolicyTag` property (compile error), or the test sees null values.

- [ ] **Step 3: Add the three properties to CJobSessionInfo**

In `CJobSessionInfo.cs`, after the existing `JobType` property (line 57), add:

```csharp
        public Guid? JobId { get; set; }

        public string PolicyName { get; set; }

        public Guid? PolicyTag { get; set; }
```

- [ ] **Step 4: Map the new columns in CDataTypesParser**

In `CDataTypesParser.cs`, after the line `jInfo.JobType = s.JobType;` (around line 696), add:

```csharp
                        jInfo.JobId      = ParseGuidOrNull(s.JobId);
                        jInfo.PolicyName = s.PolicyName;
                        jInfo.PolicyTag  = ParseGuidOrNull(s.PolicyTag);
```

Then add a private helper at the bottom of the `CDataTypesParser` class (just before the closing brace of the class):

```csharp
        private static Guid? ParseGuidOrNull(string s)
        {
            if (string.IsNullOrWhiteSpace(s)) return null;
            if (Guid.TryParse(s, out var g) && g != Guid.Empty) return g;
            return null;
        }
```

- [ ] **Step 5: Run test to verify it passes**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~CDataTypesParser_Maps_NewCsvColumns_OntoCJobSessionInfo"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add vHC/HC_Reporting/Functions/Reporting/DataTypes/CJobSessionInfo.cs \
        vHC/HC_Reporting/Functions/Reporting/DataTypes/CDataTypesParser.cs \
        vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CJobSessSummaryTEST.cs
git commit -m "feat(types): expose JobId/PolicyName/PolicyTag on CJobSessionInfo"
```

---

### Task 4: Create CSessionGroupKey helper with tests

**Files:**
- Create: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CSessionGroupKey.cs`
- Create: `vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CSessionGroupKeyTEST.cs`

- [ ] **Step 1: Write the failing tests**

Create `vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CSessionGroupKeyTEST.cs`:

```csharp
using System;
using VeeamHealthCheck.Functions.Reporting.DataTypes;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.Job_Session_Summary;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables
{
    public class CSessionGroupKeyTEST
    {
        private static readonly Guid ParentId = Guid.Parse("02fe84bc-7394-42b5-bdb2-81a56190d8c5");
        private static readonly Guid ChildId  = Guid.Parse("592c44dc-861c-48fc-b70e-e9916c790222");

        [Fact]
        public void Of_ChildWithPolicyTag_ReturnsParentGuid()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Physical - Linux Servers - lab01",
                JobId      = ChildId,
                PolicyName = "Physical - Linux Servers",
                PolicyTag  = ParentId,
            };
            Assert.Equal("id:" + ParentId.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_ParentSession_UsesOwnJobId()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Physical - Linux Servers",
                JobId      = ParentId,
                PolicyName = "Physical - Linux Servers",
                PolicyTag  = ParentId,  // equal to own JobId
            };
            Assert.Equal("id:" + ParentId.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_BCParent_PolicyTagEmpty_UsesOwnJobId()
        {
            // BC orchestrator (SimpleBackupCopyPolicy) has empty PolicyName/PolicyTag,
            // per the probe-policy-link.csv evidence.
            var parentGuid = Guid.Parse("2b60f399-4be7-4548-937d-c9357d5b59e6");
            var s = new CJobSessionInfo
            {
                JobName    = "Backup Copy - Engineers CHC 02",
                JobId      = parentGuid,
                PolicyName = null,
                PolicyTag  = null,
            };
            Assert.Equal("id:" + parentGuid.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_RegularBackup_NoChildrenNoPolicyTag_UsesOwnJobId()
        {
            // Hyper-V Backup case: PolicyName/PolicyTag empty.
            var jobId = Guid.Parse("68621a52-2a9c-4fc5-a3f4-acc1c2caa44e");
            var s = new CJobSessionInfo
            {
                JobName    = "Hyper-V - Engineers CHC 01",
                JobId      = jobId,
                PolicyName = null,
                PolicyTag  = null,
            };
            Assert.Equal("id:" + jobId.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_LegacyCsv_NoGuids_FallsBackToJobName()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Legacy Job",
                JobId      = null,
                PolicyName = null,
                PolicyTag  = null,
            };
            Assert.Equal("name:Legacy Job", CSessionGroupKey.Of(s));
        }

        [Fact]
        public void DisplayName_PrefersPolicyName()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Physical - Linux Servers - lab01",
                PolicyName = "Physical - Linux Servers",
            };
            Assert.Equal("Physical - Linux Servers", CSessionGroupKey.DisplayName(s));
        }

        [Fact]
        public void DisplayName_FallsBackToJobName_WhenPolicyNameEmpty()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Hyper-V - Engineers CHC 01",
                PolicyName = "",
            };
            Assert.Equal("Hyper-V - Engineers CHC 01", CSessionGroupKey.DisplayName(s));
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~CSessionGroupKeyTEST"
```

Expected: compile error (`CSessionGroupKey` doesn't exist).

- [ ] **Step 3: Create CSessionGroupKey.cs**

Create `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CSessionGroupKey.cs`:

```csharp
// <copyright file="CSessionGroupKey.cs" company="PlaceholderCompany">
// Copyright (c) PlaceholderCompany. All rights reserved.
// </copyright>

using System;
using VeeamHealthCheck.Functions.Reporting.DataTypes;

namespace VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.Job_Session_Summary
{
    /// <summary>
    /// Computes stable group identifiers and display names for session rollup.
    /// Children inherit the parent's PolicyTag (GUID) and PolicyName, so grouping
    /// by <see cref="Of"/> automatically merges per-machine child sessions under
    /// their parent. See ADR 0019.
    /// </summary>
    internal static class CSessionGroupKey
    {
        /// <summary>
        /// Returns the rollup group identifier for a session. Preference order:
        ///   1. PolicyTag - child sessions point at their parent's job GUID.
        ///   2. JobId - parents and standalone jobs use their own GUID.
        ///   3. JobName prefix - legacy CSVs without GUID columns.
        /// </summary>
        public static string Of(CJobSessionInfo s)
        {
            var ownId = s.JobId.GetValueOrDefault();
            if (s.PolicyTag.HasValue
                && s.PolicyTag.Value != Guid.Empty
                && s.PolicyTag.Value != ownId)
            {
                return "id:" + s.PolicyTag.Value.ToString("D");
            }

            if (ownId != Guid.Empty)
            {
                return "id:" + ownId.ToString("D");
            }

            return "name:" + (s.JobName ?? string.Empty);
        }

        /// <summary>
        /// Returns the display name for a session's group. Children carry the
        /// parent's PolicyName; parents/standalone fall back to their own JobName.
        /// </summary>
        public static string DisplayName(CJobSessionInfo s) =>
            !string.IsNullOrEmpty(s.PolicyName) ? s.PolicyName : (s.JobName ?? string.Empty);
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~CSessionGroupKeyTEST"
```

Expected: all 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add "vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CSessionGroupKey.cs" \
        vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CSessionGroupKeyTEST.cs
git commit -m "feat(rollup): add CSessionGroupKey helper for GUID-based session grouping"
```

---

### Task 5: Rewrite CJobSessSummary.JobSessionSummaryToXml around CSessionGroupKey

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummary.cs`

- [ ] **Step 1: Write the failing integration test**

Append to `vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CJobSessSummaryTEST.cs` inside the existing class:

```csharp
        [Fact]
        public void JobSessionSummary_RollsUp_LinuxAgentParentAndChild_IntoSingleRow()
        {
            // Three sessions: 1 parent (PolicyTag = own JobId, no rollup needed) +
            // 2 children (PolicyTag = parent's JobId, MUST roll up under parent).
            var parentId = Guid.Parse("02fe84bc-7394-42b5-bdb2-81a56190d8c5");
            var childId  = Guid.Parse("592c44dc-861c-48fc-b70e-e9916c790222");

            var sessions = new System.Collections.Generic.List<VeeamHealthCheck.Functions.Reporting.DataTypes.CJobSessionInfo>
            {
                new() {
                    Name = "Physical - Linux Servers", JobName = "Physical - Linux Servers",
                    JobId = parentId, PolicyName = "Physical - Linux Servers", PolicyTag = parentId,
                    Status = "Success", IsRetry = "False", JobDuration = "00:00:30",
                    VmName = "", DataSize = 0, BackupSize = 0, Alg = "Full",
                    JobType = "EpAgentBackup",
                    CreationTime = DateTime.Now.AddDays(-1),
                },
                new() {
                    Name = "Physical - Linux Servers - lab01 (Incremental)",
                    JobName = "Physical - Linux Servers - lab01",
                    JobId = childId, PolicyName = "Physical - Linux Servers", PolicyTag = parentId,
                    Status = "Success", IsRetry = "False", JobDuration = "00:10:00",
                    VmName = "lab01", DataSize = 200, BackupSize = 100, Alg = "Increment",
                    JobType = "EpAgentManagement",
                    CreationTime = DateTime.Now.AddDays(-1),
                },
                new() {
                    Name = "Physical - Linux Servers - lab01 (Synthetic Full)",
                    JobName = "Physical - Linux Servers - lab01",
                    JobId = childId, PolicyName = "Physical - Linux Servers", PolicyTag = parentId,
                    Status = "Success", IsRetry = "False", JobDuration = "00:05:00",
                    VmName = "lab01", DataSize = 400, BackupSize = 50, Alg = "Full",
                    JobType = "EpAgentManagement",
                    CreationTime = DateTime.Now.AddDays(-2),
                },
            };

            var previousDtParser = VeeamHealthCheck.CGlobals.DtParser;
            var previousReportDays = VeeamHealthCheck.CGlobals.ReportDays;
            try
            {
                VeeamHealthCheck.CGlobals.DtParser = new VeeamHealthCheck.Functions.Reporting.DataTypes.CDataTypesParser();
                VeeamHealthCheck.CGlobals.DtParser.JobSessions = sessions;
                VeeamHealthCheck.CGlobals.ReportDays = 9999;

                var summary = new VeeamHealthCheck.Functions.Reporting.Html.CJobSessSummary(
                    VeeamHealthCheck.CGlobals.Logger, false, null,
                    VeeamHealthCheck.CGlobals.DtParser);
                var rows = summary.JobSessionSummaryToXml(false);

                // Exactly two rows: one for the rolled-up job, one for the Total.
                Assert.Equal(2, rows.Count);
                var jobRow = rows[0];
                Assert.Equal("Physical - Linux Servers", jobRow.JobName);
                Assert.Equal(3, jobRow.SessionCount);  // parent + 2 children
            }
            finally
            {
                VeeamHealthCheck.CGlobals.DtParser = previousDtParser;
                VeeamHealthCheck.CGlobals.ReportDays = previousReportDays;
            }
        }

        [Fact]
        public void JobSessionSummary_HyperVNoChildren_RendersOneRow()
        {
            var jobId = Guid.Parse("68621a52-2a9c-4fc5-a3f4-acc1c2caa44e");
            var sessions = new System.Collections.Generic.List<VeeamHealthCheck.Functions.Reporting.DataTypes.CJobSessionInfo>
            {
                new() {
                    Name = "Hyper-V - Engineers CHC 01", JobName = "Hyper-V - Engineers CHC 01",
                    JobId = jobId, PolicyName = null, PolicyTag = null,
                    Status = "Success", IsRetry = "False", JobDuration = "00:30:00",
                    VmName = "vm01", DataSize = 1000, BackupSize = 500, Alg = "Increment",
                    JobType = "Backup",
                    CreationTime = DateTime.Now.AddDays(-1),
                },
            };

            var previousDtParser = VeeamHealthCheck.CGlobals.DtParser;
            var previousReportDays = VeeamHealthCheck.CGlobals.ReportDays;
            try
            {
                VeeamHealthCheck.CGlobals.DtParser = new VeeamHealthCheck.Functions.Reporting.DataTypes.CDataTypesParser();
                VeeamHealthCheck.CGlobals.DtParser.JobSessions = sessions;
                VeeamHealthCheck.CGlobals.ReportDays = 9999;

                var summary = new VeeamHealthCheck.Functions.Reporting.Html.CJobSessSummary(
                    VeeamHealthCheck.CGlobals.Logger, false, null,
                    VeeamHealthCheck.CGlobals.DtParser);
                var rows = summary.JobSessionSummaryToXml(false);

                Assert.Equal(2, rows.Count);  // job + Total
                Assert.Equal("Hyper-V - Engineers CHC 01", rows[0].JobName);
                Assert.Equal(1, rows[0].SessionCount);
            }
            finally
            {
                VeeamHealthCheck.CGlobals.DtParser = previousDtParser;
                VeeamHealthCheck.CGlobals.ReportDays = previousReportDays;
            }
        }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~JobSessionSummary_RollsUp_LinuxAgentParentAndChild_IntoSingleRow|FullyQualifiedName~JobSessionSummary_HyperVNoChildren_RendersOneRow"
```

Expected: the Linux test FAILS (current code produces 2 separate rows for the parent and rolled-up child instead of 1 unified row); the Hyper-V test may PASS already.

- [ ] **Step 3: Replace the rollup block in CJobSessSummary.cs**

In `CJobSessSummary.cs`, replace lines 94-114 (everything from `// One pass to mark which names have ANY data-bearing session...` through `var childNames = rollup.ChildNames;`) and line 116-119 (the `foreach (var j in allNames)` opening + child-skip) with this:

```csharp
            // Group all sessions by their stable rollup key. Children inherit the
            // parent's PolicyTag (GUID), so grouping by CSessionGroupKey.Of merges
            // per-machine sessions under the parent without any name parsing.
            // See ADR 0019.
            var groups = helper.JobSessionInfoList()
                .GroupBy(s => CSessionGroupKey.Of(s))
                .Select(g => new
                {
                    DisplayName = g
                        .Select(s => CSessionGroupKey.DisplayName(s))
                        .FirstOrDefault(n => !string.IsNullOrEmpty(n))
                        ?? (g.First().JobName ?? string.Empty),
                    SessionNames = new HashSet<string>(
                        g.Select(s => s.Name).Where(n => !string.IsNullOrEmpty(n)),
                        StringComparer.Ordinal),
                })
                .ToList();

            int totalProtectedInstances = 0;
            foreach (var group in groups)
            {
                var j = group.DisplayName;
```

Then inside the loop, replace lines 142-145 (the `namesToAggregate` ternary) with:

```csharp
                    SessionStats thisSession = helper.SessionStats(group.SessionNames);
```

Finally, in the `_Jobs.csv` lookup block at lines 161-185, simplify the parent-TypeToString override to apply unconditionally when `_Jobs.csv` has a `TypeToString`:

Replace lines 162-177 (the entire `try` body that does the lookup and conditional override) with:

```csharp
                        CCsvParser csv = new();
                        var jobInfo = csv.JobCsvParser().Where(x => x.Name == j).FirstOrDefault();
                        if (jobInfo != null)
                        {
                            info.UsedVmSizeTB = jobInfo.OriginalSize / 1024 / 1024 / 1024 / 1024;

                            // The row's identity is now the parent's display name,
                            // so the _Jobs.csv TypeToString is always the parent's
                            // canonical type (e.g. "Backup Copy" instead of the
                            // child's "Endpoint Backup"). See ADR 0019.
                            if (!string.IsNullOrEmpty(jobInfo.TypeToString))
                            {
                                info.JobType = jobInfo.TypeToString;
                            }
                        }
```

Make sure the `using System.Linq;` and the namespace `VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.Job_Session_Summary;` at the top of the file are still present.

- [ ] **Step 4: Run tests to verify they pass**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj --filter "FullyQualifiedName~JobSessionSummary"
```

Expected: both new tests PASS.

- [ ] **Step 5: Run the full test suite to catch regressions**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj
```

Expected: all tests PASS (no regressions on the existing `CJobSessSummaryTEST` cases that exercise `SessionStats`).

- [ ] **Step 6: Commit**

```bash
git add "vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummary.cs" \
        vHC/VhcXTests/Functions/Reporting/Html/VBR/VbrTables/CJobSessSummaryTEST.cs
git commit -m "refactor(rollup): use CSessionGroupKey for GUID-based session grouping"
```

---

### Task 6: Update IndividualJobSessionsHelper.ParseIndividualSessions

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/IndividualJobSessionsHelper.cs`

- [ ] **Step 1: Replace the rollup section**

In `IndividualJobSessionsHelper.cs`, replace lines 99-106 (everything from `var allSessions = this.ReturnJobSessionsList();` through `var rollup = CJobSessSummaryHelper.BuildNameRollup(namesList);`) with:

```csharp
            var allSessions = this.ReturnJobSessionsList();

            // Group sessions by the same rollup key the summary table uses, so
            // per-machine child sessions land in the same HTML file as their
            // parent. See ADR 0019.
            var groups = allSessions
                .GroupBy(s => CSessionGroupKey.Of(s))
                .ToList();

```

Then replace the `foreach (var name in rollup.AllNames)` loop (lines 115-165) with:

```csharp
            foreach (var group in groups)
            {
                var displayName = group
                    .Select(s => CSessionGroupKey.DisplayName(s))
                    .FirstOrDefault(n => !string.IsNullOrEmpty(n))
                    ?? group.First().JobName ?? string.Empty;

                try
                {
                    var sessionsForJob = group.ToList();

                    this.LogJobSessionParseProgress(percentCounter, totalSessions);

                    string mainDir = this.SetMainDir(folderName, displayName);
                    string scrubDir = this.SetScrubDir(folderName, displayName);

                    string mainString = this.ReturnTableHeaderString(displayName);
                    File.WriteAllText(mainDir, mainString);

                    string scrubString = this.ReturnTableHeaderString(displayName);
                    File.WriteAllText(scrubDir, scrubString);

                    foreach (var cs in sessionsForJob)
                    {
                        try
                        {
                            File.AppendAllText(mainDir, this.FormHtmlString(cs, mainString, false));
                            File.AppendAllText(scrubDir, this.FormHtmlString(cs, scrubString, true));
                        }
                        catch (Exception e)
                        {
                            this.log.Error("Exception at individual job session parse:");
                            this.log.Error(e.Message);
                        }

                        percentCounter++;
                    }
                }
                catch (Exception e)
                {
                    this.log.Error($"Exception generating individual session HTML for job '{displayName}':");
                    this.log.Error(e.Message);
                }
            }
```

Add `using System.Linq;` at the top if not already present. Verify the new namespace `VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.Job_Session_Summary` resolves `CSessionGroupKey` (the file is already in that namespace).

- [ ] **Step 2: Build to confirm compile**

```bash
dotnet build vHC/HC.sln --configuration Debug
```

Expected: success.

- [ ] **Step 3: Run all tests**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj
```

Expected: all PASS.

- [ ] **Step 4: Commit**

```bash
git add "vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/IndividualJobSessionsHelper.cs"
git commit -m "refactor(rollup): switch IndividualJobSessionsHelper to GUID-based grouping"
```

---

### Task 7: Delete obsolete name-prefix rollup code

**Files:**
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummaryHelper.cs`
- Modify: `vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/IndividualJobSessionsHelper.cs`

- [ ] **Step 1: Remove the dead code**

In `CJobSessSummaryHelper.cs`, delete:

1. The `AlgorithmSuffixRegex` field (around lines 32-36).
2. The `StripAlgorithmSuffix` method (around lines 38-39).
3. The `TryGetParentPrefix` method (around lines 46-61).
4. The `NameRollup` nested class (around lines 73-79).
5. The `BuildNameRollup` method (around lines 81-135).
6. The `JobNameList` method (around lines 221-224) — no longer called after Task 5.

Also remove now-unused `using System.Text.RegularExpressions;` if present.

In `IndividualJobSessionsHelper.cs`, delete:

7. The `ReturnJobSessionsNamesList` private method (around lines 67-86) — no longer called after Task 6.

Run a check after deletion:

```bash
dotnet build vHC/HC.sln --configuration Debug 2>&1 | tee /tmp/build.log
grep -E "BuildNameRollup|TryGetParentPrefix|StripAlgorithmSuffix|JobNameList" /tmp/build.log || echo "All references removed."
```

Expected: build succeeds, grep shows no remaining references.

- [ ] **Step 2: Run all tests**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj
```

Expected: all PASS.

- [ ] **Step 3: Commit**

```bash
git add "vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/CJobSessSummaryHelper.cs" \
        "vHC/HC_Reporting/Functions/Reporting/Html/VBR/VbrTables/Job Session Summary/IndividualJobSessionsHelper.cs"
git commit -m "refactor(rollup): remove obsolete name-prefix matching code"
```

---

### Task 8: Write ADR 0019

**Files:**
- Create: `docs/adr/0019-policy-link-based-session-rollup.md`

- [ ] **Step 1: Write the ADR**

Create `docs/adr/0019-policy-link-based-session-rollup.md`:

```markdown
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
Backup Copy policy, regular Hyper-V Backup).

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
```

- [ ] **Step 2: Commit**

```bash
git add docs/adr/0019-policy-link-based-session-rollup.md
git commit -m "docs(adr): add ADR 0019 documenting policy-link-based session rollup"
```

---

### Task 9: Final build, full test suite, and cleanup of probe artefacts

**Files:**
- Delete: `probe-session-properties.ps1`, `probe-policy-link.ps1`, `probe-session-properties.csv`, `probe-policy-link.csv`, `probe-members.txt`, `results.csv`, both `Veeam Health Check Report_VBR_localhost_*.json` files at repo root

- [ ] **Step 1: Full build**

```bash
dotnet build vHC/HC.sln --configuration Debug
```

Expected: success, no warnings about unused symbols related to this change.

- [ ] **Step 2: Full xUnit run**

```bash
dotnet test vHC/VhcXTests/VhcXTests.csproj
```

Expected: all tests PASS.

- [ ] **Step 3: Full Pester run for the module**

```powershell
$pesterPaths = @(
    'vHC/HC_Reporting/Tools/Scripts/HealthCheck/VBR/vHC-VbrConfig'
)
Invoke-Pester -Path $pesterPaths -Output Detailed
```

Expected: all tests PASS, including the new `Get-VhcSessionReport.Tests.ps1`.

- [ ] **Step 4: Remove probe artefacts**

These are ephemeral diagnostic artefacts and should not be in the repo:

```bash
rm probe-session-properties.ps1 probe-policy-link.ps1
rm probe-session-properties.csv probe-policy-link.csv probe-members.txt
rm results.csv
rm "Veeam Health Check Report_VBR_localhost_2026.05.26.123917.json"
rm "Veeam Health Check Report_VBR_localhost_2026.05.27.162914.json"
```

- [ ] **Step 5: Verify nothing else references the deleted symbols**

```bash
grep -rE "BuildNameRollup|TryGetParentPrefix|StripAlgorithmSuffix|AlgorithmSuffixRegex|namesWithData" vHC docs || echo "Clean."
```

Expected output: `Clean.` (or matches only in `docs/adr/0017-rollup-policy-child-sessions.md` describing the historical design).

- [ ] **Step 6: Commit cleanup**

```bash
git add -A
git commit -m "chore: remove probe artefacts after ADR 0019 implementation"
```

- [ ] **Step 7: Push the branch**

```bash
git push origin fix/vbr-session-fast-path
```

Then verify the PR's existing description is still accurate (this work expanded the original "VBR session fast path" PR to also include the rollup rewrite — a brief PR description update may be warranted, but is at the author's discretion, not part of the plan).
