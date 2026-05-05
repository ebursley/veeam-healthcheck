// <copyright file="StripAnsiCodesTests.cs" company="PlaceholderCompany">
// Copyright (c) PlaceholderCompany. All rights reserved.
// </copyright>

using VeeamHealthCheck.Functions.Collection;
using Xunit;

namespace VeeamHealthCheck.Tests.Functions.Collection
{
    public class StripAnsiCodesTests
    {
        [Theory]
        [InlineData("\x1B[31;1mAccess is denied\x1B[0m", "Access is denied")]
        [InlineData("\x1B[31;1mERROR\x1B[0m", "ERROR")]
        [InlineData("No escape codes here", "No escape codes here")]
        [InlineData("\x1B[0m\x1B[31;1mRed text\x1B[0m trailing", "Red text trailing")]
        [InlineData("", "")]
        public void StripAnsiCodes_RemovesEscapeSequences(string input, string expected)
        {
            string result = CCollections.StripAnsiCodes(input);
            Assert.Equal(expected, result);
        }
    }
}
