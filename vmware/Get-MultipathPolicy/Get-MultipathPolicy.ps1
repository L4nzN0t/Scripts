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
        $luns = Get-ScsiLun -VMHost $h 
        $objects = @()
        foreach($lun in $luns)
        {
            $scsiLunPath = Get-ScsiLunPath -ScsiLun $lun | Where-Object { $_.ScsiCanonicalName -eq $lun.CanonicalName  }
            $datastore = Get-Datastore | Where-Object { $_.ExtensionData.Info.vmfs.Extent | Where-Object { $_.DiskName -eq $lun.CanonicalName }}
            foreach ($scsiLun in $scsiLunPath)
            {
                $object = [pscustomobject]@{
                    Host = $h
                    Name = $datastore
                    Path = $scsiLun.LunPath
                    CanonicalName = $lun.CanonicalName
                    LunType = $lun.LunType
                    MultipathPolicy = $lun.MultipathPolicy
                    State = $scsiLun.State
                    SanID = $scsiLun.SanId
                    IsLocal = $lun.IsLocal
                    IsSSD = $lun.IsSsd
                    Capacity = $lun.CapacityGB
                }
            }
            $objects += $object
        }
        $evry += $objects
    }
    $evry | Sort-Object Host | Format-Table
    
} catch {
    Write-Error $_
}


