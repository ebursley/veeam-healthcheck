// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings
{
    [Trait("Category", "Scrubbing")]
    [Collection("GlobalState")]
    public class CCredentialsTableScrubTests : VbrTableScrubTestBase
    {
        // FileFinder matches "_Credentials.csv"; PrepareHeaderForMatch lowercases headers
        // so dynamic object property is "description" (lowercase).
        private const string CredentialsCsv =
            "\"Name\",\"UserName\",\"Description\",\"LastModified\"\r\n" +
            "\"CORP\\svc-backup\",\"svc-backup\",\"Service account for Veeam backup jobs\",\"2024-01-01\"";

        private const string CredentialsCsvEmptyDescription =
            "\"Name\",\"UserName\",\"Description\",\"LastModified\"\r\n" +
            "\"CORP\\svc-backup\",\"svc-backup\",\"\",\"2024-01-01\"";

        public CCredentialsTableScrubTests() : base("VhcCredScrubTests_") { }

        private void WriteCredentialsCsv(string content) =>
            File.WriteAllText(System.IO.Path.Combine(VbrDir, "_Credentials.csv"), content);

        [Fact]
        public void Render_ScrubTrue_DescriptionIsReplacedWithToken()
        {
            WriteCredentialsCsv(CredentialsCsv);
            string html = new CCredentialsTable().Render(scrub: true);

            Assert.DoesNotContain("Service account for Veeam backup jobs", html);
            Assert.Contains("Item_", html);
        }

        [Fact]
        public void Render_ScrubFalse_DescriptionPassesThroughUnchanged()
        {
            WriteCredentialsCsv(CredentialsCsv);
            string html = new CCredentialsTable().Render(scrub: false);

            Assert.Contains("Service account for Veeam backup jobs", html);
        }

        [Fact]
        public void Render_ScrubTrue_EmptyDescription_DoesNotThrow()
        {
            WriteCredentialsCsv(CredentialsCsvEmptyDescription);
            var exception = Record.Exception(() => new CCredentialsTable().Render(scrub: true));
            Assert.Null(exception);
        }
    }
}
