// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Tenant Backup Storage"
    /// renderer. Mirrors CCloudFailoverPlansTableTests: reuses VbrTableScrubTestBase
    /// (isolated VbrDir + CGlobals state) so the renderer's CCsvParser reads our
    /// sample _CloudTenantBackupResources.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: tenantname, repositoryfriendlyname, repositoryname,
    /// repositoryquotapath, wanacceleratorname. The renderer has no name/description
    /// pair — test (c) anonymizes the tenant + repository identifiers and asserts a
    /// non-PII column (repositorytype) still renders.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudTenantBackupResourcesTableTests : VbrTableScrubTestBase
    {
        public CCloudTenantBackupResourcesTableTests() : base("VhcCloudTenantBackupResourcesTests_") { }

        private const string Headers =
            "tenantname,repositoryfriendlyname,repositoryname,repositorytype,repositoryquotamb,usedspacemb," +
            "freespacemb,usedspacepercentage,repositoryquotapath,performancetierusedmb,capacitytierusedmb," +
            "archivetierusedmb,wanaccelerationenabled,wanacceleratorname";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudTenantBackupResources.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudTenantBackupResourcesTable().Render(scrub: false);
            Assert.Contains("No cloud tenant backup resources detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-Tenant,acme.corp Repo,ACME-Repo01,WinLocal,1048576,524288,524288,50," +
                     "C:\\Backups\\acme,262144,131072,0,True,acme-wan01");

            string html = new CCloudTenantBackupResourcesTable().Render(scrub: false);

            Assert.Contains("ACME-Tenant", html);
            Assert.Contains("acme.corp Repo", html);
            Assert.Contains("WinLocal", html);
            Assert.DoesNotContain("No cloud tenant backup resources detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-Tenant,acme.corp Repo,ACME-Repo01,WinLocal,1048576,524288,524288,50," +
                     "C:\\Backups\\acme,262144,131072,0,True,acme-wan01");

            string html = new CCloudTenantBackupResourcesTable().Render(scrub: true);

            // PII columns (tenant + repository identifiers) must not leak under scrub
            Assert.DoesNotContain("ACME-Tenant", html);
            Assert.DoesNotContain("acme.corp", html);
            Assert.DoesNotContain("ACME-Repo01", html);
            // non-PII column still renders
            Assert.Contains("WinLocal", html);
        }
    }
}
