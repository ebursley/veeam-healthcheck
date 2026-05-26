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
