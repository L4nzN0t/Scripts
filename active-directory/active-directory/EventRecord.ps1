<#
    .SYNOPSIS
    Script to search for Windows Events in Domain Controllers.

    Author: Thomas Rodriges (@L4nzN0t_)
    Required Dependencies: RSAT Module

    VERSION: 1.0.1

    .DESCRIPTION
    Script to search for Windows Events in Domain Controllers.
    It search for specific events logged events or monitoring real time events.
    Filters by user, ip address and eventID are available.

    .PARAMETER Identity
    Specify a user to search.

    .PARAMETER IPAddress
    Specify the IP address to search.

    .PARAMETER Protocol
    Specify the authentication protocol you want to use: NTLM or Kerberos.

    .PARAMETER Wait
    Monitor events in real time.

    .PARAMETER Oldest
    Search in older events.

    .PARAMETER MaxEvents
    Defines the maximum number of events per server. Default is 10.

    .PARAMETER EventID
    Search for specific events.

    .PARAMETER ExcludeEventID
    Exclude specific events.

    .EXAMPLE
    # Search for the user 'user.name' in older events
    C:\PS> .\EventRecord.ps1 -Identity user.name -LogName 'security' -Oldest

    # Search for ip address '192.168.1.10' in older events and set the maximum events to 50.
    C:\PS> .\EventRecord.ps1 -IPAdress 192.168.1.10 -LogName 'security' -Oldest -MaxEvents 50

    # Search for events when user 'user.name' access using ip address '192.168.1.10'.
    C:\PS> .\EventRecord.ps1 -Identity user.name -IPAdress 192.168.1.10 -LogName 'security' -Oldest -MaxEvents 50

    # Search for events with ID 4770 with the user 'user.name'.
    C:\PS> .\EventRecord.ps1 -Identity user.name -LogName 'security' -Oldest -MaxEvents 50 -EventID 4770

    # Search for all events but 4634,4624 with the user 'user.name'.
    C:\PS> .\EventRecord.ps1 -Identity user.name -LogName 'security' -Oldest -MaxEvents 50 ExcludeEventID 4634,4624

    .LINK
    https://www.ultimatewindowssecurity.com/securitylog/encyclopedia/
    https://powershell.org/2019/08/a-better-way-to-search-events/
#>

[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    [Parameter(Mandatory=$false)]
    [string]
    $Identity,

    [Parameter(Mandatory=$false)]
    [string]
    $IPAddress,

    [Parameter(Mandatory=$false)]
    [string]
    $LogName,

    [Parameter(Mandatory=$false)]
    [string]
    $Protocol,

    [Parameter(Mandatory=$false)]
    [switch]
    $Oldest,

    [Parameter(Mandatory=$false)]
    [switch]
    $Wait,

    [Parameter(Mandatory=$false)]
    [int]
    $MaxEvents,

    [Parameter(Mandatory=$false)]
    [int[]]
    $EventID,

    [Parameter(Mandatory=$false)]
    [int[]]
    $ExcludeEventID
)

###############
## FUNCTIONS ##
###############

Function VerifyProtocol () {
    param([string]$protocol)

    if($protocol)
    {
        if ($protocol -eq "Kerberos") {
            return $true
        } elseif ($protocol -eq "NTLM") {
            return $true
        }
    } else {
        Write-Error "$_"
        exit 1
    }
}

Function VerifyUserName () {
    param([string]$user)

    try {
        $account = Get-ADUser -Identity $user -ErrorAction Stop
        Write-Host "INFO! User Located - $($account.SamAccountName)" -ForegroundColor Yellow -BackgroundColor Black
        return $account
    }
    catch {
        Write-Error "$_"
        exit 1
    }
}

Function VerifyIPAddress () {
    param([string]$ip)

    try {
        $IPregex = '^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$'
        if($ip -match $IPregex) {
            Write-Host "INFO! Valid IP - $ip" -ForegroundColor Yellow -BackgroundColor Black
            return $true
        }
        else {
            throw "IP Address invalid!"
        }
    } catch  {
        Write-Error "$_"
        exit 1
    }
}

Function VerifyLogName () {
    param([string]$logname)

    if(!($logname))
    {
        $logname = 'Security'
        return $logname
    } else {
        return $logname
    }
}

Function ValidateEvents () {
    param([psobject]$events)
    if ($events)
    {
        return $true
    } else {
        return $false
    }

}

