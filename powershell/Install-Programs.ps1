# #Requires -RunAsAdministrator  # TODO: Uncomment for production use
<#
.SYNOPSIS
    Guided UI to silently install Bluebeam Revu, Microsoft Project, Procore Drive, and Dropbox.

.DESCRIPTION
    Presents a Windows Forms GUI where the user selects which programs to install,
    picks a Bluebeam version, then downloads and installs everything silently.
    Requires the script to be run as Administrator.

.NOTES
    Author:  Chase Jank
    Version: 1.0
    Date:    2026-02-18

    Supported Applications:
      - Bluebeam Revu 21 (Trial) or 20.3.30
      - Microsoft Project Professional (via Office Deployment Tool)
      - Procore Drive (MSI)
      - Dropbox (full offline installer)

    Downloads are cached in a "Downloads" folder next to this script so
    re-running the installer does not re-download files that already exist.
#>

# Stop on any terminating error so try/catch blocks work reliably
$ErrorActionPreference = "Stop"

# Load Windows Forms and Drawing assemblies for the GUI
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Enable modern visual styles (themed buttons, checkboxes, etc.)
[System.Windows.Forms.Application]::EnableVisualStyles()

# ===================================================================
# Downloads directory (same folder as this script, reusable across runs)
# Installers are cached here so subsequent runs skip the download step.
# ===================================================================
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition   # Directory containing this .ps1 file
$TempDir = Join-Path $ScriptRoot "Downloads"                          # e.g. .\automation\Powershell\Downloads
if (-not (Test-Path $TempDir)) {
    New-Item -ItemType Directory -Path $TempDir | Out-Null
}

# ===================================================================
# Build the GUI
# Creates a fixed-size WinForms dialog with checkboxes for each app,
# a Bluebeam version picker, progress bar, status label, install
# button, and a scrollable log textbox.
# ===================================================================

# --- Main form window ---
$form = New-Object System.Windows.Forms.Form
$form.Text            = "Software Installer"
$form.Size            = New-Object System.Drawing.Size(500, 700)      # Width x Height in pixels
$form.StartPosition   = "CenterScreen"                                # Open centered on the display
$form.FormBorderStyle = "FixedDialog"                                 # Non-resizable border
$form.MaximizeBox     = $false                                        # Disable maximize button
$form.Font            = New-Object System.Drawing.Font("Segoe UI", 10)

# --- Title label at the top of the form ---
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text     = "Select programs to install:"
$lblTitle.Location = New-Object System.Drawing.Point(20, 15)
$lblTitle.Size     = New-Object System.Drawing.Size(440, 25)
$lblTitle.Font     = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

# --- Bluebeam Revu checkbox ---
# When checked, enables the version radio-button group below
$chkBluebeam = New-Object System.Windows.Forms.CheckBox
$chkBluebeam.Text     = "Bluebeam Revu"
$chkBluebeam.Location = New-Object System.Drawing.Point(30, 55)
$chkBluebeam.Size     = New-Object System.Drawing.Size(200, 25)
$form.Controls.Add($chkBluebeam)

# --- Bluebeam version selection group ---
# Contains two radio buttons for choosing between Revu 21 and 20.3.30.
# Disabled by default; enabled when the Bluebeam checkbox is checked.
$grpBbVersion = New-Object System.Windows.Forms.GroupBox
$grpBbVersion.Text     = "Bluebeam Version"
$grpBbVersion.Location = New-Object System.Drawing.Point(50, 85)
$grpBbVersion.Size     = New-Object System.Drawing.Size(380, 70)
$grpBbVersion.Enabled  = $false                                       # Greyed out until Bluebeam is checked

# Radio button: Revu 21 (Trial download from bluebeam.com)
$rdoBb21 = New-Object System.Windows.Forms.RadioButton
$rdoBb21.Text     = "Revu 21 (v21.0.8 - Trial)"
$rdoBb21.Location = New-Object System.Drawing.Point(15, 20)
$rdoBb21.Size     = New-Object System.Drawing.Size(340, 22)
$rdoBb21.Checked  = $true                                             # Default selection
$grpBbVersion.Controls.Add($rdoBb21)

