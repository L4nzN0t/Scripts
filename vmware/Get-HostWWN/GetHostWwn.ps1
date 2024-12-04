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
        $hbas = Get-VMHostHba -VMHost $h | Where-Object {$_.Type -eq "FibreChannel"} 
        $objects = @()
        foreach ($hba in $hbas)
        {
            $nwwn = $hba.NodeWorldWideName.ToString("X")
            $pwwn = $hba.PortWorldWideName.ToString("X")
            
            $object = [pscustomobject]@{
                Host = $h.Name
                Type = $hba.Type
                Device = $hba.Device
                Model = $hba.Model
                Speed = $hba.Speed
                NodeWorldWideName = $nwwn
                PortWorldWideName = $pwwn
                Status = $hba.Status
            }
            $objects += $object
        }
        $evry += $objects
    }
    $evry | Sort-Object Host | Format-Table
    $evry | Export-Csv -Path $WORKSPACE_FOLDER\vm_wwn_host.csv -Encoding utf8 -NoHeader -NoClobber
} catch {

}
