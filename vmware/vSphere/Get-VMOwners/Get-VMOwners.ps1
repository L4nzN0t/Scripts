<#
.SYNOPSIS

Get the owners of each VM accordingly to tags

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

In order to script runs, each VM must be assigned with two tags: "Responsavel" and "Equipe"

#>

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
Function ObjectLog($vm, $vmTagEquipe, $vmTagResponsavel) {
    $properties = [ordered] @{
        'VM' = $vm
        'Equipe' = $vmTagEquipe
        'Responsavel' = $vmTagResponsavel
    }
    $object = New-Object -TypeName psobject -Property $properties
    return $object
}

try {
    $all = @()
    $all.Clear()

    vms = Get-VM | Sort-Object Name
    foreach ($vm in $vms)
    {
        $vmTagResponsavel = Get-TagAssignment -Category "Responsavel" -Entity $vm | Select-Object @{Name="TagName";Expression={$_.Tag.Name}}
        $vmTagEquipe = Get-TagAssignment -Category "Equipe" -Entity $vm | Select-Object @{Name="TagName";Expression={$_.Tag.Name}}

        if (!($vmTagResponsavel)) {
            $vmTagResponsavel = " "
        }
        if (!($vmTagEquipe)) 
        {
            $vmTagResponsavel = " "
        }

        $all += ObjectLog $vm $vmTagEquipe.TagName $vmTagResponsavel.TagName

    }
    $all

} catch {
    Write-Error $_
} finally {

}