# Radio button: Revu 20.3.30 (direct EXE download)
$rdoBb20 = New-Object System.Windows.Forms.RadioButton
$rdoBb20.Text     = "Revu 20 (v20.3.30)"
$rdoBb20.Location = New-Object System.Drawing.Point(15, 44)
$rdoBb20.Size     = New-Object System.Drawing.Size(340, 22)
$grpBbVersion.Controls.Add($rdoBb20)

$form.Controls.Add($grpBbVersion)

# Toggle the version group enabled state when the Bluebeam checkbox changes
$chkBluebeam.Add_CheckedChanged({ $grpBbVersion.Enabled = $chkBluebeam.Checked })

# --- Microsoft Project checkbox ---
# Uses the Office Deployment Tool (ODT) to download and install silently
$chkProject = New-Object System.Windows.Forms.CheckBox
$chkProject.Text     = "Microsoft Project (via Office Deployment Tool)"
$chkProject.Location = New-Object System.Drawing.Point(30, 170)
$chkProject.Size     = New-Object System.Drawing.Size(400, 25)
$form.Controls.Add($chkProject)

# --- Procore Drive checkbox ---
# Downloads the MSI from Procore's public storage bucket
$chkProcore = New-Object System.Windows.Forms.CheckBox
$chkProcore.Text     = "Procore Drive"
$chkProcore.Location = New-Object System.Drawing.Point(30, 210)
$chkProcore.Size     = New-Object System.Drawing.Size(400, 25)
$form.Controls.Add($chkProcore)

# --- Dropbox checkbox ---
# Downloads the full offline installer from dropbox.com
$chkDropbox = New-Object System.Windows.Forms.CheckBox
$chkDropbox.Text     = "Dropbox"
$chkDropbox.Location = New-Object System.Drawing.Point(30, 250)
$chkDropbox.Size     = New-Object System.Drawing.Size(400, 25)
$form.Controls.Add($chkDropbox)

# --- Select All checkbox ---
# Convenience toggle: checks or unchecks all four program checkboxes at once
$chkAll = New-Object System.Windows.Forms.CheckBox
$chkAll.Text     = "Select All"
$chkAll.Location = New-Object System.Drawing.Point(30, 295)
$chkAll.Size     = New-Object System.Drawing.Size(200, 25)
$chkAll.Font     = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$chkAll.Add_CheckedChanged({
    # Propagate the checked state to every program checkbox
    $chkBluebeam.Checked = $chkAll.Checked
    $chkProject.Checked  = $chkAll.Checked
    $chkProcore.Checked  = $chkAll.Checked
    $chkDropbox.Checked  = $chkAll.Checked
})
$form.Controls.Add($chkAll)

# --- Progress bar ---
# Fills proportionally as each selected program completes (0-100%)
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 340)
$progressBar.Size     = New-Object System.Drawing.Size(445, 25)
$progressBar.Minimum  = 0
$progressBar.Maximum  = 100
$progressBar.Value    = 0
$form.Controls.Add($progressBar)

# --- Status label ---
# Single-line text below the progress bar showing the current operation
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text     = "Ready"
$lblStatus.Location = New-Object System.Drawing.Point(20, 370)
$lblStatus.Size     = New-Object System.Drawing.Size(445, 20)
$lblStatus.ForeColor = [System.Drawing.Color]::DarkSlateGray
$form.Controls.Add($lblStatus)

# --- Install button ---
# Kicks off the download + install sequence for all checked programs
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Text     = "Install Selected"
$btnInstall.Location = New-Object System.Drawing.Point(160, 400)
$btnInstall.Size     = New-Object System.Drawing.Size(160, 35)
$btnInstall.Font     = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

