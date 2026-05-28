using System;
using System.Collections.Generic;
using System.Linq;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs;
using VeeamHealthCheck.Functions.Reporting.Html.DataFormers;
using VeeamHealthCheck.Shared;
using static VeeamHealthCheck.Functions.Collection.DB.CModel;

namespace VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables
{
    internal class CJobSummaryTable
    {
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

                // Calling AgentJobAggregator.Build directly on the already-materialized
                // backupJobs list avoids constructing a CDataFormer here — that constructor
                // eagerly reads four proxy CSVs and logs a warning when they're missing,
                // which is irrelevant noise for the job-summary path.
                var agentJobs = AgentJobAggregator.Build(backupJobs);
                foreach (var grouping in agentJobs.GroupBy(a => a.FriendlyType))
                {
                    if (!typeAndCount.ContainsKey(grouping.Key))
                    {
                        typeAndCount.Add(grouping.Key, grouping.Count());
                    }
                }

                // "Agent Standalone" is always seeded — standalone agent jobs are an
                // independent category that should appear as missing regardless of whether
                // managed agent jobs exist.
                if (!typeAndCount.ContainsKey("Agent Standalone"))
                {
                    typeAndCount.Add("Agent Standalone", 0);
                }

                // "Agent Backup" is only seeded when no agent jobs exist at all. If modern
                // agent jobs (EpAgentBackup etc.) are present, the dynamic loop already wrote
                // their FriendlyType labels ("Windows Agent Backup" etc.) and seeding "Agent
                // Backup" here would be a false-positive missing-job alert.
                if (!agentJobs.Any() && !typeAndCount.ContainsKey("Agent Backup"))
                {
                    typeAndCount.Add("Agent Backup", 0);
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

                        if (AgentJobAggregator.AgentJobTypes.Contains(bType))
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
