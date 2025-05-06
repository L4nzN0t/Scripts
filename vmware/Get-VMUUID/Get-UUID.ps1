[CmdletBinding()]
param(
    [switch]$Confirm
)
Clear-Host
# Ensure the VMware PowerCLI module is installed and loaded
Import-Module VMware.VimAutomation.Core

$vCenterServer = "<vcenter_server>"
$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
$allObj.Clear()

try {
    Connect-VIServer -Server $vCenterServer -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
    exit
}


$vms = Get-vm -Name *
$allObj = @()
foreach ($vm in $vms) {
    $biosUUID = $vm.ExtensionData.Config.Uuid
    $vcUUID = $vm.ExtensionData.Config.InstanceUuid
    $hostVM = $vm.VMHost.Name

    $objtemp = [pscustomobject]@{
        VM = $vm.Name
        BIOS_UUID  = $biosUUID
        VC_UUID = $vcUUID
        HOST = $hostVM
    }
    $allObj += $objtemp
}

## BIOS UUID -> Is related to virtual machine hardware. 
## Only visible to virtual machine os.
## 
## VC UUID -> Identify the virtual machine inside vCenter. 
## Used to manage and track virtual machine on vCenter.
## It`s not visible to the os


$allObj | Format-Table
