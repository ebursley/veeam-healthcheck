// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Hardware Plan Datastores"
    /// renderer. Mirrors CCloudFailoverPlansTableTests: reuses VbrTableScrubTestBase
    /// (isolated VbrDir + CGlobals state) so the renderer's CCsvParser reads our
    /// sample _CloudHardwarePlanDatastores.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: hardwareplanname, datastorefriendlyname, datastorepath.
    /// No name/description pair — test (c) anonymizes plan + datastore + path and
    /// asserts a non-PII column (quotagb) still renders.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudHardwarePlanDatastoresTableTests : VbrTableScrubTestBase
    {
        public CCloudHardwarePlanDatastoresTableTests() : base("VhcCloudHardwarePlanDatastoresTests_") { }

        private const string Headers =
            "hardwareplanname,datastorefriendlyname,datastorepath,quotagb";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudHardwarePlanDatastores.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudHardwarePlanDatastoresTable().Render(scrub: false);
            Assert.Contains("No cloud hardware plan datastores detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-HWPlan,acme.corp Datastore,[acme-ds01] volumes/acme,4096");

            string html = new CCloudHardwarePlanDatastoresTable().Render(scrub: false);

            Assert.Contains("ACME-HWPlan", html);
            Assert.Contains("acme.corp Datastore", html);
            Assert.Contains("4096", html);
            Assert.DoesNotContain("No cloud hardware plan datastores detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-HWPlan,acme.corp Datastore,[acme-ds01] volumes/acme,4096");

            string html = new CCloudHardwarePlanDatastoresTable().Render(scrub: true);

            // PII columns (plan, datastore name, path) must not leak under scrub
            Assert.DoesNotContain("ACME-HWPlan", html);
            Assert.DoesNotContain("acme.corp", html);
            Assert.DoesNotContain("acme-ds01", html);
            // non-PII column still renders
            Assert.Contains("4096", html);
        }
    }
}
