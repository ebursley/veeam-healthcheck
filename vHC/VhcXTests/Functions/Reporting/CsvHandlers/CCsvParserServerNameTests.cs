// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.IO;
using VeeamHealthCheck.Functions.Reporting.CsvHandlers;
using Xunit;

namespace VhcXTests.Functions.Reporting.CsvHandlers
{
    /// <summary>
    /// Regression coverage for issue #158: the report file must be named after the VBR server,
    /// never the configuration-database host. The authoritative server name is the prefix of the
    /// collected "{server}_vbrinfo.csv" file (and the folder it lives in), which collection derived
    /// from the real VBR server name. The previous implementation read PgHost/MsHost from inside
    /// vbrinfo.csv, which is the database host and is wrong whenever DB and VBR are separate machines.
    /// </summary>
    [Trait("Category", "CsvParsing")]
    public class CCsvParserServerNameTests : IDisposable
    {
        private readonly string _root;

        public CCsvParserServerNameTests()
        {
            _root = Path.Combine(Path.GetTempPath(), "VhcServerNameTests_" + Guid.NewGuid());
            Directory.CreateDirectory(_root);
        }

        public void Dispose()
        {
            try { Directory.Delete(_root, recursive: true); } catch { /* best-effort */ }
        }

        [Theory]
        [InlineData("vbr-v13-rtm.home.lab_vbrinfo.csv", "vbr-v13-rtm.home.lab")]
        [InlineData("backup-prod-01_vbrinfo.csv", "backup-prod-01")]
        [InlineData(@"C:\temp\vHC\Original\VBR\vbr01.contoso.com\20260101_000000\vbr01.contoso.com_vbrinfo.csv", "vbr01.contoso.com")]
        public void ExtractServerName_ReturnsFqdnPrefix(string fileName, string expected)
        {
            Assert.Equal(expected, CCsvParser.ExtractServerNameFromCsvFileName(fileName));
        }

        [Theory]
        [InlineData(null)]
        [InlineData("")]
        [InlineData("vbrinfo.csv")]                 // no server prefix
        [InlineData("server_Servers.csv")]          // different token
        [InlineData("server_malware_events.csv")]   // token with underscores must not be mis-parsed
        public void ExtractServerName_ReturnsNull_ForNonMatching(string fileName)
        {
            Assert.Null(CCsvParser.ExtractServerNameFromCsvFileName(fileName));
        }

        [Fact]
        public void ResolveServerNameFromCsvDir_ReturnsNull_WhenDirMissing()
        {
            Assert.Null(CCsvParser.ResolveServerNameFromCsvDir(Path.Combine(_root, "does-not-exist")));
            Assert.Null(CCsvParser.ResolveServerNameFromCsvDir(null));
        }

        [Fact]
        public void ResolveServerNameFromCsvDir_ReturnsNull_WhenNoVbrInfoCsv()
        {
            File.WriteAllText(Path.Combine(_root, "vbr01_Servers.csv"), "Name\nvbr01\n");
            Assert.Null(CCsvParser.ResolveServerNameFromCsvDir(_root));
        }

        /// <summary>
        /// Issue #158 core scenario: collection folder + filename are named after the VBR server
        /// ("backup-prod-01"), while vbrinfo.csv's MsHost points at a SEPARATE database host
        /// ("sql-db-99"). The resolver must return the VBR server name, not the database host.
        /// </summary>
        [Fact]
        public void ResolveServerNameFromCsvDir_UsesVbrName_NotDatabaseHost()
        {
            const string vbrServer = "backup-prod-01.contoso.com";
            const string dbHost = "sql-db-99.contoso.com";

            string collectionDir = Path.Combine(_root, "Original", "VBR", vbrServer, "20260101_000000");
            Directory.CreateDirectory(collectionDir);

            // vbrinfo.csv whose database columns point at a DIFFERENT host than the VBR server.
            string header = "\"Version\",\"Fixes\",\"SqlServer\",\"Instance\",\"PgHost\",\"PgDb\",\"MsHost\",\"MsDb\",\"DbType\",\"MFA\"";
            string row = $"\"13.0.1.2067\",,\"{dbHost}\",,,,\"{dbHost}\",\"VeeamBackup\",\"MsSql\",\"False\"";
            File.WriteAllText(Path.Combine(collectionDir, $"{vbrServer}_vbrinfo.csv"), header + "\n" + row + "\n");

            string resolved = CCsvParser.ResolveServerNameFromCsvDir(collectionDir);

            Assert.Equal(vbrServer, resolved);
            Assert.NotEqual(dbHost, resolved);
        }

        /// <summary>
        /// Anti-regression for ISC-9: the colocated/local case (folder named after the VBR server,
        /// no separate DB host) still yields the same FQDN it always did.
        /// </summary>
        [Fact]
        public void ResolveServerNameFromCsvDir_ColocatedCase_StillYieldsFqdn()
        {
            const string vbrServer = "vbr-v13-rtm.home.lab";
            string collectionDir = Path.Combine(_root, "Original", "VBR", vbrServer, "20260529_103007");
            Directory.CreateDirectory(collectionDir);
            File.WriteAllText(
                Path.Combine(collectionDir, $"{vbrServer}_vbrinfo.csv"),
                "\"Version\",\"Fixes\",\"SqlServer\",\"Instance\",\"PgHost\",\"PgDb\",\"MsHost\",\"MsDb\",\"DbType\",\"MFA\"\n\"13.0.1.2067\",,,,,,,,,\"False\"\n");

            Assert.Equal(vbrServer, CCsvParser.ResolveServerNameFromCsvDir(collectionDir));
        }
    }
}
