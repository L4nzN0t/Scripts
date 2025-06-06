<#
.SYNOPSIS

Gets the current user who is authenticating to LDAP

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Get the status of the last backup and export to a json file

.PARAMETER Server

vCenter Server

#>

[CmdletBinding()]
param(
    [switch]$Confirm,
    [string]$Server
)

try {
    if (!($Server)) {
        $Server = "<vcenter_server>"
    }
} catch {
    Write-Error $_
}


$allObj = @()
$vCenterServer = $Server
$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
$allObj.Clear()

try {
    # Ensure the VMware PowerCLI module is installed and loaded
    Import-Module VMware.VimAutomation.Core
    Connect-VIServer -Server $vCenterServer -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
    exit
}


try {
    $vms = Get-VM *
    foreach ($vm in $vms)  
    { 
        $bkpStatus = $vm.CustomFields | Where-Object { $_.Key -eq 'LastBackupStatus-com.dellemc.avamar' } 
        $tempObj = [pscustomobject]@{
            Name = $vm.Name
            Active = ''
            LastStatus = ''
            LastDate = ''
        }
        if ($bkpStatus.Value -ne "")
        {
            $tempObj.Active = "Yes"
            $tempObj.LastStatus = ($bkpStatus.Value -split ":\ss*")[0]
            $tempObj.LastDate = ($bkpStatus.Value -split ":\ss*")[1]
        } else {
            $tempObj.Active = "No"
        }
        $allObj += $tempObj
    }
    # $allObj | Sort-Object Name | Format-Table
    $allObj
} catch {
    $_
} finally {

}
