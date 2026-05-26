using System.Collections.Generic;
using System.Linq;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using VeeamHealthCheck.Functions.Reporting.Html.DataFormers;

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
                    FriendlyType = ResolveFriendlyType(r),
                })
                .ToList();
        }

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
    }
}
