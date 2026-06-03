// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Coverage for the Cloud Connect "Cloud Failover Plans" renderer, which shipped
    /// in d3ccd0e without tests. Reuses the existing VbrTableScrubTestBase harness
    /// (sets up an isolated VbrDir + CGlobals state) so the renderer's CCsvParser
    /// reads our sample CSV instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// collector or wrong column silently produces empty/partial HTML rather than
    /// throwing — exactly why these characterization tests assert on rendered content.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudFailoverPlansTableTests : VbrTableScrubTestBase
    {
        public CCloudFailoverPlansTableTests() : base("VhcCloudFailoverPlansTests_") { }

        private const string Headers =
            "name,description,type,platform,status,vmcount,prefailovercommand,postfailovercommand,publicipenabled";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudFailoverPlans.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudFailoverPlansTable().Render(scrub: false);
            Assert.Contains("No cloud failover plans detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-FailoverPlan,Critical DR for acme.corp,Cloud,VMware,Ready,12,pre.cmd,post.cmd,True");

            string html = new CCloudFailoverPlansTable().Render(scrub: false);

            Assert.Contains("ACME-FailoverPlan", html);
            Assert.Contains("Critical DR for acme.corp", html);
            Assert.Contains("VMware", html);
            Assert.DoesNotContain("No cloud failover plans detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-FailoverPlan,Critical DR for acme.corp,Cloud,VMware,Ready,12,pre.cmd,post.cmd,True");

            string html = new CCloudFailoverPlansTable().Render(scrub: true);

            // PII columns (name, description) must not leak under scrub
            Assert.DoesNotContain("ACME-FailoverPlan", html);
            Assert.DoesNotContain("acme.corp", html);
            // non-PII columns still render
            Assert.Contains("VMware", html);
        }
    }
}