Function CreateQuery () {
    param(
        [string]$_usersid,
        [string]$_sam,
        [string]$_ip,
        [string]$_protocol
    )

    if ((($_usersid) -and ($_sam)) -and $_ip)
    {
        $XPath = "*[((EventData[Data[@Name='TargetUserSid']='$_usersid']) or (EventData[Data[@Name='TargetUserName']='$_sam']) or (EventData[Data[@Name='TargetUserName']='$_sam@$dnsRoot'])) and [EventData[Data[@Name='IpAddress']='$IPAddress']]"
        #$XPath = "*[EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
    }

    if (($_usersid) -and ($_sam))
    {
        # DEFAULT QUERY FOR USER SEARCH
        $XPath = "*[((EventData[Data[@Name='TargetUserSid']='$_usersid']) or (EventData[Data[@Name='TargetUserName']='$_sam']) or (EventData[Data[@Name='TargetUserName']='$_sam@$dnsRoot']))]"
    }

    if ($_ip)
    {
        $XPath = "*[EventData[Data[@Name='IpAddress']='$IPAddress']]"
    }

    if ($_protocol)
    {
        $XPath = "*[EventData[Data[@Name='AuthenticationPackageName']='$protocol']]"
    }

    if ($ExcludeEventID) { # EXCLUDE SPECIFIC EVENTS
        $temp = $null
        for ($i=0;$i -lt $ExcludeEventID.Count; $i++) {
            $temp += "(EventID!=$($ExcludeEventID[$i])) and "
        }
        $temp = $temp.Substring(0, $temp.Length -5)
        $XPath = "*[System[$temp]] and " + $XPath
    }

    elseif($EventID) { # SEARCH FOR SPECIFIC EVENTS
        $temp = $null
        for ($i=0;$i -lt $EventID.Count; $i++) {
            $temp += "(EventID=$($EventID[$i])) or "
        }
        $temp = $temp.Substring(0, $temp.Length -4)
        $XPath = "*[System[$temp]] and " + $XPath
    }

    # else { # SEARCH ALL EVENTS
    #     $XPath = "*[" + $XPath
    # }

    return $XPath

}

Function CustomObjectLog($recordId, $timeCreated, $machineName, $id, $taskDisplayName, $infoDisplayName, $domain, $accountName, $sourceNetworkAddress, $SourcePort, $AuthPackage, $NTLMVersion, $processName, $description, $shareName) {
    $properties = [ordered] @{
        'RecordId' = $recordId
        'TimeCreated' = $timeCreated
        'MachineName' = $machineName
        'Event Id' = $id
        'TaskDisplayName'=$taskDisplayName
        'InfoDisplayName'=$infoDisplayName
        'Domain'=$domain
        'Account Name'=$accountName
        'Source Network Address'=$sourceNetworkAddress
        'Source Port' = $sourcePort
        'Auth Package' = $authPackage
        'NTLM Version' = $NTLMVersion
        'Process' = $processName
        'Description' = $description
        'ShareName' = $shareName
    }
    $object = New-Object -TypeName psobject -Property $properties
    return $object
}

