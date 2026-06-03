// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect;
using VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    /// <summary>
    /// Characterization coverage for the Cloud Connect "Cloud Replicas" renderer.
    /// Mirrors CCloudFailoverPlansTableTests: reuses VbrTableScrubTestBase (isolated
    /// VbrDir + CGlobals state) so the renderer's CCsvParser reads our sample
    /// _CloudReplicas.csv instead of live VBR output.
    ///
    /// NOTE: the renderer swallows exceptions (logs + continues), so a malformed
    /// CSV or wrong column silently produces empty/partial HTML rather than throwing.
    /// Scrubbed PII fields: name, jobname, originallocation, replicalocation.
    /// No description column — test (c) anonymizes name + job/locations and asserts
    /// a non-PII column (status) still renders.
    /// </summary>
    [Collection("GlobalState")]
    public class CCloudReplicasTableTests : VbrTableScrubTestBase
    {
        public CCloudReplicasTableTests() : base("VhcCloudReplicasTests_") { }

        private const string Headers =
            "name,jobname,status,restorepointcount,originallocation,replicalocation,platform";

        private void WriteCsv(string rows) =>
            File.WriteAllText(Path.Combine(VbrDir, "_CloudReplicas.csv"), Headers + "\n" + rows);

        [Fact]
        public void Render_NoData_ShowsEmptyStateMessage()
        {
            string html = new CCloudReplicasTable().Render(scrub: false);
            Assert.Contains("No cloud replicas detected", html);
        }

        [Fact]
        public void Render_ScrubFalse_RendersRawValues()
        {
            WriteCsv("ACME-VM01_replica,ACME Replication Job,Ready,7,acme-prod-site,acme-dr-site,VMware");

            string html = new CCloudReplicasTable().Render(scrub: false);

            Assert.Contains("ACME-VM01_replica", html);
            Assert.Contains("ACME Replication Job", html);
            Assert.Contains("Ready", html);
            Assert.DoesNotContain("No cloud replicas detected", html);
        }

        [Fact]
        public void Render_ScrubTrue_AnonymizesNameAndDescription()
        {
            WriteCsv("ACME-VM01_replica,ACME Replication Job,Ready,7,acme-prod-site,acme-dr-site,VMware");

            string html = new CCloudReplicasTable().Render(scrub: true);

            // PII columns (name, job name, locations) must not leak under scrub
            Assert.DoesNotContain("ACME-VM01_replica", html);
            Assert.DoesNotContain("ACME Replication Job", html);
            Assert.DoesNotContain("acme-prod-site", html);
            // non-PII column still renders
            Assert.Contains("Ready", html);
        }
    }
}
