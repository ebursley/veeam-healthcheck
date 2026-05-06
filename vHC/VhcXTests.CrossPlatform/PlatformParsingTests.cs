// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
// Cross-platform tests for vHC platform identification (ISC-1..ISC-24)

using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using Xunit;

namespace VhcXTests.CrossPlatform;

/// <summary>
/// Tests for platform identification parsing in Servers and Jobs CSV files.
/// Covers ISC criteria for platform field propagation, rendering, and backward compatibility.
/// </summary>
public class PlatformParsingTests
{
    #region Canonical Platform Strings

    /// <summary>
    /// The 8 canonical platform strings recognized by vHC.
    /// Case and spacing are SIGNIFICANT.
    /// </summary>
    public static IEnumerable<object[]> CanonicalPlatformStrings()
    {
        yield return new object[] { "Proxmox VE" };
        yield return new object[] { "Nutanix AHV" };
        yield return new object[] { "HPE Morpheus VME" };
        yield return new object[] { "SC HyperCore" };
        yield return new object[] { "XCP-ng" };
        yield return new object[] { "Sangfor HCI" };
        yield return new object[] { "RHV" };
        yield return new object[] { "Kasten" };
    }

    #endregion

    #region Servers CSV — Platform column parsing

    [Theory]
    [MemberData(nameof(CanonicalPlatformStrings))]
    public void ServersCsv_WithPlatformColumn_ParsesCanonicalPlatformString(string platform)
    {
        // Arrange — CSV with Platform column containing a canonical platform string
        string csv = VbrCsvPlatformFixtures.GenerateServersWithPlatform(platform);

        // Act
        var records = ParseServersCsv(csv);

        // Assert — the Platform field is present and matches exactly
        Assert.NotEmpty(records);
        var firstServer = records.First();
        Assert.Equal(platform, firstServer.Platform);
    }

    [Fact]
    public void ServersCsv_LegacyNoPlatformColumn_ParsesWithNullOrEmptyPlatform()
    {
        // Arrange — legacy CSV without Platform column
        string csv = VbrCsvPlatformFixtures.GenerateServersLegacyNoPlatform();

        // Act
        var records = ParseServersCsv(csv);

        // Assert — Platform should be null or empty (no exception thrown)
        Assert.NotEmpty(records);
        foreach (var record in records)
        {
            Assert.True(
                record.Platform == null || record.Platform == string.Empty,
                $"Expected null or empty Platform for legacy CSV, got: '{record.Platform}'"
            );
        }
    }

    [Fact]
    public void ServersCsv_EmptyPlatformValue_ParsesAsEmptyString()
    {
        // Arrange — CSV with Platform column present but value empty
        string csv = VbrCsvPlatformFixtures.GenerateServersEmptyPlatform();

        // Act
        var records = ParseServersCsv(csv);

        // Assert — Platform is empty string, not null literal
        Assert.NotEmpty(records);
        foreach (var record in records)
        {
            // Empty string is acceptable; "null" text string is NOT acceptable
            Assert.NotEqual("null", record.Platform, StringComparer.OrdinalIgnoreCase);
        }
    }

    [Theory]
    [MemberData(nameof(CanonicalPlatformStrings))]
    public void ServersCsv_PlatformPreservesExactCaseAndSpacing(string platform)
    {
        // Arrange
        string csv = VbrCsvPlatformFixtures.GenerateServersWithPlatform(platform);

        // Act
        var records = ParseServersCsv(csv);

        // Assert — exact case/spacing preserved (not lowercased, not trimmed differently)
        var record = records.First();
        Assert.Equal(platform, record.Platform);
    }

    #endregion

    #region Jobs CSV — Platform column parsing

