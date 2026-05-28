using System;
using VeeamHealthCheck.Functions.Reporting.DataTypes;
using VeeamHealthCheck.Functions.Reporting.Html.VBR.VbrTables.Job_Session_Summary;
using Xunit;

namespace VhcXTests.Functions.Reporting.Html.VBR.VbrTables
{
    public class CSessionGroupKeyTEST
    {
        private static readonly Guid ParentId = Guid.Parse("02fe84bc-7394-42b5-bdb2-81a56190d8c5");
        private static readonly Guid ChildId  = Guid.Parse("592c44dc-861c-48fc-b70e-e9916c790222");

        [Fact]
        public void Of_ChildWithPolicyTag_ReturnsParentGuid()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Physical - Linux Servers - lab01",
                JobId      = ChildId,
                PolicyName = "Physical - Linux Servers",
                PolicyTag  = ParentId,
            };
            Assert.Equal("id:" + ParentId.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_ParentSession_UsesOwnJobId()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Physical - Linux Servers",
                JobId      = ParentId,
                PolicyName = "Physical - Linux Servers",
                PolicyTag  = ParentId,  // equal to own JobId
            };
            Assert.Equal("id:" + ParentId.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_BCParent_PolicyTagEmpty_UsesOwnJobId()
        {
            // BC orchestrator (SimpleBackupCopyPolicy) has empty PolicyName/PolicyTag,
            // per the probe-policy-link.csv evidence.
            var parentGuid = Guid.Parse("2b60f399-4be7-4548-937d-c9357d5b59e6");
            var s = new CJobSessionInfo
            {
                JobName    = "Backup Copy - Engineers CHC 02",
                JobId      = parentGuid,
                PolicyName = null,
                PolicyTag  = null,
            };
            Assert.Equal("id:" + parentGuid.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_RegularBackup_NoChildrenNoPolicyTag_UsesOwnJobId()
        {
            // Hyper-V Backup case: PolicyName/PolicyTag empty.
            var jobId = Guid.Parse("68621a52-2a9c-4fc5-a3f4-acc1c2caa44e");
            var s = new CJobSessionInfo
            {
                JobName    = "Hyper-V - Engineers CHC 01",
                JobId      = jobId,
                PolicyName = null,
                PolicyTag  = null,
            };
            Assert.Equal("id:" + jobId.ToString("D"), CSessionGroupKey.Of(s));
        }

        [Fact]
        public void Of_LegacyCsv_NoGuids_FallsBackToJobName()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Legacy Job",
                JobId      = null,
                PolicyName = null,
                PolicyTag  = null,
            };
            Assert.Equal("name:Legacy Job", CSessionGroupKey.Of(s));
        }

        [Fact]
        public void DisplayName_PrefersPolicyName()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Physical - Linux Servers - lab01",
                PolicyName = "Physical - Linux Servers",
            };
            Assert.Equal("Physical - Linux Servers", CSessionGroupKey.DisplayName(s));
        }

        [Fact]
        public void DisplayName_FallsBackToJobName_WhenPolicyNameEmpty()
        {
            var s = new CJobSessionInfo
            {
                JobName    = "Hyper-V - Engineers CHC 01",
                PolicyName = "",
            };
            Assert.Equal("Hyper-V - Engineers CHC 01", CSessionGroupKey.DisplayName(s));
        }
    }
}
