# VhcXTests CI Wiring + MFA Test Backfill

**Date:** 2026-05-05
**Priority:** ASAP
**Discovered during:** PR #129 review (MFA D:-drive fix)
**Related:** Issue #128, commit `1041d75`

## Problem (verified, not assumed)

Two test projects exist in the repo:

| Project | Files | Where it runs in CI |
|---|---|---|
| `vHC/VhcXTests/` | 32 test files (xUnit + Moq + coverlet, Windows-only, full WPF deps) | **Nowhere — does not execute in CI** |
| `vHC/VhcXTests.CrossPlatform/` | 2 test files (CHostNameHelperTests, HtmlStructureTests) | `crossplatform-tests.yml` on ubuntu + macos — runs ~14 tests, all passing |

Root cause:

```
$ dotnet sln vHC/HC.sln list
Project(s)
----------
HC_Reporting/VeeamHealthCheck.csproj
```

`HC.sln` references only the main project. Both `ci-cd.yaml` (line ~40) and `pr-release-prep.yml` (line 36) invoke `dotnet test vHC/HC.sln`, so the test run discovers zero tests. Verified in run logs:

- Run `25396813454` (sha `1041d75`) — "Run tests with coverage" finished in **0.56s**, no test discovery output, "Generate coverage report" fell into the `No coverage files found` branch.
- Run `25339190612` (sha `ab8d967`) — same pattern, **0.57s**, no test output.

So 32 test files compile successfully on every push but never execute. Coverage reporting is configured (coverlet + ReportGenerator) but produces no data because no tests run.

## Fix (smallest change first)

### Step 1: Wire `VhcXTests` into the solution
- `dotnet sln vHC/HC.sln add vHC/VhcXTests/VhcXTests.csproj`
- Do NOT add `VhcXTests.CrossPlatform.csproj` — it targets `net10.0` and is invoked directly by `crossplatform-tests.yml`. Keeping it out of the sln avoids dragging the net10 framework into the main build.
- Push to `dev` and watch `ci-cd.yaml` "Run tests with coverage" — it should now show `Discovering: VhcXTests`, real pass/fail counts, and produce a `coverage.cobertura.xml` artifact.

### Step 2: Establish baseline coverage
- After Step 1, download the `code-coverage-report` artifact from a `dev` push.
- Record the line/branch coverage % per assembly. This is the baseline.
- Decide whether to add a coverage threshold gate (e.g., fail if line coverage drops below the baseline). Not required for this plan to land; can be a follow-up.

### Step 3: Backfill MFA path-resolution tests (Pester)
- The MFA fix (`1041d75`) modified `vHC/HC_Reporting/Functions/Collection/PSCollections/Scripts/TestMfa.ps1`. The path-resolution logic lives in PowerShell, so xUnit can't directly cover it. Use Pester.
- Add `vHC/HC_Reporting/Functions/Collection/PSCollections/Scripts/TestMfa.Tests.ps1` with three behavior tests for `Resolve-VeeamConsolePath`:
  1. Registry `CorePath = "D:\Program Files\Veeam\Backup and Replication\Backup\"` and Console exists at the install root → returns `"D:\...\Console"`. **This is the regression test for #128 / `1041d75`.**
  2. Registry missing or UNC → falls back to `$env:ProgramFiles`, returns the env-derived path when Console exists there.
  3. All candidates miss → returns `$null` and `Write-Error` fires with a "Paths attempted" listing.
- Mock `Get-ItemProperty`, `Test-Path`, and `$env:ProgramFiles` in scope so the tests don't touch the real registry or filesystem.
- Wire Pester execution into `ps51-syntax-validation.yml` as a new job (cheapest), or add a dedicated `pester-tests.yml` workflow.
- While there, add `Functions/Collection/PSCollections/Scripts/TestMfa.ps1` to the `ps51-syntax-validation.yml` script list — currently that workflow's parse check skips this file entirely.

## Decisions still open

1. **Coverage gate threshold.** Defer until we have a baseline number from Step 2.
2. **Pester wiring location.** Extend `ps51-syntax-validation.yml` (cheap, less YAML) vs. new `pester-tests.yml` (cleaner separation). Recommend extending unless the parse-validation workflow gets too crowded.
3. **`pr-release-prep.yml`.** It also runs `dotnet test vHC/HC.sln` and skips coverage collection. After Step 1, it will run the Windows tests too. No change needed unless we want to mirror coverage collection there.

## Verification (per step)

- **Step 1:** Run `dotnet sln vHC/HC.sln list` locally — must show both `VeeamHealthCheck.csproj` and `VhcXTests.csproj`. Push to a branch and confirm the `ci-cd.yaml` test step output now contains `Discovering / Discovered / Total tests / Passed`.
- **Step 2:** Download `code-coverage-report` artifact from a successful run; confirm Cobertura XML and HTML report exist. Record baseline %.
- **Step 3:** A Pester run against the *pre-fix* version of `TestMfa.ps1` must FAIL test 1 (regression test). Against the post-fix version (`1041d75`+) all three pass.

## Out of scope for this plan

- Refactoring the path-resolution logic into C# (would enable xUnit coverage of it but is a larger move).
- Adding a coverage threshold gate (do after baseline is known).
- Migrating any of the 32 Windows tests into the cross-platform project.

## Working-tree note

At time of writing, `dev` HEAD is `1041d75` and PR #129 (`Sync dev → master`) is open. This plan can land as one or more follow-up commits on `dev` (after #129 merges, or in parallel — no file conflicts).
