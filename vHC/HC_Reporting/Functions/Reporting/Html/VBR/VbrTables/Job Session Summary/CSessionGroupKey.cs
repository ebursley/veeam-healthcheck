// <copyright file="CSessionGroupKey.cs" company="PlaceholderCompany">
// Copyright (c) PlaceholderCompany. All rights reserved.
// </copyright>

using System;
using VeeamHealthCheck.Functions.Reporting.DataTypes;

namespace VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.Job_Session_Summary
{
    /// <summary>
    /// Computes stable group identifiers and display names for session rollup.
    /// Children inherit the parent's PolicyTag (GUID) and PolicyName, so grouping
    /// by <see cref="Of"/> automatically merges per-machine child sessions under
    /// their parent. See ADR 0019.
    /// </summary>
    internal static class CSessionGroupKey
    {
        /// <summary>
        /// Returns the rollup group identifier for a session. Preference order:
        ///   1. PolicyTag - child sessions point at their parent's job GUID.
        ///   2. JobId - parents and standalone jobs use their own GUID.
        ///   3. JobName prefix - legacy CSVs without GUID columns.
        /// </summary>
        public static string Of(CJobSessionInfo s)
        {
            var ownId = s.JobId.GetValueOrDefault();
            if (s.PolicyTag.HasValue
                && s.PolicyTag.Value != Guid.Empty
                && s.PolicyTag.Value != ownId)
            {
                return "id:" + s.PolicyTag.Value.ToString("D");
            }

            if (ownId != Guid.Empty)
            {
                return "id:" + ownId.ToString("D");
            }

            return "name:" + (s.JobName ?? string.Empty);
        }

        /// <summary>
        /// Returns the display name for a session's group. Children carry the
        /// parent's PolicyName; parents/standalone fall back to their own JobName.
        /// </summary>
        public static string DisplayName(CJobSessionInfo s) =>
            !string.IsNullOrEmpty(s.PolicyName) ? s.PolicyName : (s.JobName ?? string.Empty);
    }
}
