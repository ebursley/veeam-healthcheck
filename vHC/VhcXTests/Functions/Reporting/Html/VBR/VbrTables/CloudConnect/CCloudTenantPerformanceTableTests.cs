// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization tests for the Cloud Connect "Tenant Performance Settings" renderer.
    /// Reuses VbrTableScrubTestBase so the renderer's CCsvParser reads our sample
    /// _CloudTenants.csv instead of live VBR output.
    ///
    /// The table reads the same _CloudTenants.csv as CCloudTenantsTable; it renders
    /// only the performance-relevant columns (6 columns total).
    /// Scrubbed PII field: name only.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudTenantPerformanceTableTests : VbrTableScrubTestBase
    {
        public CCloudTenantPerformanceTableTests() : base("VhcCloudTenantPerfTests_") { }

        // Same 29-column header as CCloudTenantsTable — the renderer reads the same CSV file.
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
            string html = new CCloudTenantPerformanceTable().Render(scrub: false);
            Assert.Contains("No cloud tenants detected", html);
        }

        [Fact]
        public void Render_ColumnHeaders_ContainsAllSixHeaders()
        {
            string html = new CCloudTenantPerformanceTable().Render(scrub: false);

            Assert.Contains("Tenant", html);
            Assert.Contains("Enabled", html);
            Assert.Contains("Max Concurrent Tasks", html);
            Assert.Contains("Bandwidth Throttling", html);
            Assert.Contains("Max Bandwidth", html);
            Assert.Contains("Bandwidth Unit", html);
        }

        [Fact]
        public void Render_SectionId_ContainsCloudTenantPerfAnchor()
        {
            string html = new CCloudTenantPerformanceTable().Render(scrub: false);

            Assert.Contains("cloudtenantperf", html);
        }

        [Fact]
        public void Render_MaxConcurrentTaskZero_DisplaysUnlimited()
        {
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,0,True,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantPerformanceTable().Render(scrub: false);

            Assert.Contains("Unlimited", html);
        }

        [Fact]
        public void Render_MaxConcurrentTaskPositive_DisplaysNumericValue()
        {
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,8,True,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantPerformanceTable().Render(scrub: false);

            Assert.Contains("8", html);
            Assert.DoesNotContain("Unlimited", html);
        }

        [Fact]
        public void Render_ThrottlingDisabled_DisplaysDashForValueAndUnit()
        {
            // ThrottlingEnabled=False → value and unit render as "—"
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,4,False,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantPerformanceTable().Render(scrub: false);

            Assert.Contains("—", html);
            Assert.DoesNotContain("500", html);
            Assert.DoesNotContain("MbytePerSec", html);
        }

        [Fact]
        public void Render_ThrottlingEnabled_DisplaysValueAndUnit()
        {
            // ThrottlingEnabled=True → value and unit render as actual values
            WriteCsv("ACME-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,4,True,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantPerformanceTable().Render(scrub: false);

            Assert.Contains("500", html);
            Assert.Contains("MbytePerSec", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesTenantNameOnly()
        {
            // Name is scrubbed; numeric MCT value (8) must still appear
            WriteCsv("SECRET-Tenant,desc,True,Standalone,2026-01-01,Success,0,0,0,0," +
                     "0,0,0,0,0,0,0,0,8,True,500,MbytePerSec,StandaloneGateways,ACME-Pool,False,Never," +
                     "2030-01-01,True,30");

            string html = new CCloudTenantPerformanceTable().Render(scrub: true);

            Assert.DoesNotContain("SECRET-Tenant", html);
            // MCT is a numeric field, not scrubbed
            Assert.Contains("8", html);
        }
    }
}
