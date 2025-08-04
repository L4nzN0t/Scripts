<#
.SYNOPSIS

What the script does

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Description

.PARAMETER VCList
List of vCenters to connect to.

.PARAMETER Username
Username to log in vCenter

.PARAMETER Password
Password to log in vCenter

.EXAMPLE
C:/PS> ./template-script.ps1 -Username teste@vsphere.local -Password Password@123 -VCList vclist.txt -ExportType ALL

#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    [Parameter(Mandatory=$true)]
    [string]
    $VCList,

    [Parameter(Mandatory=$true)]
    [string]
    $Username,

    [Parameter(Mandatory=$true)]
    [securestring]
    $Password,

    [ValidateSet("CSV", "HTML", "ALL")]
    [Parameter(Mandatory)]
    [string]
    $ExportType = 'ALL'

)

$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$global:WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName

class Auth {
    $credential
    Auth([string]$_user, [securestring]$_password) {
        try {
            $this.credential = New-Object System.Management.Automation.PSCredential($_user,$_password)
        }
        catch {
            Write-Host "[ERROR] Failed to create credential" -ForegroundColor Red
            Write-Error $_
            exit 1
        }
    }
}

class Log {
    [string]$LogPath

    Log ([string]$logName) 
    {
        $this.LogPath = "$global:WORKSPACE_FOLDER\$logName"
        if ((Test-Path $this.LogPath)) {
            Write-Host "`n" | Out-File $this.LogPath -Append -Encoding UTF8
        } else {
            New-Item -ItemType File -Path $this.LogPath
            Write-Host ""
        }
    }

    [void] LogAppend($logType, $task, $server, $user, $description) {

        $properties = [ordered] @{
            'Date' = (Get-date -Format 'MM-dd-yyyy-hh:mm:ss' -AsUTC).ToString()
            'Type' = $logType
            'Task' = $task
            'Server' = $server
            'User' = $user
            'Description' = $description
        }
        $objectLog = New-Object -TypeName psobject -Property $properties

        $stringLog = $objectLog.Date + " UTC" + " [" + $objectLog.Type + "] " + $objectLog.Server + " " + $objectLog.User + " - " + $objectLog.Task + " - " + $objectLog.Description
        $stringLog | Out-File -FilePath $this.LogPath -Encoding utf8 -Append
    }
}
    
try {
    Clear-Host
    # Ensure the VMware PowerCLI module is installed and loaded
    Import-Module VMware.VimAutomation.Core

    # Instance Log class
    $log = "log-" + (Get-date -Format 'yyyyddMM hhmmss' -AsUTC).ToString() + ".log"
    $clientLog = [Log]::new($log)

    # Instance Auth class
    $auth = [Auth]::new($Username,$Password)

    # Test vCenters list is ok
    if((Test-Path $VCList)) 
    {
        $vCenters = (Get-Content -Path "$VCList")
        $clientLog.LogAppend("INFO", "LOAD VCENTER LIST", "LOCAL", $global:user, "Found $($vCenters.Length) servers")
    }
    elseif((Test-Path "$global:WORKSPACE_FOLDER\$VCList")) {
        $vCenters = (Get-Content -Path "$global:WORKSPACE_FOLDER\$VCList")
        $clientLog.LogAppend("INFO", "LOAD VCENTER LIST", "LOCAL", $global:user, "Found $($vCenters.Length) servers")
    }
    else {
        $vCenters = (Get-Content -Path "$global:WORKSPACE_FOLDER\$VCList")
        $clientLog.LogAppend("ERROR", "FAILED TO VALIDATE VCENTER LIST", "LOCAL", $global:user, "Review parameter -VCList")
        Write-Host "[ERROR] SCRIPT FAILED TO VALIDATE VCENTER LIST" -ForegroundColor Red
        exit 1
    }
    
    Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
    $clientLog.LogAppend("INFO", "Set-PowerCLIConfiguration", "LOCAL", $global:user, "Set UserParticipateInCEIP to False")

    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    $clientLog.LogAppend("INFO", "Set-PowerCLIConfiguration", "LOCAL", $global:user, "Set InvalidCertificateActions to Ignore")

    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null # Still working 
    $clientLog.LogAppend("INFO", "Set-PowerCLIConfiguration", "LOCAL", $global:user, "Set DefaultVIServerMode to Multiple")
        
    # Connect to each vCenter
    Write-Host "[INFO] CONNECTING TO VCENTER SERVERS"
    foreach ($vCenter in $vCenters)
    {
        try {
            Connect-VIServer -Server $vCenter -Credential $auth.credential -Protocol HTTPS -ErrorAction Stop | Out-Null
            $clientLog.LogAppend("INFO", "CONNECTED TO VCENTER", $vCenter.ToString(), $global:user, "Success authentication")
            Write-Host "[SUCCESS] CONNECTED TO $($vcenter.ToString())" -ForegroundColor Green
        } catch {
            $clientLog.LogAppend("ERROR", "CONNECTION FAIL", $vCenter.ToString(), $global:user, "$_")
            $reason = ($_.Exception.Message -split 'Connect-VIServer').trim()[1]
            Write-Host "[ERROR] DISCONNECTED FROM $($vcenter.ToString()): $reason" -ForegroundColor Red
        }
    }

    $clientLog.LogAppend("INFO", "ALL VCENTER CONNECTIONS", "LOCAL", $global:user, "$($global:sDefautVIServers.count) of $($vcenters.count) connected servers")
    Write-Host "[INFO] CONNECTED IN $($global:DefaultVIServers.count) OF $($vcenters.count) VCENTERS"
}
catch
{
    $clientLog.LogAppend("ERROR", "EXECUTION FAIL","LOCAL", $global:user, "$_")
    $reason = ($_.Exception.Message -split 'Connect-VIServer').trim()[1]
    Write-Host "[ERROR] SCRIPT EXECUTION FAILED: $reasons" -ForegroundColor Red
    exit 1
}


