// Copyright (c) 2021, Adam Congdon <adam.congdon2@gmail.com>
// MIT License
using System;
using System.Data.SqlClient;
using VeeamHealthCheck.Shared;

namespace VeeamHealthCheck.Functions.Collection.DB
{
    class CDbAccessor
    {
        public string DbAccessorString()
        {
            return this.StringBuilder().ConnectionString;
        }

        private SqlConnectionStringBuilder StringBuilder()
        {
            SqlConnectionStringBuilder builder = this.SimpleConnectionBuilder();
            return builder;
        }

        private SqlConnectionStringBuilder SimpleConnectionBuilder()
        {
            SqlConnectionStringBuilder builder = new SqlConnectionStringBuilder(GetConnectionString());
            builder.Remove("Initial Catalog");

            // builder["Server"] = server;
            CRegReader reg = new CRegReader();
            reg.GetDbInfo();
            string host = reg.HostString;
            string db = reg.DbString;
            if (host == null || db == null)
            {
                // why am i asking for interaction?

                // Console.WriteLine("Please enter SQL Host Name & Instance (i.e. vbr-server\\sqlserver2016):");
                // host = Console.ReadLine();
                // Console.WriteLine("Please enter DB name:");
                // db = Console.ReadLine();
            }

            builder["Server"] = host;

            // CGlobals.DBHOSTNAME = host;
            builder["Database"] = db;

            // Pre-flight test against the just-built connection string. If it fails we
            // still return the builder so CQueries can log per-query failures inline;
            // the warning surfaces the most common cause up front so it's obvious in the
            // log: the user running vHC lacks db_datareader on the Veeam config DB.
            if (!this.TestConnection(builder.ConnectionString))
            {
                CGlobals.Logger.Warning(
                    "SQL connection pre-flight failed. If subsequent queries log 'Login failed', " +
                    "the user running vHC needs db_datareader on the Veeam config database, " +
                    "or vHC should be run under the VBR service account.");
            }
            return builder;
        }

        private bool TestConnection(string connectionString)
        {
            try
            {
                using var connection = new SqlConnection(connectionString);
                using var command = new SqlCommand("select @@version", connection);
                connection.Open();
                return true;
            }
            catch (Exception e)
            {
                CGlobals.Logger.Warning("Sql Test Connection Failed: " + e.Message);
                return false;
            }
        }

        private static string GetConnectionString()
        {
            return "Server=(local);Integrated Security=SSPI;";
        }
    }
}
