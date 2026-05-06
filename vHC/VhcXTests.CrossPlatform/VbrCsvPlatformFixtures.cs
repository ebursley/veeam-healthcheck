// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
// CSV fixture generators for platform identification tests.

namespace VhcXTests.CrossPlatform;

/// <summary>
/// Generates sample CSV content for platform identification tests.
/// These fixtures are self-contained and require no file I/O.
/// </summary>
internal static class VbrCsvPlatformFixtures
{
    // Full Servers CSV header matching Get-VhcServer.ps1 Select-Object output
    private const string ServerHeader =
        "\"Info\",\"ParentId\",\"Id\",\"Uid\",\"Name\",\"Reference\",\"Description\"," +
        "\"IsUnavailable\",\"Type\",\"ApiVersion\",\"PhysHostId\",\"ProxyServicesCreds\"," +
        "\"Cores\",\"CPUCount\",\"RAM\",\"OSInfo\",\"Platform\"";

    // Legacy header without Platform column (pre-VBR 12.1)
    private const string ServerHeaderLegacy =
        "\"Info\",\"ParentId\",\"Id\",\"Uid\",\"Name\",\"Reference\",\"Description\"," +
        "\"IsUnavailable\",\"Type\",\"ApiVersion\",\"PhysHostId\",\"ProxyServicesCreds\"," +
        "\"Cores\",\"CPUCount\",\"RAM\",\"OSInfo\"";

    // Full Jobs CSV header matching Get-VhcJob.ps1 Select-Object output
    // Indices 0-41 are the standard fields; Platform is appended at index 42.
    private const string JobHeader =
        "\"Name\",\"JobType\",\"SheduleEnabledTime\",\"ScheduleOptions\",\"RestorePoints\"," +
        "\"RepoName\",\"Algorithm\",\"FullBackupScheduleKind\",\"FullBackupDays\"," +
        "\"TransformFullToSyntethic\",\"TransformIncrementsToSyntethic\",\"TransformToSyntethicDays\"," +
        "\"PwdKeyId\",\"OriginalSize\",\"RetentionType\",\"RetentionCount\",\"RetainDaysToKeep\"," +
        "\"DeletedVmRetentionDays\",\"DeletedVmRetention\",\"CompressionLevel\",\"Deduplication\"," +
        "\"BlockSize\",\"IntegrityChecks\",\"SpecificStorageEncryption\",\"StgEncryptionEnabled\"," +
        "\"KeepFirstFullBackup\",\"EnableFullBackup\",\"BackupIsAttached\",\"GfsWeeklyIsEnabled\"," +
        "\"GfsWeeklyCount\",\"GfsMonthlyEnabled\",\"GfsMonthlyCount\",\"GfsYearlyEnabled\"," +
        "\"GfsYearlyCount\",\"IndexingType\",\"OnDiskGB\",\"AAIPEnabled\",\"VSSEnabled\"," +
        "\"VSSIgnoreErrors\",\"GuestFSIndexingEnabled\",\"IsJobEnabled\",\"IsScheduleDisabled\"," +
        "\"Platform\"";

    // Legacy jobs header without Platform column
    private const string JobHeaderLegacy =
        "\"Name\",\"JobType\",\"SheduleEnabledTime\",\"ScheduleOptions\",\"RestorePoints\"," +
        "\"RepoName\",\"Algorithm\",\"FullBackupScheduleKind\",\"FullBackupDays\"," +
        "\"TransformFullToSyntethic\",\"TransformIncrementsToSyntethic\",\"TransformToSyntethicDays\"," +
        "\"PwdKeyId\",\"OriginalSize\",\"RetentionType\",\"RetentionCount\",\"RetainDaysToKeep\"," +
        "\"DeletedVmRetentionDays\",\"DeletedVmRetention\",\"CompressionLevel\",\"Deduplication\"," +
        "\"BlockSize\",\"IntegrityChecks\",\"SpecificStorageEncryption\",\"StgEncryptionEnabled\"," +
        "\"KeepFirstFullBackup\",\"EnableFullBackup\",\"BackupIsAttached\",\"GfsWeeklyIsEnabled\"," +
        "\"GfsWeeklyCount\",\"GfsMonthlyEnabled\",\"GfsMonthlyCount\",\"GfsYearlyEnabled\"," +
        "\"GfsYearlyCount\",\"IndexingType\",\"OnDiskGB\",\"AAIPEnabled\",\"VSSEnabled\"," +
        "\"VSSIgnoreErrors\",\"GuestFSIndexingEnabled\",\"IsJobEnabled\",\"IsScheduleDisabled\"";

