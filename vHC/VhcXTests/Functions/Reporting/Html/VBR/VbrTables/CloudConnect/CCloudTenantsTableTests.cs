// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Tenants" renderer.
    /// Mirrors CCloudFailoverPlansTableTests exactly: reuses VbrTableScrubTestBase
    /// (isolated VbrDir + CGlobals state) so the renderer's CCsvParser reads our
    /// sample _CloudTenants.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: name, description, gatewaypoolname.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudTenantsTableTests : VbrTableScrubTestBase
    {
        public CCloudTenantsTableTests() : base("VhcCloudTenantsTests_") { }

        private const string Headers =
            "name,description,enabled,type,lastactive,lastresult,vmcount,servercount,workstationcount,replicacount," +
            "newvmbackupcount,newserverbackupcount,newworkstationbackupcount,newreplicacount," +
            "rentalvmbackupcount,rentalserverbackupcount,rentalworkstationbackupcount,rentalreplicacount," +
            "maxconcurrenttask,throttlingenabled,throttlingvalue,throttlingunit,gatewayselectiontype," +
            "gatewaypoolname,gatewayfailoverenabled,leaseexpirationenabled,leaseexpirationdate," +
            "backupprotectionenabled,backupprotectionperiod";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudTenants.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudTenantsTable().Render(scrub: false);
            Assert.Contains("No cloud tenants detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            // ThrottlingEnabled=False → value/unit render as "—" (new behavior).
            // This test verifies the tenant name, description and non-throttle fields only.
            WriteCsv("ACME-Tenant,Production tenant for acme.corp,True,Standalone,2026-01-01,Success,12,3,4,2," +
                     "1,0,0,0,5,1,0,0,4,False,0,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantsTable().Render(scrub: false);

            Assert.Contains("ACME-Tenant", html);
            Assert.Contains("Production tenant for acme.corp", html);
            Assert.Contains("Standalone", html);
            Assert.DoesNotContain("No cloud tenants detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-Tenant,Production tenant for acme.corp,True,Standalone,2026-01-01,Success,12,3,4,2," +
                     "1,0,0,0,5,1,0,0,4,False,0,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantsTable().Render(scrub: true);

            // PII columns (name, description) must not leak under scrub
            Assert.DoesNotContain("ACME-Tenant", html);
            Assert.DoesNotContain("acme.corp", html);
            // non-PII column still renders
            Assert.Contains("Standalone", html);
        }

        [Fact]
        public void Render_MaxConcurrentTaskZero_DisplaysUnlimited()
        {
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,0,False,0,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantsTable().Render(scrub: false);

            Assert.Contains("Unlimited", html);
        }

        [Fact]
        public void Render_MaxConcurrentTaskEmpty_DisplaysUnlimited()
        {
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,,False,0,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantsTable().Render(scrub: false);

            Assert.Contains("Unlimited", html);
        }

        [Fact]
        public void Render_ThrottlingDisabled_DisplaysDashForValueAndUnit()
        {
            // ThrottlingEnabled=False → value and unit should show "—", not the raw values
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,4,False,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantsTable().Render(scrub: false);

            Assert.Contains("—", html);
            Assert.DoesNotContain("500", html);
            Assert.DoesNotContain("MbytePerSec", html);
        }

        [Fact]
        public void Render_ThrottlingEnabled_DisplaysActualValues()
        {
            // ThrottlingEnabled=True → value and unit should show actual values
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,4,True,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantsTable().Render(scrub: false);

            Assert.Contains("500", html);
            Assert.Contains("MbytePerSec", html);
        }

        [Fact]
        public void Render_Headers_ContainsMaxBandwidthAndBandwidthUnit()
        {
            string html = new CCloudTenantsTable().Render(scrub: false);

            Assert.Contains("Max Bandwidth", html);
            Assert.Contains("Bandwidth Unit", html);
            Assert.DoesNotContain("Throttle Value", html);
            Assert.DoesNotContain("Throttle Unit", html);
        }
    }
}
