# Define the required version
$requiredVersion = "0.29.2"
$minimalVersion = [version]"0.29.1"
$netbird_domain = "remote.qwilt.com"
$netbird_device_port = "33073"
$netbird_web_port = "443"
$netbird_ip = "35.246.201.207"


# Updating host file for remote.qwilt.com
$hostsPath = "C:\Windows\System32\drivers\etc\hosts"
# Read the hosts file
$hostsContent = Get-Content $hostsPath
# Remove existing lines containing remote.qwilt.com
$hostsContent = $hostsContent | Where-Object { $_ -notmatch "$netbird_domain" }
# Add the new entry
$newEntry = "$netbird_ip $netbird_domain"
$hostsContent += $newEntry
# Write back to the hosts file
sleep 2
$hostsContent | Set-Content $hostsPath -Force
Write-Output "Updated hosts file with: $newEntry"

# Disable ipv6
Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6

# Define the installation function
function InstallNetbird {
    # Add installation logic here
    echo Installing/Upgrading netbird
    tskill netbird-ui > $null 2>&1
    Stop-Service -Name "NetBird" > $null 2>&1
    rm C:\ProgramData\Netbird\config.json  > $null 2>&1
    # Get the ProductCode of Netbird
    $ProductCode = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -eq "Netbird" }).PSChildName

    if ($ProductCode) {
        # Run the uninstaller
        Write-Host "Uninstalling Netbird..."
        Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $ProductCode /qn" -Wait > $null 2>&1
        Write-Host "Netbird has been uninstalled."
    } else {
        Write-Host "Netbird is not installed on this system."
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    (New-Object System.Net.WebClient).DownloadFile("https://github.com/netbirdio/netbird/releases/download/v${requiredVersion}/netbird_installer_${requiredVersion}_windows_amd64.msi", "$env:TEMP/Netbird.msi")

    cd $env:TEMP
    Start-Process msiexec.exe -NoNewWindow -ArgumentList "-i Netbird.msi /quiet"
    Start-Sleep -Seconds 20
    Stop-Service -Name "NetBird" > $null 2>&1
    sleep 3
    tskill netbird-ui > $null 2>&1
    Start-Service -Name "NetBird" > $null 2>&1
    sleep 5

}

function configure_netbird_show_icon {
    #create flip icon script
    @'
    [CmdletBinding(DefaultParameterSetName='Flip')]
param (
    [Parameter(Mandatory=$false, ParameterSetName='Unhide')]
    [switch]$Unhide,

    [Parameter(Mandatory=$false, ParameterSetName='Hide')]
    [switch]$Hide,

    [Parameter(Mandatory=$false, ParameterSetName='Flip')]
    [switch]$Flip,

    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$args
)

function W11_TrayNotify {
    param (
        [Parameter(Mandatory)]
        [string[]] $AppList,

        [Parameter(Mandatory)]
        [ValidateSet('Unhide','Hide','Flip')]
        $Action
    )

    foreach ($GUID in (Get-ChildItem -Path 'HKCU:\Control Panel\NotifyIconSettings' -Name)) {
        $ChildPath = "HKCU:\Control Panel\NotifyIconSettings\$($GUID)"
        $Exec = (Get-ItemProperty -Path $ChildPath -Name ExecutablePath -ErrorAction SilentlyContinue).ExecutablePath

        foreach ($App in $AppList) {
            if ($Exec -match $App) {
                switch ($Action) {
                    'Unhide' { $Promoted = 1 }
                    'Hide'  { $Promoted = 0 }
                    'Flip' { $Promoted = (Get-ItemProperty -Path $ChildPath -Name IsPromoted).IsPromoted -bxor 1 }
                }
                Set-ItemProperty -Path $ChildPath -Name IsPromoted -Value $Promoted
            }
        }
    }
}

W11_TrayNotify -AppList @("netbird-ui") -Action Unhide
'@ | Set-Content -Path "C:\ProgramData\Netbird\show_netbird_icon.ps1" -Encoding UTF8

    #showing all icons in the traybar
    Set-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer EnableAutoTray 0
    # Get the currently logged-in user session
    $currentUserSession = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    # set to run after computer resumes from sleep
    # Define variables
}
function configure_netbird {

    # Set to run after computer resumes from sleep
    # Define variables
    $taskName = "Run netbird on Resume"
    $programPath = "C:\Program Files\Netbird\netbird-ui.exe"

    # Create trigger for system resume event using event subscription
    $triggerXml = @"
    <QueryList>
      <Query Id='0' Path='System'>
        <Select Path='System'>*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and (EventID=1)]]</Select>
      </Query>
    </QueryList>