#################################################################################################
##################################### SCRIPT EXECUTION ##########################################
Function ExportTo {
    param(
        [array]$all_data
    )

    if ($ExportType -eq "CSV")
    {
        $all_data | Sort-Object vCenter | Export-Csv -LiteralPath "storagepolicy-report.csv" -Force -Confirm:$false
        Write-Host "Report saved to: storagepolicy-report.csv"
    }
    elseif ($ExportType -eq "HTML") 
    {
        $all_data | Sort-Object vCenter | New-PrettyHTMLReport -Title "Storage Policy Report" -Theme "Classic" -FilePath "storagepolicy-report.html"
    }
    elseif ($ExportType -eq "ALL")
    {
        $all_data | Sort-Object vCenter | New-PrettyHTMLReport -Title "Storage Policy Report" -Theme "Classic" -FilePath "storagepolicy-report.html"
        $all_data | Sort-Object vCenter | Export-Csv -LiteralPath "storagepolicy-report.csv" -Force -Confirm:$false
        Write-Host "[SUCCESS] Report saved to: storagepolicy-report.csv" -ForegroundColor Green
    }
}

Function New-PrettyHTMLReport {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Object[]]$Data,
        
        [Parameter(Mandatory)]
        [string]$Title,
        
        [string]$FilePath = "report.html",
        
        [string]$Theme = "Modern" # Modern, Classic, Dark
    )
    
    begin {
        $allData = @()
    }
    
    process {
        $allData += $Data
    }
    
    end {
        $themes = @{
        Modern = @"
<style>
    body { font-family: 'Segoe UI', sans-serif; background: #f8f9fa; margin: 0; padding: 20px; }
    .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; box-shadow: 0 5px 15px rgba(0,0,0,0.1); overflow: hidden; }
    .header { background: linear-gradient(135deg, #667eea, #764ba2); color: white; padding: 30px; text-align: center; }
    h1 { margin: 0; font-size: 2rem; }
    table { width: 100%; border-collapse: collapse; }
    th { background: #495057; color: white; padding: 15px; text-align: left; }
    td { padding: 12px 15px; border-bottom: 1px solid #dee2e6; }
    tr:nth-child(even) { background: #f8f9fa; }
    tr:hover { background: #e9ecef; }
</style>
"@
        Classic = @"
<style>
    body { font-family: Georgia, serif; background: #fff; margin: 20px; }
    h1 { color: #2c3e50; border-bottom: 2px solid #3498db; padding-bottom: 10px; }
    table { width: 100%; border: 1px solid #bdc3c7; border-collapse: collapse; margin: 20px 0; }
    th { background: #34495e; color: white; padding: 10px; border: 1px solid #bdc3c7; }
    td { padding: 8px; border: 1px solid #bdc3c7; }
    tr:nth-child(even) { background: #ecf0f1; }
</style>
"@
        Dark = @"
<style>
    body { font-family: 'Consolas', monospace; background: #1a1a1a; color: #e0e0e0; margin: 0; padding: 20px; }
    .container { background: #2d2d2d; border-radius: 8px; padding: 20px; box-shadow: 0 4px 8px rgba(0,0,0,0.3); }
    h1 { color: #00ff88; text-align: center; margin-bottom: 30px; }
    table { width: 100%; border-collapse: collapse; background: #333; }
    th { background: #444; color: #00ff88; padding: 12px; border: 1px solid #555; }
    td { padding: 10px; border: 1px solid #555; }
    tr:hover { background: #404040; }
</style>
"@
    }
        
        $css = $themes[$Theme]
        $preContent = "<div class='container'><h1>$Title</h1><p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>"
        $postContent = "</div>"
        
        $html = $allData | ConvertTo-HTML -Title $Title -Head $css -PreContent $preContent -PostContent $postContent
        $html | Out-File -FilePath $FilePath -Encoding UTF8
        
        Write-Host "[SUCCESS] Report saved to: $FilePath" -ForegroundColor Green
    }
}

Function GetVsanPolicySummary {
param(
    $policies
)
$all = @()
foreach ($vsanPolicy in $policies) {
    
    $tempObj = [pscustomobject] @{
        VCenter = ($vsanPolicy.Uid -split "@").Split(":")[1]
        Name = $vsanPolicy.Name
        Description = $vsanPolicy.Description
        SiteDisasterTolerance = ''
        StoragePolicy = ''
        FTT = ''
        VMCount = '0'
    }

    if ($null -ne ($vsanPolicy.AnyOfRuleSets.AllOfRules | Where-Object { $_.Capability -like "VSAN.replicaPreference" }))  # IT MEANS THAT THE VSAN IS WORKING AS STRECHED CLUSTER
    {
        $tempObj.SiteDisasterTolerance = 'Site mirroring - streched cluster'
        $tempObj.StoragePolicy = ($vsanPolicy.AnyOfRuleSets.AllOfRules | Where-Object { $_.Capability -like "VSAN.replicaPreference" }).Value.ToString()
        $_hostFTT = ($vsanPolicy.AnyOfRuleSets.AllOfRules | Where-Object { $_.Capability -like "VSAN.hostFailuresToTolerate" }).Value.ToString()
        if($null -eq ($vsanPolicy.AnyOfRuleSets.AllOfRules | Where-Object { $_.Capability -like "VSAN.subFailuresToTolerate" })) {
            $_subFTT = "0"
        } else {
            $_subFTT = ($vsanPolicy.AnyOfRuleSets.AllOfRules | Where-Object { $_.Capability -like "VSAN.subFailuresToTolerate" }).Value.ToString()
        }
        
        $tempObj.FTT = $_hostFTT + "+" + $_subFTT
        
    } else {
        $tempObj.SiteDisasterTolerance = 'None - standard cluster'
        $tempObj.StoragePolicy = 'Default (RAID-1)'
        $tempObj.FTT = ($vsanPolicy.AnyOfRuleSets.AllOfRules | Where-Object { $_.Capability -like "VSAN.hostFailuresToTolerate" }).Value.ToString() + "+0"
    }           
    $all += $tempObj
}
return $all
}

try 
{   
    $all_vSANs = @()
    $all_vSANs.Clear()
    foreach ($vc in $vcenters) {
        $entities = Get-SpbmEntityConfiguration -Server $vc
        $clientLog.LogAppend("INFO", "COLLECTING SPBM POLICIES","$vc", $global:user, "Getting entities")
        Write-Host "[INFO] [$vc] COLLECTING SPBM POLICIES"
        $policies = $entities | Select-Object StoragePolicy -Unique
        $vsanSummary = GetVsanPolicySummary $policies.StoragePolicy
        
        foreach ($vsanSum in $vsanSummary) {
            $vsanSum.VMCount = ($entities |  Where-Object { $_.StoragePolicy -like $vsanSum.Name }).Count
        }
        
        $all_vSANs += $vsanSummary
    }
    ExportTo $all_vSANs
}
#################################################################################################
################################# END SCRIPT EXECUTION ##########################################
catch {
    Write-Error $_
} finally {
    $clientLog.LogAppend("INFO", "PREPARING TO DISCONNECT VCENTERS","LOCAL", $global:user, "Calculating")
    Write-Host "[INFO] DISCONNECTING FROM VCENTER SERVERS"
    foreach ($vCenter in $vCenters)
    {
        try {
            # Disconnect from vCenter Server
            Disconnect-VIServer -Server $vCenter -Confirm:$false -ErrorAction SilentlyContinue
            $clientLog.LogAppend("INFO", "VCENTER DISCONNECTED",$vcenter.ToString(), $global:user, "Successfully disconected")
            Write-Host "[SUCCESS] DISCONNECTED FROM $($vCenter.ToString())" -ForegroundColor Green
        } catch {
            $clientLog.LogAppend("ERROR", "FAIL TO DISCONNECT FROM VCENTER",$vCenter.ToString(), $global:user, "$_")
            $reason = ($_.Exception.Message -split 'Connect-VIServer').trim()[1]
            Write-Host "[ERROR] FAIL TO DISCONNECT FROM $($vCenter.ToString()): $reason" -ForegroundColor Red
            # exit
        }
    }

    $diference = $vCenters.Count - $Global:global:DefaultVIServers
    $clientLog.LogAppend("INFO", "ALL VCENTER DISCONNECTIONS", "LOCAL", $global:user, "$diference of $($vcenters.count) connected servers")
    Write-Host "[INFO] DISCONNECTED FROM $diference OF $($vcenters.count) VCENTERS"
}