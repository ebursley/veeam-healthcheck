// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Hardware Plans" renderer.
    /// Mirrors CCloudFailoverPlansTableTests: reuses VbrTableScrubTestBase (isolated
    /// VbrDir + CGlobals state) so the renderer's CCsvParser reads our sample
    /// _CloudHardwarePlans.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: name, hostname. No description column — test (c)
    /// anonymizes name + host and asserts a non-PII column (platform) still renders.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudHardwarePlansTableTests : VbrTableScrubTestBase
    {
        public CCloudHardwarePlansTableTests() : base("VhcCloudHardwarePlansTests_") { }

        private const string Headers =
            "name,platform,cpumhz,memorymb,networkswithinternet,networkswithoutinternet," +
            "subscribedtenantcount,totaldatastorequotagb,hostname";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudHardwarePlans.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudHardwarePlansTable().Render(scrub: false);
            Assert.Contains("No cloud hardware plans detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-HWPlan,VMware,8000,16384,2,1,5,2048,acme-esxi01");

            string html = new CCloudHardwarePlansTable().Render(scrub: false);

            Assert.Contains("ACME-HWPlan", html);
            Assert.Contains("acme-esxi01", html);
            Assert.Contains("VMware", html);
            Assert.DoesNotContain("No cloud hardware plans detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-HWPlan,VMware,8000,16384,2,1,5,2048,acme-esxi01");

            string html = new CCloudHardwarePlansTable().Render(scrub: true);

            // PII columns (name, hostname) must not leak under scrub
            Assert.DoesNotContain("ACME-HWPlan", html);
            Assert.DoesNotContain("acme-esxi01", html);
            // non-PII column still renders
            Assert.Contains("VMware", html);
        }
    }
}
