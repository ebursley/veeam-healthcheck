// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.Reflection;
using VeeamHealthCheck;
using VeeamHealthCheck.Scrubber;
using VeeamHealthCheck.Shared;
using Xunit;

namespace VhcXTests.Common.Scrubber
{
    /// <summary>
    /// Tests for CScrubHandler ensuring matchListPath reflects the current
    /// CGlobals.desiredPath at call time rather than the value captured at
    /// construction time.
    ///
    /// Issue #152: vHC_KeyFile.xml always wrote to C:\temp\vHC\Original\ even
    /// when /outdir= was supplied. Root cause was a readonly field that captured
    /// CVariables.unsafeDir once at construction. The fix converts the field to
    /// an expression-bodied property so it re-evaluates on every access.
    /// </summary>
    public class CXmlHandlerTests : IDisposable
    {
        private readonly string _originalDesiredPath;

        public CXmlHandlerTests()
        {
            // Snapshot global state before each test
            _originalDesiredPath = CGlobals.desiredPath;
        }

        public void Dispose()
        {
            // Restore global state after each test so other tests are not affected
            CGlobals.desiredPath = _originalDesiredPath;
            CGlobals.mainlog = new VeeamHealthCheck.Shared.Logging.CLogger("HealthCheck");
        }

        /// <summary>
        /// matchListPath must re-evaluate every time it is read so that a path
        /// change via CGlobals.desiredPath is honoured without reconstructing
        /// the CScrubHandler.
        ///
        /// We read the private property via reflection to avoid touching the
        /// file system (the property only reads; writes happen in AddItemToList).
        /// </summary>
        [Fact]
        public void MatchListPath_AfterDesiredPathChange_ReflectsNewPath()
        {
            // Arrange
            string customDir = @"D:\custom\output";
            var handler = new CScrubHandler();

            // Grab the private property via reflection
            PropertyInfo prop = typeof(CScrubHandler).GetProperty(
                "matchListPath",
                BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(prop); // guard: property must exist (not a field)

            // Baseline: path before desiredPath change should use CVariables.unsafeDir
            string pathBefore = (string)prop.GetValue(handler);

            // Act: change desiredPath after construction
            CGlobals.desiredPath = customDir;
            string pathAfter = (string)prop.GetValue(handler);

            // Assert: the new path must contain the custom directory
            Assert.Contains(customDir, pathAfter,
                StringComparison.OrdinalIgnoreCase);

            // Also assert they are different — if this fails the field is still readonly
            Assert.NotEqual(pathBefore, pathAfter);
        }

        /// <summary>
        /// The file name component of matchListPath must always be vHC_KeyFile.xml.
        /// </summary>
        [Fact]
        public void MatchListPath_Always_EndsWithKeyFileName()
        {
            // Arrange
            CGlobals.desiredPath = @"D:\reports\vhc";
            var handler = new CScrubHandler();

            PropertyInfo prop = typeof(CScrubHandler).GetProperty(
                "matchListPath",
                BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(prop);

            // Act
            string path = (string)prop.GetValue(handler);

            // Assert
            Assert.EndsWith("vHC_KeyFile.xml", path,
                StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Two reads of matchListPath on the same instance must return different
        /// values when desiredPath is mutated between reads. This validates that
        /// no caching occurs.
        /// </summary>
        [Fact]
        public void MatchListPath_TwoSuccessiveReads_ReflectMostRecentDesiredPath()
        {
            // Arrange
            var handler = new CScrubHandler();
            PropertyInfo prop = typeof(CScrubHandler).GetProperty(
                "matchListPath",
                BindingFlags.NonPublic | BindingFlags.Instance);
            Assert.NotNull(prop);

            // Act
            CGlobals.desiredPath = @"E:\first\path";
            string first = (string)prop.GetValue(handler);

            CGlobals.desiredPath = @"F:\second\path";
            string second = (string)prop.GetValue(handler);

            // Assert
            Assert.Contains(@"E:\first\path", first, StringComparison.OrdinalIgnoreCase);
            Assert.Contains(@"F:\second\path", second, StringComparison.OrdinalIgnoreCase);
            Assert.NotEqual(first, second);
        }
    }
}
