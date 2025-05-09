<#
.SYNOPSIS

Create specific role in vCenters.

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Create a specific permission according to the roles set in the .txt file.

.PARAMETER RoleName

Role name that will be created

#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory=$true)]
        [string]
        $RoleName
)

try {
    Clear-Host
    # Ensure the VMware PowerCLI module is installed and loaded
    Import-Module VMware.VimAutomation.Core

    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    # Connect to each vCenter
    #$vCenters = "<vcenter_server01>,<vcenter_server02>,<vcenter_server03>" -split ","
    $vCenters = "bhevmger01.fazenda.mg.gov.br,bhevcprd01.fazenda.mg.gov.br,bhevcger01.fazenda.mg.gov.br" -split ","
    $WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
    $WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName

    foreach ($vCenter in $vCenters)
    {
        try {
            Connect-VIServer -Server $vCenter -User "administrator@vsphere.local" -Password "6637N@rS6691" -ErrorAction Stop
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
try {
    $cvRolePermFile = "$WORKSPACE_FOLDER\permissions.txt"
    $cvRole = $RoleName
    $cvRoleIds = @()

    Write-Host ""
    Write-Verbose "Check if correct permissions are set in $cvRolePermFile"
    Write-Host ""
    
    Get-Content $cvRolePermFile | Foreach-Object{
        $cvRoleIds += $_
    }

    foreach ($vCenter in $vCenters)
    {
        New-VIRole -Name $cvRole -Privilege (Get-VIPrivilege -Server $vCenter -id $cvRoleIds) -Server $vCenter
        Set-VIRole -Role $cvRole -AddPrivilege (Get-VIPrivilege -Server $vCenter -id $cvRoleIds) -Server $vCenter
    }
 
} 
catch {
    Write-Error $_
} 
finally {
    foreach ($vCenter in $vCenters)
    {
        try {
            # Disconnect from vCenter Server
            Write-Host ""
            Write-Verbose "Disconnecting from vCenter Server..."
            Disconnect-VIServer -Server $vCenter -Confirm:$false
            Write-Verbose "Successfully disconnected from vCenter Server."
        } catch {
            Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
            # exit
        }
    }
}