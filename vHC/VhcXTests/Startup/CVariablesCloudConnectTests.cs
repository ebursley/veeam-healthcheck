// Copyright (C) 2025 VeeamHub
// SPDX-License-Identifier: MIT

using System;
using System.IO;
using VeeamHealthCheck;
using VeeamHealthCheck.Shared;
using Xunit;

namespace VhcXTests.Startup
{
    /// <summary>
    /// Guards the Cloud Connect navigation/section consistency contract.
    ///
    /// Regression context: commit d3ccd0e added a "Cloud Connect" sidebar nav block
    /// (10 "#cloud*" links) that was always emitted, while the report body section
    /// (CHtmlBodyHelper.CloudConnectSection) only renders when Cloud Connect collection
    /// data exists. On any VBR server without Cloud Connect configured, that produced 10
    /// dead navigation links, which the CI "Validate HTML report content" step treats as
    /// a release-blocking defect (integration-test-vbr-12 / -13 failures).
    ///
    /// CVariables.HasCloudConnectData() is now the single source of truth gating BOTH the
    /// nav links and the section, so they can never diverge. These tests pin that contract.
    /// </summary>
    [Trait("Category", "Unit")]
    [Collection("GlobalState")]
    public class CVariablesCloudConnectTests : IDisposable
    {
        private readonly string _importDir;
        private readonly bool _origImport;
        private readonly string _origImportPath;
        private readonly string _origResolvedImportPath;

        public CVariablesCloudConnectTests()
        {
            _origImport = CGlobals.IMPORT;
            _origImportPath = CGlobals.IMPORT_PATH;
            _origResolvedImportPath = CVariables.ResolvedImportPath;

            _importDir = Path.Combine(Path.GetTempPath(), "VhcCloudConnectTests_" + Guid.NewGuid());
            Directory.CreateDirectory(_importDir);

            // Route CVariables.vbrDir at our temp dir via import mode.
            CGlobals.IMPORT = true;
            CGlobals.IMPORT_PATH = _importDir;
            CVariables.ResolvedImportPath = _importDir;
        }

        public void Dispose()
        {
            CGlobals.IMPORT = _origImport;
            CGlobals.IMPORT_PATH = _origImportPath;
            CVariables.ResolvedImportPath = _origResolvedImportPath;

            if (Directory.Exists(_importDir))
            {
                try { Directory.Delete(_importDir, recursive: true); } catch { /* best effort */ }
            }
        }

        [Fact]
        public void HasCloudConnectData_NoCloudConnectCsvs_ReturnsFalse()
        {
            // Arrange: a normal collection with no Cloud Connect output.
            File.WriteAllText(Path.Combine(_importDir, "host_Servers.csv"), "Name\nlocalhost\n");
            File.WriteAllText(Path.Combine(_importDir, "host_Jobs.csv"), "Name\nDailyBackup\n");

            // Act / Assert: no nav links should be emitted -> no dead links.
            Assert.False(CVariables.HasCloudConnectData());
        }

        [Fact]
        public void HasCloudConnectData_GatewaysCsvPresent_ReturnsTrue()
        {
            File.WriteAllText(Path.Combine(_importDir, "host_CloudGateways.csv"), "Name\ngw1\n");

            Assert.True(CVariables.HasCloudConnectData());
        }

        [Fact]
        public void HasCloudConnectData_TenantsCsvPresent_ReturnsTrue()
        {
            File.WriteAllText(Path.Combine(_importDir, "host_CloudTenants.csv"), "Name\ntenant1\n");

            Assert.True(CVariables.HasCloudConnectData());
        }

        [Fact]
        public void HasCloudConnectData_MissingDirectory_ReturnsFalse()
        {
            // Point at a directory that does not exist.
            string ghost = Path.Combine(Path.GetTempPath(), "VhcCloudConnectGhost_" + Guid.NewGuid());
            CGlobals.IMPORT_PATH = ghost;
            CVariables.ResolvedImportPath = ghost;

            Assert.False(CVariables.HasCloudConnectData());
        }
    }
}
