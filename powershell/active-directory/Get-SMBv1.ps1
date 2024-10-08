<#
.SYNOPSIS

Gets the protocol SMBv1 from all machines available in the domain

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: RSAT Module

VERSION 1.0.1

.DESCRIPTION

Script designed to check the status of SMB1 and SMB2 protocols in a network environment using Windows Remote Managemenet (WinRM).
By default it will get all the Windows Server systems.
Log files will be save in the directory C:\temp\_SMBInfo.

.PARAMETER ComputerName

Specify a computer to query for SMB version.

#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    [Parameter(Mandatory=$false)]
    [string]
    $ComputerName

)

$originalProgressPreference = $ProgressPreference
$ProgressPreference = "SilentlyContinue"
$logDir = "C:\temp\_SMBInfo\"
$logFile = "$logDir\smb.log"
$logFileError = "$logDir\smberror.log"
$currentUserName = whoami
$WindowsVersion = "Server"

Function LogError () {
  Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=0)]
    [String]$string
  )
  if (!(Test-Path $logDir)) {
    New-Item -ItemType directory -Path $logDir | Out-Null
  }
  if (!(Test-Path $logFileError)) {
    New-Item -ItemType File -Path $logFileError | Out-Null
  }
  if ($String.length) {
    $string = "[$(Get-Date -Format "dd:mm:yy HH:mm:ss")] $currentUserName - $string"
  }
  $string | Out-File -Encoding ASCII -Append "$logFileError"
}

Function Log () {
  Param(
    [Parameter(Mandatory=$false, ValueFromPipeline=$true, Position=0)]
    [String]$string
  )
  if (!(Test-Path $logDir)) {
    New-Item -ItemType directory -Path $logDir | Out-Null
  }
  if (!(Test-Path $logFile)) {
    New-Item -ItemType File -Path $logFile | Out-Null
  }
  if ($String.length) {
    $string = "[$(Get-Date -Format "dd:mm:yy HH:mm:ss")] $currentUserName - $string"
  }
  $string | Out-File -Encoding ASCII -Append "$logFile"
}

Function CheckDependencies () {
  try {
    $computerInfo = Get-ComputerInfo | Select-Object WindowsInstallationType,OsName,CsDomainRole,CsDomain

    if ($computerInfo.CsDomain -eq "WORKGROUP")
    {
      Write-Host "ERROR! This computer is not joined to any domain" -ForegroundColor Red -BackgroundColor Black
      Log "ERROR! This computer is not joined to any domain"
      return $false
    }

    if ($computerInfo.WindowsInstallationType -eq "Client")
    {
      # Check dependencies
      Write-Host "INFO! Check Dependencies" -ForegroundColor Yellow -BackgroundColor Black
      if ((Get-WindowsCapability -Name *Rsat.ActiveDirectory* -Online).State -eq "Installed")
      {
        Write-Host "INFO! RSAT Module found" -ForegroundColor Green -BackgroundColor Black
        Log "RSAT Module found"
        $temp = Get-WindowsCapability -Name *Rsat.ActiveDirectory* -Online | Select-Object Name,State,Description | Format-List | Out-String
        Log "$temp"
        #Write-Host $temp
        Write-Host "INFO! Dependency check finished" -ForegroundColor Yellow -BackgroundColor Black
        Write-Host ""
        Log "Dependency check finished"
        return $true
      }
      elseif ((Get-WindowsCapability -Name *Rsat.ActiveDirectory* -Online).State -eq "NotPresent")
      {
        Write-Host "WARNING! RSAT.ActiveDirectory Module not found!" -ForegroundColor Red -BackgroundColor Black
        Log "WARNING - RSAT.ActiveDirectory Module not found!"
        Write-Host "INFO! Preparing to install.." -ForegroundColor Yellow -BackgroundColor Black
        Log "Preparing to install..."
        Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools | Out-Null
        $temp = Get-WindowsCapability -Name *Rsat.ActiveDirectory* -Online | Select-Object Name,State,Description | Format-List | Out-String
        Log "$temp"
        Write-Host "INFO! RSAT Module installed" -ForegroundColor Green -BackgroundColor Black
        Write-Host "INFO! Dependency check finished" -ForegroundColor Yellow -BackgroundColor Black
        Write-Host ""
        Log "Dependency check finished"
        return $true
      }
    }
    if ($computerInfo.WindowsInstallationType -eq "Server")
    {
      # Check dependencies
      Write-Host "INFO! Check Dependencies" -ForegroundColor Yellow -BackgroundColor Black
      if ($computerInfo.CsDomainRole -like "*DomainController*")
      {
        Write-Host "INFO! Executing in domain controller $env:computername" -ForegroundColor Yellow -BackgroundColor Black
        Log "INFO! Executing in domain controller $env:computername"
        return $true
      }
      else {
        if(!(Get-WindowsFeature -Name RSAT).Installed)
        {
          Write-Host "WARNING! RSAT Module not found!" -ForegroundColor Red -BackgroundColor Black
          Log "WARNING - RSAT Module not found!"
          Write-Host "INFO! Preparing to install.." -ForegroundColor Yellow -BackgroundColor Black
          Log "Preparing to install..."
          Add-WindowsFeature -Name RSAT - | Out-Null
          $temp = Get-WindowsFeature -Name RSAT | Select-Object Name,InstallState,Description | Format-List | Out-String
          Log "$temp"
          Write-Host "INFO! RSAT Module installed" -ForegroundColor Green -BackgroundColor Black
          Write-Host "INFO! Dependency check finished" -ForegroundColor Yellow -BackgroundColor Black
          Write-Host ""
          Log "Dependency check finished"
          return $true
        }
        else {
          Write-Host "INFO! RSAT Module found" -ForegroundColor Green -BackgroundColor Black
          Log "RSAT Module found"
          $temp = Get-WindowsFeature -Name RSAT | Select-Object Name,InstallState,Description | Format-List | Out-String
          Log "$temp"
          Write-Host "INFO! Dependency check finished" -ForegroundColor Yellow -BackgroundColor Black
          Write-Host ""
          Log "Dependency check finished"
          return $true
        }
      }
    }
  }
  catch {
    Write-Host "ERROR!! $($_.Exception.Message)" -ForegroundColor Red -BackgroundColor Black
    Log "ERROR - $($_.Exception.Message)"
    return $false
  }
}

