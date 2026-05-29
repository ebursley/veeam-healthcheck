// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.IO;
using VeeamHealthCheck;
using VeeamHealthCheck.Shared;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables.GeneralSettings
{
    public abstract class VbrTableScrubTestBase : IDisposable
    {
        protected readonly string TestBaseDir;
        protected readonly string VbrDir;

        private readonly bool _originalImport;
        private readonly string _originalImportPath;
        private readonly string _originalResolvedPath;
        private readonly string _originalDesiredPath;

        protected VbrTableScrubTestBase(string tempDirPrefix)
        {
            _originalImport = CGlobals.IMPORT;
            _originalImportPath = CGlobals.IMPORT_PATH;
            _originalResolvedPath = CVariables.ResolvedImportPath;
            _originalDesiredPath = CGlobals.desiredPath;

            TestBaseDir = Path.GetFullPath(
                Path.Combine(Path.GetTempPath(), tempDirPrefix + Guid.NewGuid()));
            VbrDir = Path.Combine(TestBaseDir, "VBR");
            Directory.CreateDirectory(VbrDir);
            Directory.CreateDirectory(Path.Combine(TestBaseDir, "Original")); // scrubber writes vHC_KeyFile.xml here

            CGlobals.desiredPath = TestBaseDir;
            CGlobals.IMPORT = true;
            CGlobals.IMPORT_PATH = VbrDir;
            CVariables.ResolvedImportPath = VbrDir;
        }

        public void Dispose()
        {
            CGlobals.IMPORT = _originalImport;
            CGlobals.IMPORT_PATH = _originalImportPath;
            CVariables.ResolvedImportPath = _originalResolvedPath;
            CGlobals.desiredPath = _originalDesiredPath;

            try { Directory.Delete(TestBaseDir, recursive: true); } catch { /* best-effort */ }
        }
    }
}