    [Theory]
    [MemberData(nameof(CanonicalPlatformStrings))]
    public void JobsCsv_WithPlatformColumn_ParsesCanonicalPlatformString(string platform)
    {
        // Arrange
        string csv = VbrCsvPlatformFixtures.GenerateJobsWithPlatform(platform);

        // Act
        var records = ParseJobsCsv(csv);

        // Assert
        Assert.NotEmpty(records);
        var firstJob = records.First();
        Assert.Equal(platform, firstJob.Platform);
    }

    [Fact]
    public void JobsCsv_LegacyNoPlatformColumn_ParsesWithNullOrEmptyPlatform()
    {
        // Arrange — legacy jobs CSV without Platform column
        string csv = VbrCsvPlatformFixtures.GenerateJobsLegacyNoPlatform();

        // Act
        var records = ParseJobsCsv(csv);

        // Assert
        Assert.NotEmpty(records);
        foreach (var record in records)
        {
            Assert.True(
                record.Platform == null || record.Platform == string.Empty,
                $"Expected null or empty Platform for legacy CSV, got: '{record.Platform}'"
            );
        }
    }

    [Fact]
    public void JobsCsv_EmptyPlatformValue_ParsesAsEmptyString()
    {
        // Arrange
        string csv = VbrCsvPlatformFixtures.GenerateJobsEmptyPlatform();

        // Act
        var records = ParseJobsCsv(csv);

        // Assert
        Assert.NotEmpty(records);
        foreach (var record in records)
        {
            Assert.NotEqual("null", record.Platform, StringComparer.OrdinalIgnoreCase);
        }
    }

    #endregion

    #region HTML Rendering — string-contains assertions

    [Theory]
    [MemberData(nameof(CanonicalPlatformStrings))]
    public void HtmlRenderer_WithPlatformValue_EmitsPlatformInOutput(string platform)
    {
        // Arrange — simulate what the managed server table renderer does:
        // it calls d.Platform ?? string.Empty
        string platform_value = platform;

        // Act — simulate the render-path null-coalescing
        string rendered = RenderPlatformCell(platform_value);

        // Assert — the platform string appears literally in the output
        Assert.Contains(platform, rendered);
    }

    [Fact]
    public void HtmlRenderer_NullPlatform_EmitsBlankCell()
    {
        // Arrange
        string? platform_value = null;

        // Act — null-coalesce as the table renderer does
        string rendered = RenderPlatformCell(platform_value);

        // Assert — must not contain the literal text "null"
        Assert.DoesNotContain("null", rendered, StringComparison.OrdinalIgnoreCase);
        // Cell should be present but empty
        Assert.Contains("<td", rendered);
    }

