using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using VeeamHealthCheck.Functions.Reporting.Html.DataFormers;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.DataFormers
{
    [Trait("Category", "JobTypes")]
    public class CJobTypesParserTests
    {
        [Fact]
        public void GetJobType_EpAgentBackup_ReturnsWindowsAgentBackup()
        {
            var result = CJobTypesParser.GetJobType("EpAgentBackup");
            Assert.Equal("Windows Agent Backup", result);
        }

        [Fact]
        public void GetJobType_EpAgentPolicy_ReturnsWindowsAgentPolicy()
        {
            var result = CJobTypesParser.GetJobType("EpAgentPolicy");
            Assert.Equal("Windows Agent Policy", result);
        }

        [Fact]
        public void GetJobType_NullInput_ReturnsOther()
        {
            var result = CJobTypesParser.GetJobType(null);
            Assert.Equal("Other", result);
        }

        [Fact]
        public void GetJobType_UnknownType_ReturnsInputAsIs()
        {
            var result = CJobTypesParser.GetJobType("UnknownType123");
            Assert.Equal("UnknownType123", result);
        }

        [Fact]
        public void GetJobType_EndpointBackup_ReturnsAgentBackup()
        {
            var result = CJobTypesParser.GetJobType("EndpointBackup");
            Assert.Equal("Agent Backup", result);
        }

        // ResolveJobFriendlyType tests (ADR 0020)

        [Fact]
        public void ResolveJobFriendlyType_AgentFriendlyTypeSet_ReturnsAgentFriendlyType()
        {
            var row = new CJobCsvInfos { JobType = "EpAgentBackup", TypeToString = "Windows Agent Backup" };
            var result = CJobTypesParser.ResolveJobFriendlyType(row, "Windows Agent Standalone");
            Assert.Equal("Windows Agent Standalone", result);
        }

        [Fact]
        public void ResolveJobFriendlyType_TypeToStringPresent_ReturnsTypeToString()
        {
            var row = new CJobCsvInfos { JobType = "VmbApiPolicyTempJob", TypeToString = "Proxmox Backup" };
            var result = CJobTypesParser.ResolveJobFriendlyType(row);
            Assert.Equal("Proxmox Backup", result);
        }

        [Fact]
        public void ResolveJobFriendlyType_EmptyTypeToString_ReturnsParserFallback()
        {
            var row = new CJobCsvInfos { JobType = "Backup", TypeToString = string.Empty };
            var result = CJobTypesParser.ResolveJobFriendlyType(row);
            Assert.Equal("Backup", result);
        }

        [Fact]
        public void ResolveJobFriendlyType_NullRow_ReturnsOther()
        {
            var result = CJobTypesParser.ResolveJobFriendlyType(null);
            Assert.Equal("Other", result);
        }
    }
}
