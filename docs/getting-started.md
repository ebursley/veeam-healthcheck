# Getting Started

## Requirements

- Windows system with **VBR Console** or **VB365** installed
- Run as an **elevated user** with **Backup Administrator** role
- **500 MB** free disk space on `C:\` (default output: `C:\temp\vHC`)
- Veeam Cloud Service Provider servers are **not** supported

## Supported Versions

| Product | Supported Versions | Notes |
|---|---|---|
| **Veeam Backup & Replication** | v12.3, v13 (Windows & Linux) | For v11/v12 pre-12.3, use [Health Check v2](https://github.com/VeeamHub/veeam-healthcheck/releases/tag/v2.0.0.681) |
| **Veeam Backup for Microsoft 365** | v6, v7, v8 | |

## Installation

1. **[Download](https://github.com/VeeamHub/veeam-healthcheck/releases/latest)** the latest `VeeamHealthCheck.zip`
2. **Extract** the archive on your Veeam server
3. **Run** `VeeamHealthCheck.exe` as Administrator

No installer. No dependencies to install. Single executable.

## Running a Health Check

=== "GUI"
    1. Launch `VeeamHealthCheck.exe` as Administrator
    2. Configure options (reporting window, export format, output path)
    3. Accept the terms and click **RUN**
    4. Review the generated report

=== "CLI"
    ```powershell
    # Standard health check (7-day window)
    VeeamHealthCheck.exe /run

    # 30-day window, also export PDF
    VeeamHealthCheck.exe /run /days:30 /pdf

    # Custom output directory, open report when done
    VeeamHealthCheck.exe /run /outdir=D:\Reports /show:report
    ```

## CLI Reference

```
VeeamHealthCheck.exe [options]
```

| Option | Description |
|---|---|
| `/run` | Execute health check via CLI |
| `/gui` | Launch graphical interface |
| `/help` | Show full help menu |
| `/days:<N>` | Reporting window: 7, 12, 30, or 90 days (default: 7) |
| `/outdir=<path>` | Output directory (default: `C:\temp\vHC`) |
| `/pdf` | Also export as PDF |
| `/pptx` | Also export as PowerPoint |
| `/scrub:true` | Anonymize sensitive data |
| `/lite` | Skip per-job HTML exports (faster) |
| `/show:report` | Open report in browser when done |
| `/show:files` | Open output folder in Explorer |
| `/remote` | Enable remote execution |
| `/host=<hostname>` | Target remote Veeam server |
| `/security` | Run security-focused assessment only |
| `/import[:<path>]` | Generate report from existing CSV data |
| `/clearcreds` | Clear stored credentials |
| `/debug` | Enable debug logging |

## Remote Execution

Run against a remote Veeam server without being locally logged into it:

```powershell
VeeamHealthCheck.exe /run /host=vbrserver.veeam.local
```

Credentials are prompted and stored securely in Windows Credential Manager.

## Troubleshooting

| Problem | Solution |
|---|---|
| **"Access Denied"** | Run as Administrator with Backup Administrator role |
| **"No Veeam installation detected"** | Tool must run on a system with VBR Console or VB365 installed |
| **Low disk space errors** | Ensure `C:\` has at least 500 MB free |
| **PowerShell errors** | Verify PowerShell 7+ is installed |
| **Credentials not working** | Run `/clearcreds` then re-authenticate |

## Sample Report

[View a sample anonymized report](https://htmlpreview.github.io/?https://github.com/VeeamHub/veeam-healthcheck/blob/master/SAMPLE/Veeam%20Health%20Check%20Report_VBR_anon_2024.11.01.101304.html) to see what output looks like before running.
