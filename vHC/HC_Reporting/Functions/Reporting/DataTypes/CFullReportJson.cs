using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using VeeamHealthCheck.Functions.Analysis.DataModels;

namespace VeeamHealthCheck.Functions.Reporting.DataTypes
{
    internal class CFullReportJson
    {
        public CProtectedWorkloads cProtectedWorkloads { get; set; }

        // License data captured from CHtmlTables.LicTable
        public List<License> Licenses { get; set; } = new();

        public string LicenseSummary { get; set; }

        // Compliance scan telemetry — populated by CComplianceTable from
        // _SecurityComplianceMeta.csv. Stable contract for VIP ingestion.
        public ComplianceScanMeta ComplianceScan { get; set; }

        // Generic sections for other HTML tables
        public Dictionary<string, HtmlSection> Sections { get; set; } = new();
    }
}
