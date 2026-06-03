// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Tenant Replica Resources"
    /// renderer. Mirrors CCloudFailoverPlansTableTests: reuses VbrTableScrubTestBase
    /// (isolated VbrDir + CGlobals state) so the renderer's CCsvParser reads our
    /// sample _CloudTenantReplicationResources.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: tenantname, hardwareplanname, datastorefriendlyname.
    /// No name/description pair — test (c) anonymizes tenant + plan + datastore and
    /// asserts a non-PII column (cpuquota) still renders.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudTenantReplicationResourcesTableTests : VbrTableScrubTestBase
    {
        public CCloudTenantReplicationResourcesTableTests() : base("VhcCloudTenantReplicationResourcesTests_") { }

        private const string Headers =
            "tenantname,hardwareplanname,usedcpu,usedmemorymb,datastorefriendlyname,datastorequotagb," +
            "datastoreusedspacegb,cpuquota,memoryquota";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudTenantReplicationResources.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudTenantReplicationResourcesTable().Render(scrub: false);
            Assert.Contains("No cloud tenant replication resources detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-Tenant,ACME-HWPlan,2000,4096,acme.corp Datastore,1024,512,Unlimited,Unlimited");

            string html = new CCloudTenantReplicationResourcesTable().Render(scrub: false);

            Assert.Contains("ACME-Tenant", html);
            Assert.Contains("acme.corp Datastore", html);
            Assert.Contains("Unlimited", html);
            Assert.DoesNotContain("No cloud tenant replication resources detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-Tenant,ACME-HWPlan,2000,4096,acme.corp Datastore,1024,512,Unlimited,Unlimited");

            string html = new CCloudTenantReplicationResourcesTable().Render(scrub: true);

            // PII columns (tenant, hardware plan, datastore) must not leak under scrub
            Assert.DoesNotContain("ACME-Tenant", html);
            Assert.DoesNotContain("ACME-HWPlan", html);
            Assert.DoesNotContain("acme.corp", html);
            // non-PII column still renders
            Assert.Contains("Unlimited", html);
        }
    }
}