    #region Servers CSV

    /// <summary>
    /// Generate a _Servers.csv with a Platform column set to the given platform string.
    /// </summary>
    public static string GenerateServersWithPlatform(string platform = "Proxmox VE")
    {
        return ServerHeader + "\n" +
               $"\"Veeam.Backup.Model.CWinViHost\"," +
               $"\"00000000-0000-0000-0000-000000000000\"," +
               $"\"aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb\"," +
               $"\"aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb\"," +
               $"\"proxmox-node-01\"," +
               $"\"\"," +
               $"\"\"," +
               $"\"False\"," +
               $"\"LinuxServer\"," +
               $"\"12.1.0.2131\"," +
               $"\"aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb\"," +
               $"\"\"," +
               $"\"32\"," +
               $"\"2\"," +
               $"\"137438953472\"," +
               $"\"Ubuntu 22.04.3 LTS\"," +
               $"\"{EscapeCsvField(platform)}\"";
    }

    /// <summary>
    /// Generate a _Servers.csv WITHOUT a Platform column (legacy VBR &lt; 12.1).
    /// </summary>
    public static string GenerateServersLegacyNoPlatform()
    {
        return ServerHeaderLegacy + "\n" +
               "\"Veeam.Backup.Model.CWinViHost\"," +
               "\"00000000-0000-0000-0000-000000000000\"," +
               "\"bbbbbbbb-1111-2222-3333-cccccccccccc\"," +
               "\"bbbbbbbb-1111-2222-3333-cccccccccccc\"," +
               "\"legacy-server-01\"," +
               "\"\"," +
               "\"\"," +
               "\"False\"," +
               "\"WinServer\"," +
               "\"11.0.1.1261\"," +
               "\"bbbbbbbb-1111-2222-3333-cccccccccccc\"," +
               "\"\"," +
               "\"16\"," +
               "\"1\"," +
               "\"68719476736\"," +
               "\"Microsoft Windows Server 2019\"";
    }

    /// <summary>
    /// Generate a _Servers.csv with a Platform column present but value is empty.
    /// </summary>
    public static string GenerateServersEmptyPlatform()
    {
        return ServerHeader + "\n" +
               "\"Veeam.Backup.Model.CWinViHost\"," +
               "\"00000000-0000-0000-0000-000000000000\"," +
               "\"cccccccc-1111-2222-3333-dddddddddddd\"," +
               "\"cccccccc-1111-2222-3333-dddddddddddd\"," +
               "\"native-server-01\"," +
               "\"\"," +
               "\"\"," +
               "\"False\"," +
               "\"WinServer\"," +
               "\"12.1.0.2131\"," +
               "\"cccccccc-1111-2222-3333-dddddddddddd\"," +
               "\"\"," +
               "\"8\"," +
               "\"1\"," +
               "\"34359738368\"," +
               "\"Microsoft Windows Server 2022\"," +
               "\"\"";
    }

    #endregion

    #region Jobs CSV