# --- Log output label ---
$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text     = "Log:"
$lblLog.Location = New-Object System.Drawing.Point(20, 445)
$lblLog.Size     = New-Object System.Drawing.Size(445, 20)
$lblLog.Font     = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblLog)

# --- Log textbox ---
# Read-only, dark-themed, scrollable multi-line textbox that records
# timestamped entries for every download, install, and error event.
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location   = New-Object System.Drawing.Point(20, 468)
$txtLog.Size       = New-Object System.Drawing.Size(445, 180)
$txtLog.Multiline  = $true
$txtLog.ReadOnly   = $true                                            # User cannot edit log text
$txtLog.ScrollBars = "Vertical"                                       # Scroll when log grows long
$txtLog.Font       = New-Object System.Drawing.Font("Consolas", 9)    # Monospace for clean alignment
$txtLog.BackColor  = [System.Drawing.Color]::FromArgb(30, 30, 30)     # Dark background
$txtLog.ForeColor  = [System.Drawing.Color]::FromArgb(200, 200, 200)  # Light text
$form.Controls.Add($txtLog)

# --- Log helper function ---
# Appends a timestamped message to the log textbox and updates the status label.
# Called throughout the install logic to give real-time feedback.
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $txtLog.AppendText("[$timestamp] $Message`r`n")
    $lblStatus.Text = $Message
    $form.Refresh()   # Force the UI to repaint so the user sees updates immediately
}

