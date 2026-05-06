using CsvHelper.Configuration.Attributes;
using System;

namespace VeeamHealthCheck.Functions.Reporting.CsvHandlers
{
    public class CComplianceMetaCsv
    {
        [Name("ScanStartedAt")]
        public DateTime? ScanStartedAt { get; set; }

        [Name("ScanCompletedAt")]
        public DateTime? ScanCompletedAt { get; set; }

        [Name("ScanDurationSeconds")]
        public double ScanDurationSeconds { get; set; }

        [Name("ScanStatus")]
        public string ScanStatus { get; set; }
    }
}
