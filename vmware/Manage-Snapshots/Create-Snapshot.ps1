<#
.SYNOPSIS

Create snapshot from list of VMs.

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Create snapshots from a list of VMs in .txt file

.PARAMETER NoAsk

If this parameter is set, the script runs without stop. All answers are marked as yes.

#>
[CmdletBinding()]
param(
    [switch]
    $NoAsk
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
Function Write-VerboseMessage {
    param (
        [string]$Message
    )
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
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