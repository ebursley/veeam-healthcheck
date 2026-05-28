using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers.VB365;
using VeeamHealthCheck.Shared;

namespace VeeamHealthCheck.Functions.Reporting.Html.DataFormers
{
    public class CJobTypesParser
    {
        public static string GetJobType(string jobType)
        {
            if(CGlobals.DEBUG){
                CGlobals.Logger.Debug("JobType = " + jobType);
            }

            if (jobType == null)
                return "Other";

            switch (jobType)
            {
                case "Copy":
                    return "File Copy";
                case "SimpleBackupCopyPolicy":
                    return "Backup Copy";
                case "NasBackup":
                    return "File Backup";
                case "ENasBackup":
                    return "File Backup";
                case "Backup":
                    return "Backup";
                case "Replica":
                    return "Replica";
                case "NasBackupCopy":
                    return "File Backup - Copy";
                case "MSSQLPlugin":
                    return "MS SQL Plugin";
                case "SureBackup":
                    return "SureBackup";
                case "FileTapeBackup":
                    return "Tape";
                case "VmTapeBackup":
                    return "Tape";
                case "BackupSync":
                    return "Backup Copy";
                case "SqlLogBackup":
                    return "SQL Log Backup";
                case "OracleLogBackup":
                    return "Oracle Log Backup";
                case "SimpleBackupCopyWorker":
                    return "Backup Copy";
                case "ConfBackup":
                    return "Configuration Backup";
                case "Cloud":
                    return "Cloud Backup";
                case "OrchestratedTask":
                    return "Orchestrated Task";
                case "OracleRMANBackup":
                    return "Enterprise Database Plugin";
                case "SapBackintBackup":
                    return "Enterprise Database Plugin";
                case "EpAgentBackup":
                    return "Windows Agent Backup";
                case "EpAgentPolicy":
                    return "Windows Agent Policy";
                case "EndpointBackup":
                    return "Agent Backup";
                case "EpAgentManagement":
                    return "Agent Backup";
                case "ELinuxPhysical":
                    return "Agent Backup";
                case "EEndPoint":
                    return "Endpoint Backup";
                case "EHyperV":
                    return "Hyper-V Backup";
                case "EVmware":
                    return "VMware Backup";
                case "":
                    return "Other";
                default:
                    return jobType;
            }
        }

        /// <summary>
        /// Resolves the human-readable job type with the same precedence used by
        /// <c>CJobSessSummary</c> (see ADR 0020):
        /// <list type="number">
        ///   <item><c>agentFriendlyType</c> when non-empty — already resolved by
        ///   <c>AgentJobAggregator</c> and includes the Standalone/Managed distinction.</item>
        ///   <item><c>row.TypeToString</c> when non-empty — the Veeam-API-supplied label,
        ///   covers third-party plug-in types (Proxmox, AHV, etc.).</item>
        ///   <item><c>GetJobType(row.JobType)</c> — enum-switch fallback.</item>
        /// </list>
        /// Pass <c>agentRecord?.FriendlyType</c> as <paramref name="agentFriendlyType"/>
        /// rather than the record itself to avoid a namespace cycle with
        /// <c>AgentJobAggregator</c>.
        /// </summary>
        public static string ResolveJobFriendlyType(CJobCsvInfos row, string agentFriendlyType = null)
        {
            if (!string.IsNullOrEmpty(agentFriendlyType))
                return agentFriendlyType;

            if (row != null && !string.IsNullOrEmpty(row.TypeToString))
                return row.TypeToString;

            return GetJobType(row?.JobType);
        }
    }
}