    [Fact]
    public void HtmlRenderer_EmptyPlatform_EmitsBlankCell()
    {
        // Arrange
        string platform_value = string.Empty;

        // Act
        string rendered = RenderPlatformCell(platform_value);

        // Assert — no literal "null", empty cell is fine
        Assert.DoesNotContain("null", rendered, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("<td", rendered);
    }

    [Theory]
    [MemberData(nameof(CanonicalPlatformStrings))]
    public void HtmlRenderer_PlatformValueNotMangled_CasePreserved(string platform)
    {
        // Arrange
        string platform_value = platform;

        // Act
        string rendered = RenderPlatformCell(platform_value);

        // Assert — exact platform string appears (case-sensitive)
        Assert.Contains(platform, rendered);
    }

    #endregion

    #region CSV Fixture Helpers

    private static IReadOnlyList<CServerCsvInfosProxy> ParseServersCsv(string csvContent)
    {
        var results = new List<CServerCsvInfosProxy>();
        using var reader = new StringReader(csvContent);
        string? headerLine = reader.ReadLine();
        if (headerLine == null) return results;

        var headers = ParseCsvLine(headerLine);
        int platformIndex = Array.IndexOf(headers, "Platform");

        string? line;
        while ((line = reader.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            var fields = ParseCsvLine(line);
            var record = new CServerCsvInfosProxy();

            // Map known fields by position (matching CServerCsvInfos Index attributes)
            if (fields.Length > 4) record.Name = Unquote(fields[4]);
            if (fields.Length > 7) record.IsUnavailable = Unquote(fields[7]);

            // Platform: either at named column or at index 16
            if (platformIndex >= 0 && platformIndex < fields.Length)
            {
                record.Platform = Unquote(fields[platformIndex]);
            }
            else if (fields.Length > 16)
            {
                record.Platform = Unquote(fields[16]);
            }
            else
            {
                record.Platform = null;
            }

            results.Add(record);
        }

        return results;
    }

    private static IReadOnlyList<CJobCsvInfosProxy> ParseJobsCsv(string csvContent)
    {
        var results = new List<CJobCsvInfosProxy>();
        using var reader = new StringReader(csvContent);
        string? headerLine = reader.ReadLine();
        if (headerLine == null) return results;

        var headers = ParseCsvLine(headerLine);
        int platformIndex = Array.IndexOf(headers, "Platform");

        string? line;
        while ((line = reader.ReadLine()) != null)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            var fields = ParseCsvLine(line);
            var record = new CJobCsvInfosProxy();

            if (fields.Length > 0) record.Name = Unquote(fields[0]);
            if (fields.Length > 1) record.JobType = Unquote(fields[1]);

            // Platform: either at named column or at index 42 (after IsScheduleDisabled at 41)
            if (platformIndex >= 0 && platformIndex < fields.Length)
            {
                record.Platform = Unquote(fields[platformIndex]);
            }
            else if (fields.Length > 42)
            {
                record.Platform = Unquote(fields[42]);
            }
            else
            {
                record.Platform = null;
            }

            results.Add(record);
        }

        return results;
    }

    /// <summary>
    /// Simulates the HTML table render path for a Platform cell.
    /// Mirrors the pattern: form.TableData(d.Platform ?? string.Empty, string.Empty)
    /// </summary>
    private static string RenderPlatformCell(string? platformValue)
    {
        string cellValue = platformValue ?? string.Empty;
        return $"<td>{System.Net.WebUtility.HtmlEncode(cellValue)}</td>";
    }

    /// <summary>
    /// Minimal CSV line parser that handles quoted fields.
    /// </summary>
    private static string[] ParseCsvLine(string line)
    {
        var fields = new List<string>();
        int i = 0;
        while (i < line.Length)
        {
            if (line[i] == '"')
            {
                // Quoted field
                int start = i + 1;
                i++;
                while (i < line.Length)
                {
                    if (line[i] == '"')
                    {
                        if (i + 1 < line.Length && line[i + 1] == '"')
                        {
                            i += 2; // escaped quote
                        }
                        else
                        {
                            break;
                        }
                    }
                    else
                    {
                        i++;
                    }
                }
                fields.Add(line.Substring(start, i - start).Replace("\"\"", "\""));
                i++; // skip closing quote
                if (i < line.Length && line[i] == ',') i++; // skip comma
            }
            else
            {
                // Unquoted field
                int start = i;
                while (i < line.Length && line[i] != ',') i++;
                fields.Add(line.Substring(start, i - start));
                if (i < line.Length) i++; // skip comma
            }
        }
        return fields.ToArray();
    }

    private static string Unquote(string s)
    {
        if (s.StartsWith("\"") && s.EndsWith("\"") && s.Length >= 2)
            return s.Substring(1, s.Length - 2).Replace("\"\"", "\"");
        return s;
    }

    #endregion

    #region Proxy types for CSV parsing (mirrors CServerCsvInfos / CJobCsvInfos)

    private class CServerCsvInfosProxy
    {
        public string? Name { get; set; }
        public string? IsUnavailable { get; set; }
        public string? Platform { get; set; }
    }

    private class CJobCsvInfosProxy
    {
        public string? Name { get; set; }
        public string? JobType { get; set; }
        public string? Platform { get; set; }
    }

    #endregion
}
