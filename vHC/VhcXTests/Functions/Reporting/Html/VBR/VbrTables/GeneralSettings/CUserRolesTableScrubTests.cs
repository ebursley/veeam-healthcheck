// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System.IO;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings
{
    [Trait("Category", "Scrubbing")]
    public class CUserRolesTableScrubTests : VbrTableScrubTestBase
    {
        // FileFinder matches "_UserRoles.csv"; row dict keys match CSV header casing exactly.
        private const string UserRolesCsv =
            "\"Name\",\"Role\",\"Description\"\r\n" +
            "\"CORP\\jdoe\",\"Veeam Backup Administrator\",\"John Doe - IT Admin - john.doe@corp.example.com\"";

        private const string UserRolesCsvEmptyDescription =
            "\"Name\",\"Role\",\"Description\"\r\n" +
            "\"CORP\\jdoe\",\"Veeam Backup Administrator\",\"\"";

        public CUserRolesTableScrubTests() : base("VhcUserRolesScrubTests_") { }

        private void WriteUserRolesCsv(string content) =>
            File.WriteAllText(System.IO.Path.Combine(VbrDir, "_UserRoles.csv"), content);

        [Fact]
        public void Render_ScrubTrue_DescriptionIsReplacedWithToken()
        {
            WriteUserRolesCsv(UserRolesCsv);
            string html = new CUserRolesTable().Render(scrub: true);

            Assert.DoesNotContain("John Doe", html);
            Assert.DoesNotContain("john.doe@corp.example.com", html);
            Assert.Contains("Item_", html);
        }

        [Fact]
        public void Render_ScrubFalse_DescriptionPassesThroughUnchanged()
        {
            WriteUserRolesCsv(UserRolesCsv);
            string html = new CUserRolesTable().Render(scrub: false);

            Assert.Contains("John Doe - IT Admin - john.doe@corp.example.com", html);
        }

        [Fact]
        public void Render_ScrubTrue_EmptyDescription_DoesNotThrow()
        {
            WriteUserRolesCsv(UserRolesCsvEmptyDescription);
            var exception = Record.Exception(() => new CUserRolesTable().Render(scrub: true));
            Assert.Null(exception);
        }
    }
}
