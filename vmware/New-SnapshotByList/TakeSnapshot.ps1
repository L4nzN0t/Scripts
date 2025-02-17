[CmdletBinding()]
param(
    [switch]$NoAsk
)

$vCenterServer = "<vcenter_server>"
$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
$serverListFile = "$WORKSPACE_FOLDER\vms.txt"

Clear-Host
# Ensure the VMware PowerCLI module is installed and loaded
Import-Module VMware.VimAutomation.Core

# Function to display verbose messages
function Write-VerboseMessage {
    param (
        [string]$Message
    )
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

# Connect to the vCenter Server
Write-VerboseMessage "Connecting to vCenter Server: $vCenterServer"

try {
    Connect-VIServer -Server $vCenterServer -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
    exit
}

Write-Host ""
Write-VerboseMessage "Successfully connected to vCenter Server."

# Read the text file with the server names
if (-Not (Test-Path $serverListFile)) {
    Write-Host "[ERROR] Server list file not found: $serverListFile" -ForegroundColor Red
    exit
}

$serverNames = Get-Content -Path $serverListFile

# Get snap Information
Write-Host ""
Write-VerboseMessage "Getting VM information"
$vms = @()
foreach ($serverName in $serverNames)
{
    try {
        Write-VerboseMessage "Processing VM - $serverName"
        $vms += Get-vm -Name $serverName
    }
    catch {
        Write-Host "[ERROR] - Failed to get VM info" -ForegroundColor Red
        Write-Host "[ERROR] - $($Error[0])" -ForegroundColor Red
        exit
    }
}
# $vms = $snapshots | Select-Object -Unique
# $snapshots | Format-Table VM, Created, Name, ParentSnapshot, SizeGB, Quiesced, PowerState, IsCurrent

foreach ($vm in $vms) {
    
    try {
        $serverName = $vm.Name

        # Check for old snapshots (older than 3 days)
        $snapshots = Get-Snapshot -VM $vm

        if ($snapshots)
        {
            Write-Host "[WARNING] Old snapshots found for $($serverName):" -ForegroundColor DarkYellow
            
            # $snapshots | Format-Table VM, Name,Created, PowerState, SizeGB, Description

            if ($NoAsk)
            {
                Write-Host "[$serverName] Removing old snapshots" -ForegroundColor Cyan
                $snapshots | ForEach-Object { Remove-Snapshot -Snapshot $_ -Confirm:$false -RunAsync:$false } 
                Write-Host "[$serverName] Old snapshots removed successfully" -ForegroundColor Cyan
            }
            else 
            {
                $removeOldSnapshots = Read-Host "Do you want to remove old snapshots for $serverName? (Y/N)"
                Write-Host ""
                switch($removeOldSnapshots.ToUpper())
                {
                    "Y" {
                        Write-Host "[$serverName] Removing old snapshots" -ForegroundColor Cyan
                        $snapshots | ForEach-Object { Remove-Snapshot -Snapshot $_ -Confirm:$false -RunAsync:$false } 
                        Write-Host "[$serverName] Old snapshots removed successfully" -ForegroundColor Cyan
                    }
                    Default {
                        continue
                    }
                }
            }            
        } else {
            Write-Host "[$serverName] No old snapshots found for" -ForegroundColor Cyan
        }

        # Create a new snapshot
        $snapshotName = "Snapshot-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $description = "Automated snapshot created on $(Get-Date)"

        Write-Host "[$serverName] Creating new snapshot" -ForegroundColor Cyan
        $snapshot = $vm | New-Snapshot -Name $snapshotName -Description $description -Memory -Quiesce -ErrorAction Stop
        Write-Host "[$serverName] Snapshot created - Name: $snapshotName - Time: $($snapshot.Created)" -ForegroundColor Cyan
    } 
    catch
    {
        Write-Host "[ERROR] Error processing server $($serverName): $_" -ForegroundColor Red
    }
}
$vms | Get-Snapshot | Select-Object -Unique | Format-Table VM, Name,Created, PowerState, SizeGB, Description

# Disconnect from vCenter Server
Write-Host ""
Write-VerboseMessage "Disconnecting from vCenter Server..."
Disconnect-VIServer -Server $vCenterServer -Confirm:$false
Write-VerboseMessage "Successfully disconnected from vCenter Server."
