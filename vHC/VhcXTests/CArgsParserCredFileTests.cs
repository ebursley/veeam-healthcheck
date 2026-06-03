// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.IO;
using System.Text;
using VeeamHealthCheck.Startup;
using Xunit;

namespace VhcXTests
{
    /// <summary>
    /// Coverage for /credfile= loading — the supported, scriptable, multi-host
    /// credential mechanism for fleet execution (e.g. one file holding creds for
    /// 15 VBR servers). Replaces the removed /creds=user:pass inline flag, which
    /// leaked passwords into process args / CI logs.
    ///
    /// Credfile format: JSON map of host -> { Username, PasswordBase64 }, where
    /// PasswordBase64 is base64(UTF8(plaintext password)).
    /// </summary>
    [Collection("GlobalState")]
    public class CArgsParserCredFileTests : IDisposable
    {
        private readonly string _dir;

        public CArgsParserCredFileTests()
        {
            _dir = Path.Combine(Path.GetTempPath(), "vHC_CredFileTests_" + Guid.NewGuid());
            Directory.CreateDirectory(_dir);
        }

        public void Dispose()
        {
            try { Directory.Delete(_dir, recursive: true); } catch { /* best-effort */ }
        }

        private string WriteCredFile(string json)
        {
            string p = Path.Combine(_dir, "creds.json");
            File.WriteAllText(p, json);
            return p;
        }

        private static string B64(string plaintext) =>
            Convert.ToBase64String(Encoding.UTF8.GetBytes(plaintext));

        [Fact]
        public void LoadCredFile_ValidSingleHost_ReturnsZero()
        {
            string json = $"{{ \"vbr01.home.lab\": {{ \"Username\": \"veeamadmin\", \"PasswordBase64\": \"{B64("p@ssw0rd")}\" }} }}";
            int rc = new CArgsParser(new string[] { }).LoadCredFile(WriteCredFile(json));
            Assert.Equal(0, rc);
        }

        [Fact]
        public void LoadCredFile_Fleet15Hosts_ReturnsZero()
        {
            // The fleet scenario: one credfile, 15 VBR servers.
            var sb = new StringBuilder("{");
            for (int i = 1; i <= 15; i++)
            {
                if (i > 1) sb.Append(',');
                sb.Append($"\"vbr{i:D2}.home.lab\": {{ \"Username\": \"svc{i}\", \"PasswordBase64\": \"{B64("pw-" + i)}\" }}");
            }
            sb.Append('}');

            int rc = new CArgsParser(new string[] { }).LoadCredFile(WriteCredFile(sb.ToString()));
            Assert.Equal(0, rc);
        }

        [Fact]
        public void LoadCredFile_CaseInsensitiveKeys_ReturnsZero()
        {
            // Property names are deserialized case-insensitively (username/passwordbase64).
            string json = "{ \"vbr01.home.lab\": { \"username\": \"veeamadmin\", \"passwordbase64\": \"" + B64("x") + "\" } }";
            int rc = new CArgsParser(new string[] { }).LoadCredFile(WriteCredFile(json));
            Assert.Equal(0, rc);
        }

        [Fact]
        public void LoadCredFile_MissingFile_ReturnsNonZero()
        {
            int rc = new CArgsParser(new string[] { }).LoadCredFile(Path.Combine(_dir, "does-not-exist.json"));
            Assert.NotEqual(0, rc);
        }

        [Fact]
        public void LoadCredFile_MalformedJson_ReturnsNonZero()
        {
            int rc = new CArgsParser(new string[] { }).LoadCredFile(WriteCredFile("{ not valid json "));
            Assert.NotEqual(0, rc);
        }

        [Fact]
        public void LoadCredFile_EntryMissingPassword_ReturnsNonZero()
        {
            string json = "{ \"vbr01.home.lab\": { \"Username\": \"veeamadmin\" } }";
            int rc = new CArgsParser(new string[] { }).LoadCredFile(WriteCredFile(json));
            Assert.NotEqual(0, rc);
        }

        [Fact]
        public void LoadCredFile_EmptyObject_ReturnsNonZero()
        {
            int rc = new CArgsParser(new string[] { }).LoadCredFile(WriteCredFile("{}"));
            Assert.NotEqual(0, rc);
        }
    }
}
