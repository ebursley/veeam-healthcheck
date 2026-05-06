using System;

namespace VeeamHealthCheck.Functions.Analysis.DataModels
{
    internal class ComplianceScanMeta
    {
        public DateTime? StartedAt { get; set; }

        public DateTime? CompletedAt { get; set; }

        public double DurationSeconds { get; set; }

        // "Completed" | "TimedOut" | "Failed" | "Unknown"
        public string Status { get; set; }

        public int RuleCount { get; set; }
    }
}
