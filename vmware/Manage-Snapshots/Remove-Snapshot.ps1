<#
.SYNOPSIS

Remove the snapshot from list of VMs.

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Remove snapshots from a list of VMs in .txt file

.PARAMETER NoAsk

If this parameter is set, the script runs without stop. All answers are marked as yes.

#>
[CmdletBinding()]
param(
    [switch]
    $Confirm
)

try {
    Clear-Host
    # Ensure the VMware PowerCLI module is installed and loaded
    Import-Module VMware.VimAutomation.Core

    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    # Connect to each vCenter
    $vCenters = "<vcenter_server01>,<vcenter_server02>,<vcenter_server03>" -split ","
    $WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
    $WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
    Write-Host ""
    Write-VerboseMessage "Successfully connected to vCenter Server."

    foreach ($vCenter in $vCenters)
    {
        try {
            Connect-VIServer -Server $vCenter -User "user@vsphere.local" -Password "pass" -ErrorAction Stop
        } catch {
            Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
            # exit
        }
    }
}
catch
{
    Write-Error $_
}

# SCRIPT EXECUTION

# Function to display verbose messages
function Write-VerboseMessage {
    param (
        [string]$Message
    )
    Write-Host "[INFO] $Message" -ForegroundColor DarkCyan
}

try {
    $serverListFile = "$WORKSPACE_FOLDER\vms.txt"

    # Read the text file with the server names
    if (-Not (Test-Path $serverListFile)) {
        Write-Host "[ERROR] Server list file not found: $serverListFile" -ForegroundColor Red
        exit
    }

    $serverNames = Get-Content -Path $serverListFile

    # Get snap Information
    Write-Host ""
    Write-VerboseMessage "Getting VM information"
    $snapshots = @()
    $vms = @()
    foreach ($serverName in $serverNames)
    {
        try {
            Write-VerboseMessage "Processing VM - $serverName"
            $vms += Get-vm -Name $serverName
            $snapshots += $vms| Get-Snapshot
        }
        catch {
            Write-Host "[ERROR] - Failed to get VM info" -ForegroundColor Red
            Write-Host "[ERROR] - $($Error[0])" -ForegroundColor Red
            exit
        }
    }
    $snapshots = $snapshots | Select-Object -Unique
    $snapshots | Format-Table VM, Created, Name, ParentSnapshot, SizeGB, Quiesced, PowerState, IsCurrent

    if ($snapshots)
    {
        foreach ($snap in $snapshots)
        {
            try {
                if(!($NoAsk))
                {
                    $removeOldSnapshots = Read-Host "Do you want to remove old snapshots for $($snap.VM)? (Y/N)"
                    Write-Host ""
                    switch($removeOldSnapshots.ToUpper())
                    {
                        "Y" {
                            Write-Host "[$($snap.VM)] - Removing old snapshots" -ForegroundColor DarkCyan
                            $snap | Remove-Snapshot -Confirm:$false -RunAsync:$false
                            Write-Host "[$($snap.VM)] - Snapshot removed" -ForegroundColor DarkCyan
                            Write-Host "--"
                        }
                        Default {
                            continue
                        }
                    }
                } else {
                    Write-Host "[$($snap.VM)] - Removing old snapshots" -ForegroundColor DarkCyan
                    $snap | Remove-Snapshot -Confirm:$false -RunAsync:$false | Out-null
                    Write-Host "[$($snap.VM)] - Snapshot removed" -ForegroundColor DarkCyan
                }
            } 
            catch
            {
                Write-Host "[ERROR] Error processing server $($serverName): $_" -ForegroundColor Red
            }
        } 
        $vms | Get-Snapshot | Format-Table VM, Created, Name, ParentSnapshot, SizeGB, Quiesced, PowerState, IsCurrent
    } else {
        Write-VerboseMessage "No old snapshots found for $vms."
    }
} 
catch {
    Write-Error $_
}
finally {
    # Disconnect from vCenter Server
    Write-Host ""
    Write-VerboseMessage "Disconnecting from vCenter Server..."
    Disconnect-VIServer -Server $vCenterServer -Confirm:$false
    Write-VerboseMessage "Successfully disconnected from vCenter Server."
}