using System;
using System.Windows;
using VeeamHealthCheck.Shared;

namespace VeeamHealthCheck.Functions.CredsWindow
{
    public partial class CredentialPromptWindow : Window
    {
        public string Username => UsernameBox.Text;

        public string Password => PasswordBox.Password;

        public CredentialPromptWindow(string host)
        {
            // Belt-and-suspenders: silent (unattended) mode must never show a
            // credential dialog. Any caller that bypasses CredsHandler and
            // constructs this window directly while CGlobals.Silent is true
            // is a bug and should fail fast rather than hang the process.
            if (CGlobals.Silent)
            {
                throw new InvalidOperationException(
                    "CredentialPromptWindow must not be invoked in silent mode.");
            }

            InitializeComponent();
            this.Title = $"Authentication Required - {host}";
            ServerText.Text = $"Please enter credentials to connect to {host}";
            UsernameBox.Focus();
        }

        private void Ok_Click(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrWhiteSpace(this.Username) && !string.IsNullOrWhiteSpace(this.Password))
            {
                this.DialogResult = true;
            }
            else
            {

                MessageBox.Show("Please enter both username and password.", "Missing Information", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }
    }
}