"@

    # Create the action to start the program
    $action = New-ScheduledTaskAction -Execute $programPath

    # Register the scheduled task
    Register-ScheduledTask -TaskName $taskName -Trigger (New-ScheduledTaskTrigger -AtStartup -RandomDelay (New-TimeSpan -Seconds 30)) -Action $action -Description "Runs $programPath on system resume" -User "SYSTEM" -RunLevel Highest -Force

    echo Updating config file
    # Define the new values
    $newManagementURL = "${netbird_domain}:${netbird_device_port}"
    $newWebURL = "${netbird_domain}:${netbird_web_port}"

    # Path to the config.json file
    $configFilePath = "C:\ProgramData\Netbird\config.json"

    # Read the contents of the file
    $configContent = Get-Content -Path $configFilePath -Raw
    # Replace the strings in the configuration file
    $newConfigContent = $configContent -replace 'api.wiretrustee.com:443', "${netbird_domain}:${netbird_device_port}" -replace 'app.netbird.io:443', "${netbird_domain}:${netbird_web_port}" -replace 'api.netbird.io:443', "${netbird_domain}:${netbird_device_port}"

    $newConfigContent | Set-Content -Path $configFilePath
    Start-Service -Name "NetBird" > $null 2>&1
    # Get the currently logged-in user session
    $currentUserSession = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

    # Extract the username from the session information
    $username = $currentUserSession -replace ".*\\"

    # Check if the user is currently logged in
    if ($username) {
        Write-Host "User $username is currently logged in."

        # Start the software as the logged-in user
        $softwarePath = "C:\Program Files\Netbird\netbird-ui.exe"
        sleep 2
        Start-Process -FilePath $softwarePath -Verb RunAs $username -WindowStyle Minimized > $null 2>&1
        Write-Host "Software started for user $username on their desktop."
    } else {
        Write-Host "No user is currently logged in."
    }

}

# Check if Netbird is installed
if (-not (Get-Command netbird -ErrorAction SilentlyContinue)) {
    Write-Host "Netbird is not installed, installing now..."
    
    # Call the installation function
    InstallNetbird
    sleep 10
    configure_netbird_show_icon
    sleep 5
    configure_netbird


} else {
    configure_netbird_show_icon # updating start_script file
    # Capture the output of the netbird status command
    $netbirdStatus = " "
# Function to check Netbird status
    function Get-NetbirdStatus {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "netbird"
    $processInfo.Arguments = "status -d"
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo
    $process.Start() | Out-Null

    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $netbirdStatus = $standardOutput + $standardError
    return $netbirdStatus
}
    $netbirdVersionString = Invoke-Expression "netbird version"
    $netbirdVersion = [version]"$netbirdVersionString"

        # Check if the installed version is below the minimal version
    if ($netbirdVersion -lt $minimalVersion) {
        Write-Host "Netbird version is below the minimal version, stopping service and notifying user."
        # Send notification to all logged-in users
        msg * "Netbird version is too old. Forcing Upgrade of Netbird. Please wait."
        $popup_subject = "Upgrading Netbird"
        $popup_message = "Netbird version is too old. Forcing Upgrade of Netbird. Please wait."
        popup # running function to send popup


        & 'C:\Program Files\Netbird\netbird.exe' down
        & 'C:\Program Files\Netbird\netbird.exe' service stop
        # Run the installation and configuration functions
        InstallNetbird
        Start-Sleep -Seconds 5
        & 'C:\Program Files\Netbird\netbird.exe' service restart
        configure_netbird_show_icon
        sleep 5
        configure_netbird
        }
    # Check if the output contains "Management: Disconnected" or "YOUR_MANAGEMENT_URL"

    # Get Netbird status
    $netbirdStatus = Get-NetbirdStatus

    if ($netbirdStatus -match "context deadline exceeded") {
        Write-Host "Netbird service is shutdown or config Damaged - Regenerating"
        Stop-Service -Name "NetBird" > $null 2>&1
        rm C:\ProgramData\Netbird\config.json
        Start-Service -Name "NetBird" > $null 2>&1
        sleep 5
        configure_netbird_show_icon
        sleep 5
        configure_netbird
        sleep 5
        & 'C:\Program Files\Netbird\netbird.exe' service restart 
    }

    # Check if the file contains the string 'netbird.io'
    if (Test-Path C:\ProgramData\Netbird\config.json) {
        $configContent = Get-Content C:\ProgramData\Netbird\config.json -Raw
        if ($configContent -match "netbird.io") {
            Stop-Service -Name "NetBird" > $null 2>&1
            rm C:\ProgramData\Netbird\config.json
            Start-Service -Name "NetBird" > $null 2>&1
            sleep 5
            configure_netbird_show_icon
            sleep 5
            configure_netbird
            sleep 5
            & 'C:\Program Files\Netbird\netbird.exe' service restart 
        }
    }

    if ($netbirdStatus -match "Management: Disconnected" -or $netbirdStatus -match "YOUR_MANAGEMENT_URL") {
        Write-Host "Netbird is installed but not connected, verifying version and connecting..."
           # Check if the output matches the required version
        if ($netbirdVersion -eq $requiredVersion) {
            Write-Host "Netbird version is $requiredVersion, Ignoring"
          } else {
            Write-Host "Netbird Current Version is:" $netbirdVersion
            Write-Host "Netbird version is not $requiredVersion - Upgrading/Downgrading"
            msg * "Netbird version is not the recommended version - upgrading - Please wait."

            # Call the installation function
            Stop-Service -Name "NetBird" > $null 2>&1
            rm C:\ProgramData\Netbird\config.json  > $null 2>&1
            InstallNetbird
            sleep 5
            configure_netbird_show_icon
            sleep 5
            configure_netbird
            sleep 5
            & 'C:\Program Files\Netbird\netbird.exe' service restart
        }
        
    } else {
        Write-Host "Netbird is connected at the moment, ignoring"

    }
    # show netbird-ui icon
    C:\ProgramData\Netbird\show_netbird_icon.ps1  > $null 2>&1

}
echo "Host file:"
Get-Content C:\Windows\System32\drivers\etc\hosts |  Select-String "remote.qwilt.com"

echo "Config File:"

Get-Content C:\ProgramData\Netbird\config.json |  Select-String "remote.qwilt.com"