if (!(CheckDependencies))
{
  exit 1
}

try {
  $domainCN = (Get-AdRootDSE).DefaultNamingContext

  if ($ComputerName)
  {
    $machines = Get-AdComputer $ComputerName -ErrorAction Stop
  }

  if ($WindowsVersion -eq "Server")
  {
    $machines = Get-AdComputer -Filter {OperatingSystem -like "*Windows Server*"} -SearchBase $domainCN | Where-Object {$_.Enabled -eq $True}
  }

    $machinesError = @()
    $machinesSuccess = Invoke-Command -ComputerName $machines.Name -ErrorAction SilentlyContinue -ErrorVariable machinesError -ThrottleLimit 10 -ScriptBlock {Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol,EnableSMB2Protocol}
    $smb1EnabledMachines = $machinesSuccess | Where-Object {$_.EnableSMB1Protocol -eq $True }

    # Log all machines that executed the script in $logFile
    Log "Process succeed in $($machinesSuccess.RunspaceId.Count) machines"

    # Log only SMB1 machines n $logFile
    if ($null -eq $smb1EnabledMachines)
    {
        Log "SMBv1 Protocol is not enabled in machine"
    } else
    {
        Log "SMBv1 Protocol enabled in $($temp.Count) machines"
        Log "Machines:"
        Log ($smb1EnabledMachines | Format-Table PSComputerName, EnableSMB1Protocol, RunspaceId | Out-String)
    }

    # Log only SMB2 machines n $logFile
    $smb2EnabledMachines = $machinesSuccess | Where-Object { $_.EnableSMB2Protocol -eq $True }
    if ($null -eq $smb2EnabledMachines)
    {
        Log "SMBv2 Protocol is not enabled in machine"
    } else {
        Log "SMBv2 Protocol enabled in $($smb2EnabledMachines.Count) machines"
        Log "Machines:"
        Log ($smb2EnabledMachines | Format-Table PSComputerName, EnableSMB2Protocol, RunspaceId | Out-String)
    }

    # Log failed machines in $logFile
    Log "Process failed in $($machinesError.Count) machines"
    Log ($machinesError | Select-Object TargetObject, CategoryInfo | Out-String)

    # Log failed machines in $logFileError | Increased verbosity
    Log "Process failed in $($machinesError.Count) machines"
    $machinesError | ForEach-Object {
      Log "ERROR - $($_.TargetObject)"
      Log "$($_.Exception)"
    }


    # Write results in host
    Write-Host ""
    Write-Host "Summary" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "-------" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "Total machines execution = $($machines.SID.Count)" -ForegroundColor Yellow -BackgroundColor Black
    Write-Host "Total machines execution completed = $($machinesSuccess.RunspaceId.Count)" -ForegroundColor Green -BackgroundColor Black
    Write-Host "Total machines execution failed = $($machinesError.Count)" -ForegroundColor Red -BackgroundColor Black
    Write-Host ""
    Write-Host "Log saved in $logFile" -ForegroundColor Yellow -BackgroundColor Black
    if ($machinesError.Count -eq $machines.SID.Count) {
        exit 1
    }
    if ($null -eq $smb1EnabledMachines)
    {
        Write-Host "All machines have the with SMBv1 DISABLED" -ForegroundColor Yellow -BackgroundColor Black
    }
    else {
        Write-Host "Machines with SMBv1 ENABLED" -ForegroundColor Yellow -BackgroundColor Black
        $smb1EnabledMachines | Format-Table PSComputerName, EnableSMB1Protocol
    }
} catch [System.Management.Automation.CommandNotFoundException] {
  Log "ERROR - $_"
  Write-Warning "Error!! - $_"
  Write-Warning "Consider install module ADD"
}
catch {
  Log "ERROR - $_"
  Write-Warning "Error!! - $_"
} finally {
  $ProgressPreference = $originalProgressPreference
}
