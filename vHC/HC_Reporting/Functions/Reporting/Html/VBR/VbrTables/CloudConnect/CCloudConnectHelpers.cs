// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
namespace VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.CloudConnect
{
    internal static class CCloudConnectHelpers
    {
        internal static string FormatMaxConcurrent(string raw) =>
            (string.IsNullOrWhiteSpace(raw) || raw.Trim() == "0") ? "Unlimited" : raw;

        internal static string FormatThrottleField(string throttlingEnabled, string fieldValue) =>
            (string.IsNullOrWhiteSpace(throttlingEnabled) ||
             throttlingEnabled.Trim().Equals("False", System.StringComparison.OrdinalIgnoreCase))
                ? "—" : fieldValue;
    }
}