Function WriteData () {
    param( [array]$events )
    $all = @()
    try
    {
        foreach ($event in $events) {
            # Extract data from each event
            $_LOGLINES = $event.Message -split "`n"

            if ($event.Id -eq 5140)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Source Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourcePort = (($_LOGLINES | Select-String -Pattern "Source Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_ShareName = (($_LOGLINES | Select-String -Pattern "Share Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = "-"
                $_Description = $_LOGLINES[0]
            }
            elseif ($event.Id -eq 4648)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Network Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourcePort = (($_LOGLINES | Select-String -Pattern "Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = (($_LOGLINES | Select-String -Pattern "Additional Information" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4624)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Source Network Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourcePort = (($_LOGLINES | Select-String -Pattern "Source Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_ShareName = "-"
                $_AuthPackage = (($_LOGLINES | Select-String -Pattern "Authentication Package" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_NTLMVersion = (($_LOGLINES | Select-String -Pattern "Package Name \(NTLM only\)" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Process = (($_LOGLINES | Select-String -Pattern "Logon Process" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4627)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = "-"
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4634)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = "-"
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4688)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = (($_LOGLINES | Select-String -Pattern "New Process Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4770)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4771)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = "-"
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Client Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourcePort = (($_LOGLINES | Select-String -Pattern "Client Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4740)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Caller Computer Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = "-"
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4768)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Supplied Realm Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            elseif ($event.Id -eq 4769)
            {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                $_Description = $_LOGLINES[0]
            }

            else {
                $_recordID = $event.RecordId
                $_timeCreated = $event.TimeCreated
                $_machineName = $event.MachineName
                $_eventID = $event.Id
                $_TaskDisplayName = $event.TaskDisplayName
                $_InfoDisplayName = $event.KeywordsDisplayNames
                $_Domain = "-"
                $_AccountName = "-"
                $_SourceAddress = "-"
                $_SourcePort = "-"
                $_ShareName = "-"
                $_AuthPackage = "-"
                $_NTLMVersion = "-"
                $_Process = "-"
                $_Description = $_LOGLINES[0]
            }

            $all += CustomObjectLog $_recordID $_timeCreated $_machineName $_eventID $_TaskDisplayName $_InfoDisplayName $_Domain $_AccountName $_SourceAddress $_SourcePort $_AuthPackage $_NTLMVersion $_Process $_Description $_ShareName
            }
        return $all
    } catch {
        Write-Error $_
    }
}

Function Start-ParallelJob {
    param (
        [string]$ComputerName,
        [string]$LogName,
        [string]$Protocol,
        [string]$UserSID,
        [string]$SAM,
        [string]$IPAddress
    )

    Start-Job -ScriptBlock {
        param ($ComputerName, $LogName, $Protocol, $UserSID, $SAM, $IPAddress)

        Function Log () {
            param([pscustomobject]$value,
                [switch]$Protocol,
                [switch]$IPAddress,
                [switch]$User
            )
            $dnsRoot = (Get-ADDomain).DnsRoot
            $path = "\\$dnsRoot\SYSVOL\$dnsRoot\scripts\"
            $fullPath = $path + "logs\"

            if (Test-Path $fullPath)
            {
                if ($Protocol)
                {
                    $fileLog = "logEvents-protocol.txt"
                }
                elseif ($IPAddress)
                {
                    $fileLog = "logEvents-ip.txt"
                }
                elseif ($User)
                {
                    $fileLog = "logEvents-user.txt"
                }
                $pathLog = $fullPath + $fileLog
                $value | Export-Csv -Path $pathLog -Encoding UTF8 -Append -NoTypeInformation
            } else {
                mkdir $fullPath
                if ($Protocol)
                {
                    $fileLog = "logEvents-protocol.txt"
                }
                elseif ($IPAddress)
                {
                    $fileLog = "logEvents-ip.txt"
                }
                elseif ($User)
                {
                    $fileLog = "logEvents-user.txt"
                }
                $pathLog = $fullPath + $fileLog
                New-Item -ItemType File -Name $pathLog
                $value | Export-Csv -Path $pathLog -Encoding UTF8 -Append -NoTypeInformation
            }

        }

        Function CustomObjectLog($recordId, $timeCreated, $machineName, $id, $taskDisplayName, $infoDisplayName, $domain, $accountName, $sourceNetworkAddress, $SourcePort, $AuthPackage, $NTLMVersion, $processName, $description, $shareName) {
            $properties = [ordered] @{
                'RecordId' = $recordId
                'TimeCreated' = $timeCreated
                'MachineName' = $machineName
                'Event Id' = $id
                'TaskDisplayName'=$taskDisplayName
                'InfoDisplayName'=$infoDisplayName
                'Domain'=$domain
                'Account Name'=$accountName
                'Source Network Address'=$sourceNetworkAddress
                'Source Port' = $sourcePort
                'Auth Package' = $authPackage
                'NTLM Version' = $NTLMVersion
                'Process' = $processName
                'Description' = $description
                'ShareName' = $shareName
            }
            $object = New-Object -TypeName psobject -Property $properties
            return $object
        }

        Function WriteData () {
            param( [array]$events )
            $all = @()
            try
            {
                foreach ($event in $events) {
                    # Extract data from each event
                    $_LOGLINES = $event.Message -split "`n"

                    if ($event.Id -eq 5140)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Source Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourcePort = (($_LOGLINES | Select-String -Pattern "Source Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_ShareName = (($_LOGLINES | Select-String -Pattern "Share Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = "-"
                        $_Description = $_LOGLINES[0]
                    }
                    elseif ($event.Id -eq 4648)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Network Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourcePort = (($_LOGLINES | Select-String -Pattern "Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = (($_LOGLINES | Select-String -Pattern "Additional Information" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4624)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Source Network Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourcePort = (($_LOGLINES | Select-String -Pattern "Source Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_ShareName = "-"
                        $_AuthPackage = (($_LOGLINES | Select-String -Pattern "Authentication Package" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_NTLMVersion = (($_LOGLINES | Select-String -Pattern "Package Name \(NTLM only\)" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Process = (($_LOGLINES | Select-String -Pattern "Logon Process" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4627)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = "-"
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4634)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = "-"
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4688)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = (($_LOGLINES | Select-String -Pattern "New Process Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4770)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4771)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = "-"
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Client Address" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourcePort = (($_LOGLINES | Select-String -Pattern "Client Port" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4740)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = (($_LOGLINES | Select-String -Pattern "Caller Computer Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = "-"
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4768)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Supplied Realm Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    elseif ($event.Id -eq 4769)
                    {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = (($_LOGLINES | Select-String -Pattern "Account Domain" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_AccountName = (($_LOGLINES | Select-String -Pattern "Account Name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = (($_LOGLINES | Select-String -Pattern "Service name" | Select-Object -ExpandProperty Line) -split ":")[-1].trim()
                        $_Description = $_LOGLINES[0]
                    }

                    else {
                        $_recordID = $event.RecordId
                        $_timeCreated = $event.TimeCreated
                        $_machineName = $event.MachineName
                        $_eventID = $event.Id
                        $_TaskDisplayName = $event.TaskDisplayName
                        $_InfoDisplayName = $event.KeywordsDisplayNames
                        $_Domain = "-"
                        $_AccountName = "-"
                        $_SourceAddress = "-"
                        $_SourcePort = "-"
                        $_ShareName = "-"
                        $_AuthPackage = "-"
                        $_NTLMVersion = "-"
                        $_Process = "-"
                        $_Description = $_LOGLINES[0]
                    }

                    $all += CustomObjectLog $_recordID $_timeCreated $_machineName $_eventID $_TaskDisplayName $_InfoDisplayName $_Domain $_AccountName $_SourceAddress $_SourcePort $_AuthPackage $_NTLMVersion $_Process $_Description $_ShareName
                    }
                return $all
            } catch {
                Write-Error $_
            }
        }

        Function CreateQuery () {
            param(
                [string]$_usersid,
                [string]$_sam,
                [string]$_ip,
                [string]$_protocol
            )

            if ((($_usersid) -and ($_sam)) -and $_ip)
            {
                $XPath = "*[((EventData[Data[@Name='TargetUserSid']='$_usersid']) or (EventData[Data[@Name='TargetUserName']='$_sam']) or (EventData[Data[@Name='TargetUserName']='$_sam@$dnsRoot'])) and [EventData[Data[@Name='IpAddress']='$IPAddress']]"
                #$XPath = "*[EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
            }

            if (($_usersid) -and ($_sam))
            {
                # DEFAULT QUERY FOR USER SEARCH
                $XPath = "*[((EventData[Data[@Name='TargetUserSid']='$_usersid']) or (EventData[Data[@Name='TargetUserName']='$_sam']) or (EventData[Data[@Name='TargetUserName']='$_sam@$dnsRoot']))]"
            }

            if ($_ip)
            {
                $XPath = "*[EventData[Data[@Name='IpAddress']='$IPAddress']]"
            }

            if ($_protocol)
            {
                $XPath = "*[EventData[Data[@Name='AuthenticationPackageName']='$protocol']]"
            }

            if ($ExcludeEventID) { # EXCLUDE SPECIFIC EVENTS
                $temp = $null
                for ($i=0;$i -lt $ExcludeEventID.Count; $i++) {
                    $temp += "(EventID!=$($ExcludeEventID[$i])) and "
                }
                $temp = $temp.Substring(0, $temp.Length -5)
                $XPath = "*[System[$temp]] and " + $XPath
            }

            elseif($EventID) { # SEARCH FOR SPECIFIC EVENTS
                $temp = $null
                for ($i=0;$i -lt $EventID.Count; $i++) {
                    $temp += "(EventID=$($EventID[$i])) or "
                }
                $temp = $temp.Substring(0, $temp.Length -4)
                $XPath = "*[System[$temp]] and " + $XPath
            }

            # else { # SEARCH ALL EVENTS
            #     $XPath = "*[" + $XPath
            # }

            return $XPath

        }

        if ($Protocol) {
            $lastRecordID = 0
            while ($true) {
                # QUERY
                $XPath = CreateQuery -_protocol $Protocol

                $_event = Get-WinEvent -ComputerName $ComputerName -FilterXPath $XPath -LogName $LogName -MaxEvents 1 -ErrorAction SilentlyContinue
                if ($_event.RecordId -eq $lastRecordID) {
                    continue
                } else {
                    $lastRecordID = $_event.RecordId
                    Log (WriteData $_event) -Protocol
                }
            }
        }
        elseif ($IPAddress) {
            $lastRecordID = 0
            while ($true) {
                # QUERY
                $XPath = CreateQuery -_protocol $IPAddress

                $_event = Get-WinEvent -ComputerName $ComputerName -FilterXPath $XPath -LogName $LogName -MaxEvents 1 -ErrorAction SilentlyContinue
                if ($_event.RecordId -eq $lastRecordID) {
                    continue
                } else {
                    $lastRecordID = $_event.RecordId
                    Log (WriteData $_event) -IPAddress
                }
            }
        }
        elseif ($UserSID) {
            $lastRecordID = 0
            while ($true) {
                # QUERY
                $XPath = CreateQuery -_usersid $UserSID -_sam $SAM

                $_event = Get-WinEvent -ComputerName $ComputerName -FilterXPath $XPath -LogName $LogName -MaxEvents 1 -ErrorAction SilentlyContinue
                if ($_event.RecordId -eq $lastRecordID) {
                    continue
                } else {
                    $lastRecordID = $_event.RecordId
                    Log (WriteData $_event) -User
                }
            }
        }
    } -ArgumentList $ComputerName, $LogName, $Protocol, $UserSID, $SAM, $IPAddress
}

Function GetEventLogs ()
{
    param(
        [string]$logname,
        [string]$ipaddress,
        [string]$protocol,
        [Microsoft.ActiveDirectory.Management.ADAccount]$useraccount,
        [int]$maxevents,
        [switch]$oldest,
        [switch]$wait
    )
    try {
        ############################################################################################################################################################
        ### GET EVENTS IN REAL TIME
        if ($wait) {
            Write-Host "INFO! Monitoring..." -ForegroundColor Green -BackgroundColor Black
            if ($useraccount -and $IPAddress)
            {

            }
            elseif ($ipaddress) {
                foreach ($dc in $domainControllers)
                {
                    # Exemplo de chamada da função
                    Start-ParallelJob -ComputerName $dc -LogName $logname -IPAddress $ipaddress
                }

            }
            elseif ($useraccount) {
                $usersid = $useraccount.SID.Value
                $sam = $useraccount.SamAccountName
                foreach ($dc in $domainControllers)
                {
                    # Exemplo de chamada da função
                    Start-ParallelJob -ComputerName $dc -LogName $logname -UserSID $usersid -SAM $sam
                }
            }
            elseif ($protocol)
            {
                foreach ($dc in $domainControllers)
                {
                    # Exemplo de chamada da função
                    Start-ParallelJob -ComputerName $dc -LogName $logname -Protocol $protocol
                }
            }
        }
        ############################################################################################################################################################
        ### GET OLDER EVENTS
        elseif($oldest)
        {
            Write-Host "INFO! Searching..." -ForegroundColor Yellow -BackgroundColor Black
            $all = @()
            if ($useraccount -and $IPAddress)
            {
                foreach ($dc in $domainControllers)
                {
                    $usersid = $useraccount.SID.Value
                    $sam = $useraccount.SamAccountName

                    $XPath = CreateQuery -_usersid $useraccount -_sam $sam -_ip $ipaddress

                    # if ($ExcludeEventID) {
                    #     $XPath = "*[System[(EventID!=$ExcludeEventID)]] and [EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
                    # }
                    # elseif($EventID) {
                    #     $XPath = "*[EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
                    # }
                    # else {
                    #     $XPath = "*[EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
                    # }
                    $events = Get-WinEvent -ComputerName $dc -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction SilentlyContinue

                    if ((ValidateEvents $events))
                    {
                        $all += WriteData $events
                    }
                }
            }

            elseif ($ipaddress) {
                foreach ($dc in $domainControllers)
                {
                    # QUERY
                    $XPath = CreateQuery -_ip $ipaddress

                    $events = Get-WinEvent -ComputerName $dc -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction SilentlyContinue
                    if ((ValidateEvents $events))
                    {
                        $all += WriteData $events
                    }
                }

            }

            elseif ($useraccount) {
            $usersid = $useraccount.SID.Value
            $sam = $useraccount.SamAccountName
                foreach ($dc in $domainControllers) {

                    # QUERY
                    $XPath = CreateQuery -_usersid $usersid -_sam $sam

                    Write-Host "INFO! Searching in $dc..." -ForegroundColor Yellow -BackgroundColor Black
                    $events = Get-WinEvent -ComputerName $dc -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction SilentlyContinue

                    if ((ValidateEvents $events))
                    {
                        $all += WriteData $events
                    }

                }
            }
            elseif ($protocol)
            {
                foreach ($dc in $domainControllers)
                {
                    # QUERY
                    $XPath = CreateQuery -_protocol $protocol

                    Write-Host "INFO! Searching in $dc..." -ForegroundColor Yellow -BackgroundColor Black
                    $events = Get-WinEvent -ComputerName $dc -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction SilentlyContinue

                    if ((ValidateEvents $events))
                    {
                        $all += WriteData $events
                    }
                }
            }

            # Write Summary of logs
            $all
        }
    }
    catch {
        Write-Error "ERROR! - $($_.Exception.Message)"
    }
}


#########################################################################
############################### EXECUTION ###############################
#########################################################################


if ($MaxEvents -eq 0)
{
    $MaxEvents = 10
}

# Get Domain Controllers
try {
    $domainControllers = (Get-ADDomainController -Filter *).Name
} catch {
    Write-Error $_.Exception.Message
}

try {
    $dnsRoot = (Get-ADDomain).DnsRoot
} catch {
    Write-Error $_.Exception.Message
}


if ($Identity -and $IPAddress)
{
    $userAccount = VerifyUserName $Identity
    $validIP = VerifyIPAddress $IPAddress
    if (($validIP) -and ($userAccount))
    {
        Write-Host "IP and USER" -ForegroundColor Yellow -BackgroundColor Black

        if ($Oldest) # Oldest events
        {
            GetEventLogs -ipaddress $IPAddress -useraccount $userAccount -logname (VerifyLogName $LogName) -maxevents $MaxEvents -oldest
        }
        elseif ($Wait) { # Realtime events
            GetEventLogs -ipaddress $IPAddress -useraccount $userAccount -logname (VerifyLogName $LogName) -maxevents $MaxEvents -wait
        }
        else {
            Write-Error "Option invalid! Try use -Oldest or -Wait. See Get-Help EventRecord.ps1."
            exit 1
        }
    }
    else {
        Write-Error "Option invalid!"
    }
}

elseif ($Identity)
{
    $userAccount = VerifyUserName $Identity

    if ($Oldest) # Oldest events
    {
        GetEventLogs -useraccount $userAccount -logname (VerifyLogName $LogName) -maxevents $MaxEvents -oldest
    }
    elseif ($Wait) { # Realtime events
        GetEventLogs -useraccount $userAccount -logname (VerifyLogName $LogName) -maxevents $MaxEvents -wait
    }
    else {
        Write-Error "Option invalid! Try use -Oldest or -Wait. See Get-Help EventRecord.ps1."
        exit 1
    }

}

elseif ($IPAddress)
{
    VerifyIPAddress $IPAddress | Out-Null

    if ($Oldest) # Oldest events
    {
        GetEventLogs -ipaddress $IPAddress -logname (VerifyLogName $LogName) -maxevents $MaxEvents -oldest
    }
    elseif ($Wait) { # Realtime events
        GetEventLogs -ipaddress $IPAddress -logname (VerifyLogName $LogName) -maxevents $MaxEvents -wait
    }
    else {
        Write-Error "Option invalid! Try use -Oldest or -Wait. See Get-Help EventRecord.ps1."
        exit 1
    }
}

elseif ($Protocol)
{
    VerifyProtocol $Protocol | Out-Null

    if ($Oldest)
    {
        GetEventLogs -protocol $Protocol -logname (VerifyLogName $LogName) -maxevents $MaxEvents -oldest
    }
    elseif ($Wait) {
        GetEventLogs -protocol $Protocol -logname (VerifyLogName $LogName) -maxevents $MaxEvents -wait
    }
    else
    {
        Write-Error "Option invalid! Try use -Oldest or -Wait. See Get-Help EventRecord.ps1."
        exit 1
    }
}

else
{
    Write-Error "You should specified a valid option. See Get-Help EventRecord.ps1."
    exit 1
}