// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Gateways" renderer.
    /// Mirrors CCloudFailoverPlansTableTests exactly: reuses VbrTableScrubTestBase
    /// (isolated VbrDir + CGlobals state) so the renderer's CCsvParser reads our
    /// sample _CloudGateways.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: name, description, ipaddress, hostname.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudGatewaysTableTests : VbrTableScrubTestBase
    {
        public CCloudGatewaysTableTests() : base("VhcCloudGatewaysTests_") { }

        private const string Headers =
            "name,description,ipaddress,networkmode,incomingport,natport,hostname,enabled";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudGateways.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudGatewaysTable().Render(scrub: false);
            Assert.Contains("No cloud gateways detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-Gateway,Edge gateway for acme.corp,203.0.113.10,DirectMode,6180,33,acme-host01,True");

            string html = new CCloudGatewaysTable().Render(scrub: false);

            Assert.Contains("ACME-Gateway", html);
            Assert.Contains("Edge gateway for acme.corp", html);
            Assert.Contains("DirectMode", html);
            Assert.DoesNotContain("No cloud gateways detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-Gateway,Edge gateway for acme.corp,203.0.113.10,DirectMode,6180,33,acme-host01,True");

            string html = new CCloudGatewaysTable().Render(scrub: true);

            // PII columns (name, description) must not leak under scrub
            Assert.DoesNotContain("ACME-Gateway", html);
            Assert.DoesNotContain("acme.corp", html);
            // non-PII column still renders
            Assert.Contains("DirectMode", html);
        }
    }
}
