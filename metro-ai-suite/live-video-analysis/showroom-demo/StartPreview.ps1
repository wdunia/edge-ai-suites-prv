# Starts the live-video-captioning showroom demo on the Ubuntu host over SSH
# and opens its dashboard on this laptop.
#
# The Wi-Fi password is never stored in this file: set the environment variable
# INTEL_DEMO_WLAN_PASSWORD or type it when prompted.

$SSID = "IntelDemoWLAN"

# Network configuration (must match setup-showroom-host.sh)
$remoteHostAddress = "192.168.100.1"
$port = 4173
$remoteUser = "sshuser"
$url = "http://${remoteHostAddress}:${port}"
$healthUrl = "${url}/api/health"
$remoteSSHAddress = "${remoteUser}@${remoteHostAddress}"

# Location of the demo checkout on the Ubuntu host. It is discovered
# automatically over SSH (setup-showroom-host.sh publishes it in
# ~sshuser/.showroom-demo); these values are only the fallback.
$demoDir = if ($env:SHOWROOM_DEMO_DIR) { $env:SHOWROOM_DEMO_DIR } else { "~/showroom-demo" }
$scriptPath = "$demoDir/run-demo-captioning.sh"
$stopScriptPath = "$demoDir/stop-all-demos.sh"

# Where the client installs itself on this laptop, so the demo can be started
# from the desktop without keeping the repository around.
$localInstallDir = Join-Path $env:LOCALAPPDATA "IntelShowroomDemo"

# The application binds WebRTC/RTSP to HOST_IP, so it has to be the access point
# address - not whatever interface holds the host's default route.
$hostIp = $remoteHostAddress

# The first start converts the model and pulls images, so allow a long wait.
$readyTimeoutSeconds = 1800

$tmuxSessionName = "captioning-demo"
$keyPath = Join-Path $HOME ".ssh\id_ed25519_LiveDemoKey"

# Trust-on-first-use: the host key is remembered in a dedicated known_hosts file
# and verified on every later connection, instead of disabling the check.
$knownHostsPath = Join-Path $HOME ".ssh\known_hosts_livedemo"

