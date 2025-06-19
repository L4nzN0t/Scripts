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
C:/PS> ./template-script.ps1 -Username teste@vsphere.local -Password Password@123 -VCList vclist.txt

#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    [Parameter(Mandatory=$false)]
    [string]
    $vCenter,

    [Parameter(Mandatory=$false)]
    [string]
    $Username,

    [Parameter(Mandatory=$true)]
    [securestring]
    $Password

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
    
    Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null
    $clientLog.LogAppend("INFO", "Set-PowerCLIConfiguration", "LOCAL", $global:user, "Set UserParticipateInCEIP to False")

    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
    $clientLog.LogAppend("INFO", "Set-PowerCLIConfiguration", "LOCAL", $global:user, "Set InvalidCertificateActions to Ignore")

    Set-PowerCLIConfiguration -DefaultVIServerMode Multiple -Confirm:$false | Out-Null # Still working 
    $clientLog.LogAppend("INFO", "Set-PowerCLIConfiguration", "LOCAL", $global:user, "Set DefaultVIServerMode to Multiple")
        
    # Connect to each vCenter
    Write-Host "[INFO] CONNECTING TO VCENTER SERVER"
    
    try {
        Connect-VIServer -Server $vCenter -Credential $auth.credential -Protocol HTTPS -ErrorAction Stop | Out-Null
        $clientLog.LogAppend("INFO", "CONNECTED TO VCENTER", $vCenter.ToString(), $global:user, "Success authentication")
        Write-Host "[SUCCESS] CONNECTED TO $($vCenter.ToString())" -ForegroundColor Green
    } catch {
        $clientLog.LogAppend("ERROR", "CONNECTION FAIL", $vCenter.ToString(), $global:user, "$_")
        $reason = ($_.Exception.Message -split 'Connect-VIServer').trim()[1]
        Write-Host "[ERROR] DISCONNECTED FROM $($vCenter.ToString()): $reason" -ForegroundColor Red
    }

    $clientLog.LogAppend("INFO", "ALL VCENTER CONNECTIONS", "LOCAL", $global:user, "$($global:sDefautVIServers.count) of $($vCenter.count) connected servers")
    Write-Host "[INFO] CONNECTED IN $($global:DefaultVIServers.count) OF $($vCenter.count) VCENTERS"
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
try 
{
    $sws = Get-VDSwitch
    foreach ($sw in $sws)
    {
        $clientLog.LogAppend("INFO", "PREPARE TO CREATE NEW VDS", "LOCAL", $global:user, "")
        Write-Host "[INFO] PREPARE TO CREATE NEW VDS"
        
        # Create the network folder (if it doesn't already exist)
        $datacenter = Get-Datacenter
        $folderName = "New Switches"

        $folder = Get-Folder -Name $folderName -ErrorAction SilentlyContinue
        if (-not $folder) {
            $folder = New-Folder -Name $folderName -Location ($datacenter | Get-Folder -Name "network" -Type 'Network')
            $clientLog.LogAppend("INFO", "NEW FOLDER CREATED", "LOCAL", $global:user, "Folder name - $folderName")
        } else {
            $clientLog.LogAppend("INFO", "FOLDER ALREADY EXISTS", "LOCAL", $global:user, "Folder name - $folderName")
            Write-Host "[INFO] FOLDER ALREADY EXISTS - '$folderName'"
        }

        # Create the new VDS
        Write-Host "[INFO] VDS CURRENT NAME: $($sw.Name)" -ForegroundColor Cyan
        $newVDSName = Read-Host "[INFO] VDS NEW NAME"
        
        if ($null -eq $newVDSName) {
            $newVDSName = "New-VDS-$(Get-random)"
        }

        $clientLog.LogAppend("INFO", "CREATING NEW VDS", "LOCAL", $global:user, "Create new virtual distributed switch - $newVDSName")
        Write-Host "[INFO] CREATING NEW VDS"
        $sw | New-VDSwitch -Name $newVDSName -Location $folder | Out-Null
        Set-VDSwitch -VDSwitch $newVDSName -Version '7.0.3'

        $clientLog.LogAppend("SUCCESS", "NEW VDS CREATED", "LOCAL", $global:user, "New virtual distributed switch created - $newVDSName")
        Write-Host "[SUCCESS] NEW VDS CREATED" -ForegroundColor Green
        $nSW = Get-VDSwitch $newVDSName | Out-Null

        $clientLog.LogAppend("SUCCESS", "NEW VDS NAME", "LOCAL", $global:user, "$($nSW.Name)")
        $clientLog.LogAppend("SUCCESS", "NEW VDS MTU", "LOCAL", $global:user, "$($nSW.Mtu)")
        $clientLog.LogAppend("SUCCESS", "NEW VDS VERSION", "LOCAL", $global:user, "$($nSW.Version)")
        Write-Host "[SUCCESS] NEW VDS NAME $($nSW.Name)" -ForegroundColor Green
        Write-Host "[SUCCESS] NEW VDS MTU $($nSW.Mtu)" -ForegroundColor Green
        Write-Host "[SUCCESS] NEW VDS VERSION $($nSW.Version)" -ForegroundColor Green
        Write-Host ""
    }
}
#################################################################################################
################################# END SCRIPT EXECUTION ##########################################
catch {
    Write-Error $_
} finally {
    $clientLog.LogAppend("INFO", "PREPARING TO DISCONNECT VCENTERS","LOCAL", $global:user, "Calculating")
    Write-Host "[INFO] DISCONNECTING FROM VCENTER SERVERS"
    foreach ($vCenter in $global:DefautVIServers)
    {
        try {
            # Disconnect from vCenter Server
            Disconnect-VIServer -Server $vCenter.Name -Confirm:$false -ErrorAction SilentlyContinue
            $clientLog.LogAppend("INFO", "VCENTER DISCONNECTED",$vCenter.Name.ToString(), $global:user, "Successfully disconected")
            Write-Host "[SUCCESS] DISCONNECTED FROM $($vCenter.Name.ToString())" -ForegroundColor Green
        } catch {
            $clientLog.LogAppend("ERROR", "FAIL TO DISCONNECT FROM VCENTER",$vCenter.Name.ToString(), $global:user, "$_")
            $reason = ($_.Exception.Message -split 'Connect-VIServer').trim()[1]
            Write-Host "[ERROR] FAIL TO DISCONNECT FROM $($vCenter.Name.ToString()): $reason" -ForegroundColor Red
            # exit
        }
    }

    $clientLog.LogAppend("INFO", "ALL VCENTER DISCONNECTIONS", "LOCAL", $global:user, "$($global:DefautVIServers.count) of $($vCenter.count) connected servers")
    Write-Host "[INFO] CONNECTED IN $($global:DefautVIServers.count) OF $($vCenter.count) VCENTERS"
}