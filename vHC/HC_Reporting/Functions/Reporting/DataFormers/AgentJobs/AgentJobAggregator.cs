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
