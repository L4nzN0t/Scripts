<#
.SYNOPSIS

Get the HBAs from each host

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

This script connect to each vCenter into the network and get the information about each online HBA that is used to connect to a fiber channel datastore.

#>
Clear-Host

try {
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

    $hbasInfo = Get-VMHost | Get-VMHostHba -Type FibreChannel | Where-Object Status -eq "online" | Select-Object VMHost, Device, Status, Speed, @{Name="WWN";Expression={"{0:X}:{1:X}" -f $_.ExtensionData.NodeWorldWideName, $_.ExtensionData.PortWorldWideName}}
    $hbasInfo | ConvertTo-Json -Depth 1 | Out-File -Force -Encoding utf8 -FilePath $FilePath

} catch {
    Write-error $_
}