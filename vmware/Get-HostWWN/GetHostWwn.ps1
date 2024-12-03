[CmdletBinding()]
param(
    [switch]$Confirm
)
Clear-Host
# Ensure the VMware PowerCLI module is installed and loaded
Import-Module VMware.VimAutomation.Core

$vCenterServer = "<vcenter_server>"
$cluster = "<cluster_name>"
$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
$evry.Clear()

try {
    Connect-VIServer -Server $vCenterServer -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
    exit
}

try {
    $hosts = Get-VMHost | Where-Object {$_.Parent -like $cluster}
    foreach ($h in $hosts) {
        $hbas = Get-VMHostHba -VMHost $h
        
        $evry += $hbas | Where-Object {$_.Type -eq "FibreChannel"} |Select-Object VMHost,Type,Device,Model,Speed,NodeWorldWideName,PortWorldWideName,Status | Sort VMHost | Format-Table 
        
    }
    $evry | Format-Table 
    $evry | Out-File $WORKSPACE_FOLDER\vm_wwn_host.txt -Encoding utf8
} catch {

}