function Get-WifiPassword {
    param([string]$Ssid)

    if ($env:INTEL_DEMO_WLAN_PASSWORD) {
        return $env:INTEL_DEMO_WLAN_PASSWORD
    }

    $secure = Read-Host "Wi-Fi password for '$Ssid'" -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Install-LocalCopy {
    <#
        Copies this script (and RunDemo.bat next to it) into a stable folder on
        the laptop and puts a shortcut on the desktop, so the demo can be
        started later without the repository or a USB stick.
    #>
    param(
        [string]$InstallDir
    )

    $sourceDir = Split-Path -Parent $PSCommandPath
    if ($sourceDir -eq $InstallDir) {
        return
    }

    try {
        New-Item -ItemType Directory -Force $InstallDir | Out-Null
        Copy-Item $PSCommandPath (Join-Path $InstallDir "StartPreview.ps1") -Force

        $batchSource = Join-Path $sourceDir "RunDemo.bat"
        $batchTarget = Join-Path $InstallDir "RunDemo.bat"
        if (Test-Path $batchSource) {
            Copy-Item $batchSource $batchTarget -Force
        }
        else {
            # Recreate the launcher when only the PowerShell script was copied.
            @(
                '@echo off',
                'set SCRIPT_DIR=%~dp0',
                '',
                'powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT_DIR%StartPreview.ps1"'
            ) | Set-Content -Path $batchTarget -Encoding ASCII
        }

        $shortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "Intel Showroom Demo.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($shortcut)
        $link.TargetPath = $batchTarget
        $link.WorkingDirectory = $InstallDir
        $link.Description = "Start the Intel live video captioning showroom demo"
        $link.Save()

        Write-Output "Installed the demo launcher in $InstallDir (shortcut: $shortcut)"
    }
    catch {
        Write-Warning "Could not install the local copy: $($_.Exception.Message)"
    }
}

function Invoke-Cleanup {
    param(
        [string]$StopScriptPath,
        [string]$CurrentSSID,
        [string]$SSID,
        [string]$RemoteSSHAddress,
        [string]$Url,
        [string]$DemoDir,
        [string]$TmuxSessionName,
        [string]$KeyFile
    )

    Write-Output "To open the dashboard manually copy this address into your browser: $Url"
    Write-Host -ForeGroundColor DarkGreen "The demo starts its captioning runs automatically:"
    Write-Host -ForeGroundColor DarkGreen "  - one run for the USB camera (/dev/video0)"
    Write-Host -ForeGroundColor DarkGreen "  - one run per *.mp4 file in $DemoDir/videos"
    Write-Host -ForeGroundColor DarkGreen "To change the videos, copy new *.mp4 files into that directory."
    Write-Output "Click 'Enter' to stop the Demo"
    pause

    $cmd = @"
tmux kill-session -t '$TmuxSessionName' 2>/dev/null || true
bash '$StopScriptPath'
"@

    Invoke-SSH -RemoteTarget $RemoteSSHAddress -RemoteCommand $cmd -KeyFile $KeyFile

    if ($CurrentSSID -ne $SSID) {
        Write-Output "Restoring to previous network $CurrentSSID"
        netsh wlan connect name="$CurrentSSID" | Out-Null
    }
}

function Force-Network-Refresh {
    # Force refresh by opening windows forms
    Start-Process "ms-availablenetworks:"
    Start-Sleep -Milliseconds 1500
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
}

function Network-Connection-Attempt {
    param (
        [string]$RemoteHostAddress
    )
    $maxAttempts = 10
    $attempt = 0
    $online = $false

    do {
        $attempt++

        try {
            Write-Output "Checking connectivity to $RemoteHostAddress..."

            # Throws on failure
            Test-Connection -ComputerName $RemoteHostAddress -Count 1 -ErrorAction Stop | Out-Null

            $online = $true
            Write-Output "Host is online."
        }
        catch [System.Net.NetworkInformation.PingException] {
            Write-Output "Ping failed: Host unreachable or not responding."
        }
        catch [System.Net.Sockets.SocketException] {
            Write-Output "DNS or network socket error."
        }
        catch {
            Write-Output "Unexpected error: $($_.Exception.Message)"
        }

        if (-not $online) {
            Start-Sleep -Seconds 2
        }

    } until ($online -or $attempt -ge $maxAttempts)

    if (-not $online) {
        Write-Output "Timed out waiting for host to come online."
    }
}

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 30,
        [int]$DelaySeconds = 5,
        [string]$OperationName = "Operation"
    )

    $attempt = 0

    while ($attempt -lt $MaxRetries) {
        $attempt++

        Write-Output "$OperationName - Attempt $attempt/$MaxRetries"

        try {
            & $ScriptBlock
            return
        }
        catch {
            Write-Warning "$OperationName failed: $_"

            if ($_ -notmatch "RETRYABLE_SSH_FAILURE") {
                throw
            }

            if ($attempt -ge $MaxRetries) {
                throw
            }

            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

function Invoke-SSH {
    param(
        [string]$RemoteTarget,
        [string]$RemoteCommand,
        [string]$KeyFile,
        [int]$MaxRetries = 30,
        [int]$DelaySeconds = 5
    )

    Invoke-WithRetry `
        -MaxRetries $MaxRetries `
        -DelaySeconds $DelaySeconds `
        -OperationName "SSH -> $RemoteTarget" `
        -ScriptBlock {

            $sshArgs = @()
            if ($KeyFile) {
                $sshArgs += @(
                    "-i", $KeyFile,
                    "-o", "IdentitiesOnly=yes"
                )
            }

            $sshArgs += @(
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "UserKnownHostsFile=$knownHostsPath",
                "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=20",
                "-o", "ServerAliveCountMax=3"
            )

            $sshArgs += $RemoteTarget
            $sshArgs += $RemoteCommand

            $output = ssh @sshArgs 2>&1 | Out-String
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                return
            }

            if ($output -match "duplicate session") {
                Write-Output "Session already exists."
                return
            }

            if ($exitCode -eq 255) {
                throw "RETRYABLE_SSH_FAILURE`n$output"
            }
        }
}

function Invoke-SSHCapture {
    param(
        [string]$RemoteTarget,
        [string]$RemoteCommand,
        [string]$KeyFile
    )

    $sshArgs = @(
        "-i", $KeyFile,
        "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "UserKnownHostsFile=$knownHostsPath",
        "-o", "ConnectTimeout=10",
        $RemoteTarget,
        $RemoteCommand
    )

    $output = ssh @sshArgs 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    return ($output | Out-String).Trim()
}

function Resolve-DemoDir {
    <#
        setup-showroom-host.sh publishes the demo location in ~/.showroom-demo
        (plus a ~/showroom-demo symlink), so the client needs no configuration.
    #>
    param(
        [string]$RemoteTarget,
        [string]$KeyFile,
        [string]$Fallback
    )

    $discovered = Invoke-SSHCapture -RemoteTarget $RemoteTarget -KeyFile $KeyFile -RemoteCommand @'
cat ~/.showroom-demo 2>/dev/null || readlink -f ~/showroom-demo 2>/dev/null
'@

    if ($discovered -and (Invoke-SSHCapture -RemoteTarget $RemoteTarget -KeyFile $KeyFile `
                -RemoteCommand "test -x '$discovered/run-demo-captioning.sh' && echo ok") -eq "ok") {
        Write-Output "Discovered the demo on the host: $discovered"
        return $discovered
    }

    Write-Warning "Could not discover the demo location; falling back to $Fallback"
    return $Fallback
}

function Invoke-SSHWithInput {
    param(
        [string]$RemoteTarget,
        [string]$RemoteCommand,
        [string]$InputData,
        [string]$KeyFile,
        [int]$MaxRetries = 30,
        [int]$DelaySeconds = 5
    )

    Invoke-WithRetry `
        -MaxRetries $MaxRetries `
        -DelaySeconds $DelaySeconds `
        -OperationName "SSH(stdin) -> $RemoteTarget" `
        -ScriptBlock {

            $psi = New-Object System.Diagnostics.ProcessStartInfo

            $psi.FileName = "ssh"

            $psi.Arguments = @(
                "-i `"$KeyFile`""
                "-o IdentitiesOnly=yes"
                "-o StrictHostKeyChecking=accept-new"
                "-o UserKnownHostsFile=`"$knownHostsPath`""
                "-o ConnectTimeout=10"
                $RemoteTarget
                $RemoteCommand
            ) -join ' '

            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardError = $true
            $psi.RedirectStandardOutput = $true
            $psi.UseShellExecute = $false

            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $psi

            $process.Start() | Out-Null

            $process.StandardInput.Write($InputData)
            $process.StandardInput.Close()

            $stdout = $process.StandardOutput.ReadToEnd()
            $stderr = $process.StandardError.ReadToEnd()

            $process.WaitForExit()

            if ($process.ExitCode -eq 255) {
                throw "RETRYABLE_SSH_FAILURE`n$stderr"
            }

            if ($process.ExitCode -ne 0) {
                throw "SSH failed with exit code $($process.ExitCode)`n$stderr"
            }

            Write-Output $stdout
        }
}

function Wait-ForDemo {
    param(
        [string]$HealthUrl,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        try {
            # Direct request: the demo network must never be reached via a
            # corporate proxy configured on the laptop.
            $request = [System.Net.HttpWebRequest]::Create($HealthUrl)
            $request.Proxy = $null
            $request.Timeout = 5000
            $response = $request.GetResponse()
            try {
                $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
                $body = $reader.ReadToEnd()
            }
            finally {
                $response.Dispose()
            }

            if ($body -match "healthy") {
                return $true
            }
        }
        catch {
            # Service not up yet - keep polling.
        }

        Start-Sleep -Seconds 5
    }

    return $false
}

Install-LocalCopy -InstallDir $localInstallDir

$currentSSID = netsh wlan show interfaces |
ForEach-Object {
    $m = [regex]::Match($_, '^\s*SSID\s*:\s*(.+)$')
    if ($m.Success) {
        $m.Groups[1].Value.Trim()
    }
} |
Select-Object -First 1

Write-Output "Current SSID: $currentSSID"
if ($currentSSID -ne $SSID) {
    $password = Get-WifiPassword -Ssid $SSID

    $wlanProfile = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$SSID</name>
    <SSIDConfig>
        <SSID>
            <name>$SSID</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$password</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@

    # The profile carries the passphrase, so remove it as soon as it is imported.
    $temp = "$env:TEMP\$SSID.xml"
    $wlanProfile | Out-File -Encoding ascii $temp
    try {
        netsh wlan add profile filename="$temp"
    }
    finally {
        Remove-Item $temp -Force -ErrorAction SilentlyContinue
        $password = $null
        $wlanProfile = $null
    }
}

$keyPrivate = $keyPath
$keyPublic = "$keyPath.pub"

New-Item -ItemType Directory -Force "$HOME\.ssh" | Out-Null

if (-not (Test-Path $keyPrivate) -or -not (Test-Path $keyPublic)) {
    Write-Output "Generating SSH keypair"

    ssh-keygen -t ed25519 -f $keyPrivate

    if (-not (Test-Path $keyPublic)) {
        throw "Key generation failed: public key missing"
    }
}

$keyData = Get-Content $keyPublic -Raw

if ($currentSSID -eq $SSID) {
    Write-Output "Already connected to the the right network"
    Network-Connection-Attempt -RemoteHostAddress $remoteHostAddress
    Write-Output "Connected successfully."
} else {
    $maxScanAttempts = 30
    $scanAttempt = 0

    while ($scanAttempt -lt $maxScanAttempts) {
        $scanAttempt++

        Write-Output "Looking for $SSID..."
        Force-Network-Refresh

        if ((netsh wlan show networks) -match [regex]::Escape($SSID)) {

            Write-Output "Connecting..."
            netsh wlan connect name="$SSID" | Out-Null
            break
        }

        Start-Sleep 5
    }

    if ($scanAttempt -ge $maxScanAttempts) {
        throw "SSID '$SSID' not found."
    }

    Network-Connection-Attempt -RemoteHostAddress $remoteHostAddress
}

Write-Output "Device reachable, starting SSH"
Write-Output "Attepting to establish ssh connection to remote host"

$remoteCommand = @'
mkdir -p ~/.ssh &&
chmod 700 ~/.ssh &&
touch ~/.ssh/authorized_keys &&
chmod 600 ~/.ssh/authorized_keys &&
cat >> ~/.ssh/authorized_keys
'@

Invoke-SSHWithInput -RemoteTarget $remoteSSHAddress -RemoteCommand $remoteCommand -InputData $keyData -KeyFile $keyPrivate
Write-Output "Key installed"

# Resolve the demo location on the host, then derive every path from it.
$demoDir = Resolve-DemoDir -RemoteTarget $remoteSSHAddress -KeyFile $keyPrivate -Fallback $demoDir
$scriptPath = "$demoDir/run-demo-captioning.sh"
$stopScriptPath = "$demoDir/stop-all-demos.sh"

# Stop whatever is left from a previous session, then start the demo in tmux.
# HOST_IP is pinned to the access point address so WebRTC and the RTSP streams
# are reachable from this laptop.
Write-Output "Stopping any existing demos... (May take a moment)"
$remoteCommand1 = @"
tmux kill-session -t '$tmuxSessionName' 2>/dev/null || true
bash '$stopScriptPath' >/dev/null 2>&1 || true
tmux new-session -d -s '$tmuxSessionName' "HOST_IP=$hostIp '$scriptPath'"
"@

Invoke-SSH -RemoteTarget $remoteSSHAddress -RemoteCommand $remoteCommand1 -KeyFile $keyPrivate

Write-Output "Waiting for the captioning service (first start converts the model, this can take a while)..."
if (-not (Wait-ForDemo -HealthUrl $healthUrl -TimeoutSeconds $readyTimeoutSeconds)) {
    Write-Warning "The demo did not report healthy within $readyTimeoutSeconds s."
    Write-Warning "Check it on the host with: tmux attach -t $tmuxSessionName"
}
else {
    Write-Output "Demo ready"
}

function Open-In-Browser {
    param(
        [string]$Url
    )

    $chromePaths = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "$env:ProgramFiles(x86)\Google\Chrome\Application\chrome.exe",
    "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )

    $chrome = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    Write-Output "Demo status: Ready. Starting..."
    if ($chrome) {
        Write-Output "Detected Chrome browser, launching..."
        Start-Process $chrome @("--start-fullscreen", $Url)
    } else {
        Write-Output "Chrome not detected, using default browser"
        Start-Process $Url
    }
}

Open-In-Browser -Url $url

Invoke-Cleanup -StopScriptPath $stopScriptPath -CurrentSSID $currentSSID -SSID $SSID -RemoteSSHAddress $remoteSSHAddress -Url $url -DemoDir $demoDir -TmuxSessionName $tmuxSessionName -KeyFile $keyPrivate