    /// <summary>
    /// Generate a _Jobs.csv with a Platform column set to the given platform string.
    /// Uses VmbApiPolicyTempJob job type (the plugin job type for external infrastructure).
    /// </summary>
    public static string GenerateJobsWithPlatform(string platform = "Proxmox VE")
    {
        return JobHeader + "\n" +
               $"\"Proxmox Backup Job\"," +
               $"\"VmbApiPolicyTempJob\"," +
               $"\"01/01/2026 02:00:00 a.m.\"," +
               $"\"Start time: [01/01/2026 2:00:00 a.m.]\"," +
               $"\"14\"," +
               $"\"Default Backup Repository\"," +
               $"\"Increment\"," +
               $"\"Daily\"," +
               $"\"Sunday\"," +
               $"\"False\"," +
               $"\"False\"," +
               $"\"Sunday\"," +
               $"\"00000000-0000-0000-0000-000000000000\"," +
               $"\"0\"," +
               $"\"Days\"," +
               $"\"14\"," +
               $"\"14\"," +
               $"\"14\"," +
               $"\"False\"," +
               $"\"5\"," +
               $"\"True\"," +
               $"\"KbBlockSize1024\"," +
               $"\"True\"," +
               $"\"False\"," +
               $"\"False\"," +
               $"\"False\"," +
               $"\"False\"," +
               $"\"False\"," +
               $"\"False\"," +
               $"\"4\"," +
               $"\"False\"," +
               $"\"1\"," +
               $"\"False\"," +
               $"\"1\"," +
               $"\"None\"," +
               $"\"50.5\"," +
               $"\"\"," +
               $"\"\"," +
               $"\"\"," +
               $"\"\"," +
               $"\"True\"," +
               $"\"False\"," +
               $"\"{EscapeCsvField(platform)}\"";
    }

    /// <summary>
    /// Generate a _Jobs.csv WITHOUT a Platform column (legacy format).
    /// </summary>
    public static string GenerateJobsLegacyNoPlatform()
    {
        return JobHeaderLegacy + "\n" +
               "\"Legacy Backup Job\"," +
               "\"Backup\"," +
               "\"01/01/2026 01:00:00 a.m.\"," +
               "\"Start time: [01/01/2026 1:00:00 a.m.]\"," +
               "\"14\"," +
               "\"Default Backup Repository\"," +
               "\"Increment\"," +
               "\"Daily\"," +
               "\"Sunday\"," +
               "\"False\"," +
               "\"False\"," +
               "\"Sunday\"," +
               "\"00000000-0000-0000-0000-000000000000\"," +
               "\"1099511627776\"," +
               "\"Days\"," +
               "\"14\"," +
               "\"14\"," +
               "\"14\"," +
               "\"False\"," +
               "\"5\"," +
               "\"True\"," +
               "\"KbBlockSize1024\"," +
               "\"True\"," +
               "\"False\"," +
               "\"True\"," +
               "\"False\"," +
               "\"False\"," +
               "\"False\"," +
               "\"False\"," +
               "\"4\"," +
               "\"False\"," +
               "\"1\"," +
               "\"False\"," +
               "\"1\"," +
               "\"None\"," +
               "\"102.5\"," +
               "\"False\"," +
               "\"True\"," +
               "\"False\"," +
               "\"\"," +
               "\"True\"," +
               "\"False\"";
    }

    /// <summary>
    /// Generate a _Jobs.csv with a Platform column present but value is empty.
    /// </summary>
    public static string GenerateJobsEmptyPlatform()
    {
        return JobHeader + "\n" +
               "\"Standard Backup Job\"," +
               "\"Backup\"," +
               "\"01/01/2026 01:00:00 a.m.\"," +
               "\"Start time: [01/01/2026 1:00:00 a.m.]\"," +
               "\"14\"," +
               "\"Default Backup Repository\"," +
               "\"Increment\"," +
               "\"Daily\"," +
               "\"Sunday\"," +
               "\"False\"," +
               "\"False\"," +
               "\"Sunday\"," +
               "\"00000000-0000-0000-0000-000000000000\"," +
               "\"1099511627776\"," +
               "\"Days\"," +
               "\"14\"," +
               "\"14\"," +
               "\"14\"," +
               "\"False\"," +
               "\"5\"," +
               "\"True\"," +
               "\"KbBlockSize1024\"," +
               "\"True\"," +
               "\"False\"," +
               "\"True\"," +
               "\"False\"," +
               "\"False\"," +
               "\"False\"," +
               "\"False\"," +
               "\"4\"," +
               "\"False\"," +
               "\"1\"," +
               "\"False\"," +
               "\"1\"," +
               "\"None\"," +
               "\"102.5\"," +
               "\"False\"," +
               "\"True\"," +
               "\"False\"," +
               "\"\"," +
               "\"True\"," +
               "\"False\"," +
               "\"\"";
    }

    #endregion

    #region Helpers

    private static string EscapeCsvField(string value)
    {
        // Escape double-quotes by doubling them (RFC 4180)
        return value.Replace("\"", "\"\"");
    }

    #endregion
}
