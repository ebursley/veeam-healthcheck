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

        private const string GatewayHeaders =
            "name,description,ipaddress,networkmode,incomingport,natport,hostname,enabled";

        // Server CSV: 15 required columns (0–14), indices match CServerCsvInfos.
        // Index: 0=Info, 1=ParentId, 2=Id, 3=Uid, 4=Name, 5=Reference, 6=Description,
        //        7=IsUnavailable, 8=Type, 9=ApiVersion, 10=PhysHostId, 11=ProxyServicesCreds,
        //        12=Cores, 13=CPU, 14=Ram
        private const string ServerHeaders =
            "Info,ParentId,Id,Uid,Name,Reference,Description,IsUnavailable,Type,ApiVersion,PhysHostId,ProxyServicesCreds,Cores,CPU,Ram";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudGateways.csv"), GatewayHeaders + "\n" + rows);

        private void WriteServerCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_Servers.csv"), ServerHeaders + "\n" + rows);

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

        [Fact]
        public void Render_ServerRamPresent_DisplaysGigabytes()
        {
            // 410665353216 bytes = 382.something GB → rounds to 382
            WriteCsv("ACME-Gateway,Edge gateway,203.0.113.10,DirectMode,6180,33,gw-host01,True");
            WriteServerCsv("info1,parentid1,id1,uid1,gw-host01,ref1,desc1,False,Windows,12,physid1,creds1,32,Intel Xeon,410665353216");

            string html = new CCloudGatewaysTable().Render(scrub: false);

            Assert.Contains("382 GB", html);
            Assert.DoesNotContain("410665353216", html);
        }

        [Fact]
        public void Render_ServerRamUnparseable_DisplaysRawValue()
        {
            WriteCsv("ACME-Gateway,Edge gateway,203.0.113.10,DirectMode,6180,33,gw-host01,True");
            WriteServerCsv("info1,parentid1,id1,uid1,gw-host01,ref1,desc1,False,Windows,12,physid1,creds1,32,Intel Xeon,not-a-number");

            string html = new CCloudGatewaysTable().Render(scrub: false);

            Assert.Contains("not-a-number", html);
        }

        [Fact]
        public void Render_ServerRamEmpty_RendersWithoutCrash()
        {
            WriteCsv("ACME-Gateway,Edge gateway,203.0.113.10,DirectMode,6180,33,gw-host01,True");
            WriteServerCsv("info1,parentid1,id1,uid1,gw-host01,ref1,desc1,False,Windows,12,physid1,creds1,32,Intel Xeon,");

            // Should not throw; no raw bytes string in output
            string html = new CCloudGatewaysTable().Render(scrub: false);

            Assert.DoesNotContain("No cloud gateways detected", html);
            // Empty RAM — just verify the row rendered and no byte-style number leaked
            Assert.Contains("DirectMode", html);
        }
    }
}
