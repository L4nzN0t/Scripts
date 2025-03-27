[CmdletBinding()]
param(
    [switch]$Confirm
)
Clear-Host
# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$vCenterServer = "BHEVMGER01.fazenda.mg"
$FilePath = "\\bherunner01.fazenda.mg\E$\WEB_SERVER\export\vmware_owners.json"
$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
$all = @()

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
    Connect-VIServer -Server $vCenterServer -ErrorAction Stop
} catch {
    Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
    exit
}



try {
    $vms = Get-VM | Sort-Object Name
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
    $all | ConvertTo-Json -Depth 1 | Out-File -Force -Encoding utf8 -FilePath $FilePath
} catch {
    Write-error $_$vmTag
}