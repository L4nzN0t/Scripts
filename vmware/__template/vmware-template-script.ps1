<#
.SYNOPSIS

What the script does

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.1

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
    [Parameter(Mandatory=$true)]
    [string]
    $VCList,

    [Parameter(Mandatory=$true)]
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
try 
{
    
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

    $clientLog.LogAppend("INFO", "ALL VCENTER DISCONNECTIONS", "LOCAL", $global:user, "$($global:sDefautVIServers.count) of $($vcenters.count) connected servers")
    Write-Host "[INFO] DISCONNECTED FROM $($global:DefautVIServers.count) OF $($vcenters.count) VCENTERS"
}