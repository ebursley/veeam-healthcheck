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
    }
}
