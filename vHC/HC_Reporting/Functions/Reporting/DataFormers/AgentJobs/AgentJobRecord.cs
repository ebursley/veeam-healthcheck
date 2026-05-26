namespace VeeamHealthCheck.Functions.Reporting.DataFormers.AgentJobs
{
    /// <summary>
    /// Normalized view of a single Veeam Agent job (managed or standalone)
    /// for the report renderers. Produced by AgentJobAggregator.
    /// </summary>
    public class AgentJobRecord
    {
        public string JobName { get; set; }
        public string JobType { get; set; }
        public string FriendlyType { get; set; }
        public string RepoName { get; set; }
        public double SourceSizeGB { get; set; }
        public double OnDiskGB { get; set; }
        public string RetentionScheme { get; set; }
        public string RetainDays { get; set; }
        public string Encrypted { get; set; }
        public string CompressionLevel { get; set; }
        public string BlockSize { get; set; }
        public bool GfsEnabled { get; set; }
        public string GfsDetails { get; set; }
        public string ActiveFullEnabled { get; set; }
        public bool SyntheticFullEnabled { get; set; }
        public string BackupChainType { get; set; }
        public bool IndexingEnabled { get; set; }
        public string AAIPEnabled { get; set; }
        public string VSSEnabled { get; set; }
        public string VSSIgnoreErrors { get; set; }
        public string GuestFSIndexing { get; set; }
        public string Platform { get; set; }
    }
}