# ===================================================================
# Install logic  (runs when the "Install Selected" button is clicked)
# ===================================================================
$btnInstall.Add_Click({

    # Build a list of selected programs to determine progress increments
    $selected = @()
    if ($chkBluebeam.Checked) { $selected += "Bluebeam" }
    if ($chkProject.Checked)  { $selected += "Project" }
    if ($chkProcore.Checked)  { $selected += "Procore" }
    if ($chkDropbox.Checked)  { $selected += "Dropbox" }

    # Guard: require at least one selection before proceeding
    if ($selected.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "Please select at least one program to install.",
            "Nothing Selected",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }

    # Lock all controls during installation to prevent double-clicks / changes
    $btnInstall.Enabled  = $false
    $chkAll.Enabled      = $false
    $chkBluebeam.Enabled = $false
    $chkProject.Enabled  = $false
    $chkProcore.Enabled  = $false
    $chkDropbox.Enabled  = $false
    $grpBbVersion.Enabled = $false

    # Progress tracking: step counter and results hashtable
    $step     = 0                 # Current completed step count
    $total    = $selected.Count   # Total number of programs to install
    $results  = @{}               # Stores "Installed" or "FAILED" per program

    # Helper: increments step count, calculates percentage, updates progress bar
    function Update-Progress {
        param([string]$Status)
        $script:step++
        $pct = [math]::Round(($script:step / $total) * 100)
        $progressBar.Value = $pct
        $lblStatus.Text    = $Status
        $form.Refresh()
    }

    # ---------------------------------------------------------------
    # Bluebeam Revu
    # Downloads the selected version (21 Trial or 20.3.30) and runs
    # a silent install with the /S flag.
    # ---------------------------------------------------------------
    if ($chkBluebeam.Checked) {
        # Pick the URL and filename based on the selected radio button
        if ($rdoBb21.Checked) {
            $bbUrl  = "https://bluebeam.com/FullRevuTRIAL"                                          # Revu 21 Trial
            $bbFile = Join-Path $TempDir "BluebeamRevu21.exe"
            $bbVer  = "21"
        } else {
            $bbUrl  = "https://downloads.bluebeam.com/software/downloads/20.3.30/BbRevu20.3.30.exe" # Revu 20.3.30
            $bbFile = Join-Path $TempDir "BbRevu20.3.30.exe"
            $bbVer  = "20.3.30"
        }

        try {
            # Download only if we don't already have the installer cached
            if (-not (Test-Path $bbFile)) {
                Write-Log "Downloading Bluebeam Revu $bbVer..."
                Invoke-WebRequest -Uri $bbUrl -OutFile $bbFile -UseBasicParsing
                Write-Log "Download complete: $bbFile"
            } else {
                Write-Log "Using cached installer: $bbFile"
            }
            # Run installer silently (/S = silent mode for NSIS-based installers)
            Write-Log "Installing Bluebeam Revu $bbVer (silent)..."
            Start-Process -FilePath $bbFile -ArgumentList "/S" -Wait -NoNewWindow
            Write-Log "Bluebeam Revu $bbVer installed successfully."
            $results["Bluebeam Revu $bbVer"] = "Installed"
        } catch {
            Write-Log "ERROR: Bluebeam Revu $bbVer - $($_.Exception.Message)"
            $results["Bluebeam Revu $bbVer"] = "FAILED"
        }
        Update-Progress "Bluebeam Revu $bbVer complete."
    }

    # ---------------------------------------------------------------
    # Microsoft Project (via Office Deployment Tool)
    # 1. Downloads the ODT self-extractor from Microsoft
    # 2. Extracts setup.exe to a local ODT folder
    # 3. Generates a configuration XML for Project Professional Retail
    # 4. Runs setup.exe /configure to install silently
    # ---------------------------------------------------------------
    if ($chkProject.Checked) {
        $ODTUrl    = "https://aka.ms/officedeploymenttool"             # Redirects to latest ODT
        $ODTSetup  = Join-Path $TempDir "ODTSetup.exe"                 # Downloaded self-extractor
        $ODTDir    = Join-Path $TempDir "ODT"                          # Extraction target folder
        $ConfigXml = Join-Path $ODTDir "project-config.xml"            # Generated install config

        try {
            # Download the ODT self-extractor (only if not cached)
            if (-not (Test-Path $ODTSetup)) {
                Write-Log "Downloading Office Deployment Tool..."
                Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTSetup -UseBasicParsing
                Write-Log "ODT download complete."
            } else {
                Write-Log "Using cached ODT installer."
            }
            # Create the extraction directory if it doesn't exist
            if (-not (Test-Path $ODTDir)) {
                New-Item -ItemType Directory -Path $ODTDir | Out-Null
            }
            # Extract setup.exe and supporting files from the self-extractor
            Write-Log "Extracting ODT..."
            Start-Process -FilePath $ODTSetup -ArgumentList "/quiet /extract:$ODTDir" -Wait -NoNewWindow

            # Build the XML configuration for Project Professional (64-bit, Current Channel)
            # Display Level="None" = fully silent; AcceptEULA="TRUE" = auto-accept license
            $xmlContent = '<Configuration>' + "`n"
            $xmlContent += '  <Add OfficeClientEdition="64" Channel="Current">' + "`n"
            $xmlContent += '    <Product ID="ProjectProRetail">' + "`n"
            $xmlContent += '      <Language ID="en-us" />' + "`n"
            $xmlContent += '    </Product>' + "`n"
            $xmlContent += '  </Add>' + "`n"
            $xmlContent += '  <Display Level="None" AcceptEULA="TRUE" />' + "`n"
            $xmlContent += '  <Property Name="AUTOACTIVATE" Value="1" />' + "`n"
            $xmlContent += '</Configuration>'
            Set-Content -Path $ConfigXml -Value $xmlContent -Encoding UTF8

            # Run the ODT setup.exe with the generated config to install Project
            $SetupExe = Join-Path $ODTDir "setup.exe"
            if (Test-Path $SetupExe) {
                Write-Log "Installing Microsoft Project (silent)..."
                $odtArgs = '/configure "' + $ConfigXml + '"'
                Start-Process -FilePath $SetupExe -ArgumentList $odtArgs -Wait -NoNewWindow
                Write-Log "Microsoft Project installed successfully."
                $results["Microsoft Project"] = "Installed"
            } else {
                Write-Log "ERROR: setup.exe not found after ODT extraction."
                $results["Microsoft Project"] = "FAILED"
            }
        } catch {
            Write-Log "ERROR: Microsoft Project - $($_.Exception.Message)"
            $results["Microsoft Project"] = "FAILED"
        }
        Update-Progress "Microsoft Project complete."
    }

    # ---------------------------------------------------------------
    # Procore Drive
    # Downloads the latest MSI from Procore's public GCS bucket
    # and installs via msiexec with /qn (quiet, no UI) /norestart.
    # ---------------------------------------------------------------
    if ($chkProcore.Checked) {
        $ProcoreMsi = Join-Path $TempDir "ProcoreDrive.msi"
        $ProcoreUrl = "https://storage.googleapis.com/procore-drive-releases/latest/ProcoreDrive.msi"

        try {
            # Download the MSI (only if not cached)
            if (-not (Test-Path $ProcoreMsi)) {
                Write-Log "Downloading Procore Drive..."
                Invoke-WebRequest -Uri $ProcoreUrl -OutFile $ProcoreMsi -UseBasicParsing
                Write-Log "Procore Drive download complete."
            } else {
                Write-Log "Using cached Procore Drive installer."
            }
            # Install silently via msiexec: /i = install, /qn = quiet no UI, /norestart = suppress reboot
            Write-Log "Installing Procore Drive (silent)..."
            $msiArgs = '/i "' + $ProcoreMsi + '" /qn /norestart'
            Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -NoNewWindow
            Write-Log "Procore Drive installed successfully."
            $results["Procore Drive"] = "Installed"
        } catch {
            Write-Log "ERROR: Procore Drive - $($_.Exception.Message)"
            $results["Procore Drive"] = "FAILED"
        }
        Update-Progress "Procore Drive complete."
    }

    # ---------------------------------------------------------------
    # Dropbox
    # Downloads the full offline installer from dropbox.com and
    # installs silently with the /s flag.
    # ---------------------------------------------------------------
    if ($chkDropbox.Checked) {
        $DropboxInstaller = Join-Path $TempDir "DropboxInstaller.exe"
        $DropboxUrl       = 'https://www.dropbox.com/download?plat=win&type=full'  # Full offline installer URL

        try {
            # Download the installer (only if not cached)
            if (-not (Test-Path $DropboxInstaller)) {
                Write-Log "Downloading Dropbox..."
                Invoke-WebRequest -Uri $DropboxUrl -OutFile $DropboxInstaller -UseBasicParsing
                Write-Log "Dropbox download complete."
            } else {
                Write-Log "Using cached Dropbox installer."
            }
            # Run silent install (/s flag)
            Write-Log "Installing Dropbox (silent)..."
            Start-Process -FilePath $DropboxInstaller -ArgumentList "/s" -Wait -NoNewWindow
            Write-Log "Dropbox installed successfully."
            $results["Dropbox"] = "Installed"
        } catch {
            Write-Log "ERROR: Dropbox - $($_.Exception.Message)"
            $results["Dropbox"] = "FAILED"
        }
        Update-Progress "Dropbox complete."
    }

    # ---------------------------------------------------------------
    # Summary
    # Logs the final result for each program and the download path.
    # ---------------------------------------------------------------
    $progressBar.Value = 100

    Write-Log "========================================"
    Write-Log "SUMMARY"
    foreach ($key in $results.Keys) {
        Write-Log "  $key  -  $($results[$key])"
    }
    Write-Log "Downloads saved in: $TempDir"
    Write-Log "All tasks complete."

    # Re-enable all controls so the user can run again if needed
    $btnInstall.Enabled  = $true
    $chkAll.Enabled      = $true
    $chkBluebeam.Enabled = $true
    $chkProject.Enabled  = $true
    $chkProcore.Enabled  = $true
    $chkDropbox.Enabled  = $true
    if ($chkBluebeam.Checked) { $grpBbVersion.Enabled = $true }
})

# ===================================================================
# Show the form (blocks until the user closes the window)
# ===================================================================
[void]$form.ShowDialog()
