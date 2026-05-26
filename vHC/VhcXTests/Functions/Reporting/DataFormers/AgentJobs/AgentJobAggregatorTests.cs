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
    }
}
