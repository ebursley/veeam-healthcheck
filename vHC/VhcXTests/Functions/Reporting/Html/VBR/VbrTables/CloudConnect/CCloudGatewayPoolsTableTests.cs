// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Gateway Pools" renderer.
    /// Mirrors CCloudFailoverPlansTableTests: reuses VbrTableScrubTestBase (isolated
    /// VbrDir + CGlobals state) so the renderer's CCsvParser reads our sample
    /// _CloudGatewayPools.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: poolname, description, gatewayname — ALL THREE string
    /// columns are scrubbed, so test (c) has no non-PII column to assert survives.
    /// Instead it asserts PII is absent AND the empty-state message is absent
    /// (proving a data row rendered under scrub).
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudGatewayPoolsTableTests : VbrTableScrubTestBase
    {
        public CCloudGatewayPoolsTableTests() : base("VhcCloudGatewayPoolsTests_") { }

        private const string Headers = "poolname,description,gatewayname";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudGatewayPools.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudGatewayPoolsTable().Render(scrub: false);
            Assert.Contains("No cloud gateway pools detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-Pool,Pool for acme.corp gateways,acme-gw01");

            string html = new CCloudGatewayPoolsTable().Render(scrub: false);

            Assert.Contains("ACME-Pool", html);
            Assert.Contains("Pool for acme.corp gateways", html);
            Assert.Contains("acme-gw01", html);
            Assert.DoesNotContain("No cloud gateway pools detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-Pool,Pool for acme.corp gateways,acme-gw01");

            string html = new CCloudGatewayPoolsTable().Render(scrub: true);

            // All string columns (poolname, description, gatewayname) are scrubbed PII.
            // PII must not leak under scrub.
            Assert.DoesNotContain("ACME-Pool", html);
            Assert.DoesNotContain("acme.corp", html);
            Assert.DoesNotContain("acme-gw01", html);
            // No non-PII survivor column exists; instead prove a row still rendered
            // (the empty-state message is absent because data was present).
            Assert.DoesNotContain("No cloud gateway pools detected", html);
        }
    }
}
