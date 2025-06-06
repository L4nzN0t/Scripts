
<#
.SYNOPSIS

What the script does

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Description

.PARAMETER Tag

Set the tag name 

.PARAMETER Category

Set the category of the tag 

#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    [Parameter(Mandatory=$true)]
    [string]
    $Tag,

    [Parameter(Mandatory=$true)]
    [string]
    $Category

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
try {
    $CATEGORY = $Category
    $NEW_TAG = $Tag

    $vmsTags = Get-Content  "$WORKSPACE_FOLDER\vms.txt"

    foreach ($vm in $vmsTags)
    {
        New-TagAssignment -Tag $NEW_TAG -Entity $vm
    }

} catch {
    Write-Error $_
} finally {
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