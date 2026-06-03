// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Failover Plan VMs"
    /// renderer (CCloudFailoverPlanObjectsTable). Mirrors CCloudFailoverPlansTableTests:
    /// reuses VbrTableScrubTestBase (isolated VbrDir + CGlobals state) so the
    /// renderer's CCsvParser reads our sample _CloudFailoverPlanObjects.csv instead
    /// of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: failoverplanname, vmname. No description column —
    /// test (c) anonymizes plan + VM name and asserts a non-PII column
    /// (publiciprule) still renders.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudFailoverPlanObjectsTableTests : VbrTableScrubTestBase
    {
        public CCloudFailoverPlanObjectsTableTests() : base("VhcCloudFailoverPlanObjectsTests_") { }

        private const string Headers =
            "failoverplanname,vmname,bootorder,bootdelay,publiciprule";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudFailoverPlanObjects.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudFailoverPlanObjectsTable().Render(scrub: false);
            Assert.Contains("No cloud failover plan VMs detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-FailoverPlan,acme-web01,1,30,MapToExisting");

            string html = new CCloudFailoverPlanObjectsTable().Render(scrub: false);

            Assert.Contains("ACME-FailoverPlan", html);
            Assert.Contains("acme-web01", html);
            Assert.Contains("MapToExisting", html);
            Assert.DoesNotContain("No cloud failover plan VMs detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-FailoverPlan,acme-web01,1,30,MapToExisting");

            string html = new CCloudFailoverPlanObjectsTable().Render(scrub: true);

            // PII columns (failover plan name, VM name) must not leak under scrub
            Assert.DoesNotContain("ACME-FailoverPlan", html);
            Assert.DoesNotContain("acme-web01", html);
            // non-PII column still renders
            Assert.Contains("MapToExisting", html);
        }
    }
}
