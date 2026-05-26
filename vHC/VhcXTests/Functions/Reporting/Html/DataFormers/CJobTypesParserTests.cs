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
    }
}
