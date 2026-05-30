using CsvHelper.Configuration.Attributes;

namespace VeeamHealthCheck.Functions.Reporting.CsvHandlers
{
    public class CComplianceCatalogCsv
    {
        [Name("RuleType")]
        public string RuleType { get; set; }

        [Name("MappedLabel")]
        public string MappedLabel { get; set; }

        [Name("IsMapped")]
        public bool IsMapped { get; set; }

        [Name("LabelSource")]
        public string LabelSource { get; set; }

        [Name("VbrVersion")]
        public string VbrVersion { get; set; }

        [Name("ValidatedFor")]
        public string ValidatedFor { get; set; }
    }
}
