<#
    .SYNOPSIS
    Script to search for Windows Events in Domain Controllers.

    Author: Thomas Rodriges (@L4nzN0t_)
    Required Dependencies: RSAT Module

    VERSION: 1.0.0

    .DESCRIPTION
    Script to search for Windows Events in Domain Controllers.
    It search for specific events logged events or monitoring real time events.
    Filters by user, ip address and eventID are available.

    .PARAMETER Identity
    Specify a user to search.

    .PARAMETER IPAddress
    Specify the IP address to search.

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

Function VerifyUserName () {
    param([string]$user)

    try {
        $account = Get-ADUser -Identity $user -ErrorAction Stop
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

Function CreateQuery () {
    param(
        [string]$_usersid,
        [string]$_sam
    )

    # DEFAULT QUERY FOR USER SEARCH
    $XPath = "((EventData[Data[@Name='TargetUserSid']='$_usersid']) or (EventData[Data[@Name='TargetUserName']='$_sam']) or (EventData[Data[@Name='TargetUserName']='$_sam@FAZENDA.MG']))]"

    if ($ExcludeEventID) { # EXCLUDE SPECIFIC EVENTS
        $temp = $null
        for ($i=0;$i -lt $ExcludeEventID.Count; $i++) {
            $temp += "(EventID!=$($ExcludeEventID[$i])) and "
        }
        $temp = $temp.Substring(0, $temp.Length -5)
        $XPath = "*[System[$temp] and " + $XPath
    }

    elseif($EventID) { # SEARCH FOR SPECIFIC EVENTS
        $temp = $null
        for ($i=0;$i -lt $EventID.Count; $i++) {
            $temp += "(EventID=$($EventID[$i])) or "
        }
        $temp = $temp.Substring(0, $temp.Length -4)
        $XPath = "*[System[$temp] and " + $XPath
    }

    else { # SEARCH ALL EVENTS
        $XPath = "*[" + $XPath
    }

    return $XPath

}

Function WriteData () {
    param( [array]$events )
    $all = @()
    try
    {
        foreach ($event in $events) {
            # Extract data from each event
            $lines = $event.Message -split "`n"
            $description = $lines[0]

            # IP ADDRESS
            $regexIPv4 = '\b(?:(?:2[0-4][0-9]|25[0-5]|1[0-9]{2}|[1-9]?[0-9])\.){3}(?:2[0-4][0-9]|25[0-5]|1[0-9]{2}|[1-9]?[0-9])\b'
            $regexIPv6 = '::1\b'
            $sourceAddress = $lines | Where-Object { $_ -like '*Address:*' }
            if ($sourceAddress -match $regexIPv4) {
                $sourceAddress = $matches[0]
            }
            elseif ($sourceAddress -match $regexIPv6 ) {
                $sourceAddress = $matches[0]
            }
            else {
                $sourceAddress = "-"
            }

            # PORT CONNECTION
            #$sourcePort = $lines | Where-Object { ($_ -like '*Source Port:*') -or ($_ -like '*Client Port*') }
            $sourcePort = $lines | Where-Object { $_ -like '*Port:*'}
            if ($sourcePort) {
                $sourcePort = ($sourcePort -split ":")[-1].Trim()
            } else {
                $sourcePort =  "-"
            }

            # USERNAME
            $user = $lines | Where-Object { ($_ -like "*Account Name:*") -and ($_ -notlike "*$*") -and ($_ -notlike "*network*")}
            if ($user.Count -gt 1) {
                $user = ($user[0] -split ":")[-1].Trim()
            }
            else {
                $user = ($user -split ":")[-1].Trim()
            }

            # DOMAIN NAME
            $domain = ($lines | Where-Object { ($_ -like "*Realm Name:*") -or ($_ -like "*Account Domain:*")})

            # EVENT ID 4738 - A USER ACCOUNT WAS CHANGED
            if ($event.Id -eq 4738) {
                $user = ($user[1] -split ":")[-1].Trim() # Get the account of target username
            }

            # EVENT ID 4740 - A USER ACCOUNT WAS LOCKED OUT
            if ($event.Id -eq 4740) {
                $sourceAddress = $lines | Where-Object { $_ -like '*Caller Computer Name:*' }
                $sourceAddress = ($sourceAddress -split ":")[-1].Trim()
            }

            # EVENT ID 4768 - A KERBEROS AUTHENTICATION TICKET (TGT) WAS REQUESTED
            if ($event.Id -eq 4768)
            {
                $domain = ($lines | Where-Object { ($_ -like "*Realm Name:*") })
                $domain = ($domain -split ":")[-1].Trim()
            }

            # EVENT ID 4624 -
            if ($event.Id -eq 4624 )
            {
                $processName = ($lines | Where-Object { ($_ -like "*Process Name:*") })
                $processName = $processName -replace '.*Process Name:\s+',''

                $authPackage = ($lines | Where-Object { ($_ -like "*Authentication Package:*") })
                $authPackage = ($authPackage -split ":")[-1].Trim()
            }

            #Network Address

            # EVENT ID 4768 - A KERBEROS AUTHENTICATION TICKET (TGT) WAS REQUESTED
            # if ($event.Id -eq 4768)
            # {
            #     $domain = ($lines | Where-Object { ($_ -like "*Realm Name:*") })
            #     $domain = ($domain -split ":")[-1].Trim()
            # }

            # if ($event.Id -eq 4771)
            # {
            #     $domain = $null

            #     $clientPort = ($lines | Where-Object { ($_ -like "*Client Port:*") })
            #     $clientPort = ($clientPort -split ":")[-1].Trim()
            #     $sourcePort = $clientPort
            # }
            # else {
            #     $domain = ($lines | Where-Object { ($_ -like "*Account Domain:*") })[0]
            #     $domain = ($domain -split ":")[-1].Trim()

            #     $clientAddress = "-"
            #     $clientPort = "-"
            # }

            if ($domain) {
                $domain = ($domain -split ":")[-1].Trim()
                if($domain -eq "-") {
                    $account = $user
                } else {
                    $account = "$domain\$user"
                }
            } else {
                $account = $user
            }

            # $all += $event | Select-Object RecordId, TimeCreated, MachineName, Id, TaskDisplayName, KeywordsDisplayNames,@{Label="User Account";Expression={"$account"} }, @{Label="Source Network Address";Expression={$sourceAddress} }, @{Label="Source Port";Expression={$sourcePort} }, @{Label="Description";Expression={$description} }, `
            #     @{Label="Client Address";Expression={$clientAddress} }, @{Label="Client Port";Expression={$clientPort} }

            $all += $event | Select-Object RecordId, TimeCreated, MachineName, Id, TaskDisplayName,@{Label="User Account";Expression={"$account"} }, @{Label="Source Network Address";Expression={$sourceAddress} }, @{Label="Source Port";Expression={$sourcePort} }, ` #@{Label="Description";Expression={$description} }, `
                @{Label="Auth Package";Expression={$authPackage} }, @{Label="Process";Expression={$processName} }, @{Label="Description";Expression={$description} }
        }
        return $all
    } catch {
        Write-Error $_
    }

}

Function GetEventLogs ()
{
    param(
        [string]$logname,
        [string]$ipaddress,
        [string]$usersid,
        [Microsoft.ActiveDirectory.Management.ADAccount]$useraccount,
        [int]$maxevents,
        [switch]$oldest,
        [switch]$wait
    )
    try {
        if ($wait) {
            Write-Host "INFO! Monitoring..." -ForegroundColor Green -BackgroundColor Black
            if ($useraccount -and $IPAddress)
            {

            }
            elseif ($ipaddress) {

            }
            elseif ($useraccount) {
                $usersid = $useraccount.SID.Value
                $sam = $useraccount.SamAccountName
                $lastRecordID = 0
                while ($true)
                {
                    $XPath = CreateQuery -_usersid $usersid -_sam $sam
                    $_event = Get-WinEvent -ComputerName BHEDC216 -FilterXPath $XPath -LogName $logname -MaxEvents 1 -ErrorAction SilentlyContinue
                    if ($_event.RecordId -eq $lastRecordID) {
                        continue
                    } else {
                        $lastRecordID = $_event.RecordId
                        $temp = WriteData $_event
                        $temp | Format-Table -AutoSize -Wrap
                    }

                }
            }
        }
        elseif($oldest) { ## GET OLDER EVENTS
            Write-Host "INFO! Searching..." -ForegroundColor Yellow -BackgroundColor Black
            $all = @()
            if ($useraccount -and $IPAddress)
            {
                if ($ExcludeEventID) {
                    $XPath = "*[System[(EventID!=$ExcludeEventID)]] and [EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
                }
                elseif($EventID) {
                    $XPath = "*[EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
                }
                else {
                    $XPath = "*[EventData[Data[@Name='TargetUserSid']='$usersid'] and EventData[Data[@Name='IpAddress']='$IPAddress']]"
                }
                $events = Get-WinEvent -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction Stop
                $all += WriteData $events
            }

            elseif ($ipaddress) {
                $XPath = "*[EventData[Data[@Name='IpAddress']='$IPAddress']]"
                $events = Get-WinEvent -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction Stop
                $all += WriteData $events
            }

            elseif ($useraccount) {
            $usersid = $useraccount.SID.Value
            $sam = $useraccount.SamAccountName
                foreach ($dc in $domainControllers) {

                    # DEFAULT QUERY FOR USER SEARCH
                    $XPath = "((EventData[Data[@Name='TargetUserSid']='$usersid']) or (EventData[Data[@Name='TargetUserName']='$sam']) or (EventData[Data[@Name='TargetUserName']='$sam@FAZENDA.MG']))]"

                    if ($ExcludeEventID) { # EXCLUDE SPECIFIC EVENTS
                        $temp = $null
                        for ($i=0;$i -lt $ExcludeEventID.Count; $i++) {
                            $temp += "(EventID!=$($ExcludeEventID[$i])) and "
                        }
                        $temp = $temp.Substring(0, $temp.Length -5)
                        $XPath = "*[System[$temp] and " + $XPath
                    }

                    elseif($EventID) { # SEARCH FOR SPECIFIC EVENTS
                        $temp = $null
                        for ($i=0;$i -lt $EventID.Count; $i++) {
                            $temp += "(EventID=$($EventID[$i])) or "
                        }
                        $temp = $temp.Substring(0, $temp.Length -4)
                        $XPath = "*[System[$temp] and " + $XPath
                    }

                    else { # SEARCH ALL EVENTS
                        $XPath = "*[" + $XPath
                    }

                    Write-Host "INFO! Searching in $dc..." -ForegroundColor Yellow -BackgroundColor Black
                    $events = Get-WinEvent -ComputerName $dc -FilterXPath $XPath -LogName $logname -MaxEvents $maxevents -ErrorAction SilentlyContinue

                    if (!($null -eq $events))
                    {
                        $all += WriteData $events
                    }

                }
            }

            # Write Summary of logs
            $all | Sort-Object TimeCreated -Descending | Format-Table -AutoSize -Wrap
            Write-Host ""
            Write-Host "SUMMARY! Total events: $($all.Count)" -ForegroundColor Yellow -BackgroundColor Black
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

if ($Identity -and $IPAddress)
{
    $userAccount = VerifyUserName $Identity
    $validIP = VerifyIPAddress $IPAddress
    if (($validIP) -and ($userAccount))
    {
        # WOrk HEre

        if ($Oldest) # Oldest events
        {
            GetEventLogs -ipaddress $IPAddress -usersid $userAccount.SID.value -logname (VerifyLogName $LogName) -maxevents $MaxEvents -oldest
        }
        elseif ($Wait) { # Realtime events
            GetEventLogs -ipaddress $IPAddress -usersid $userAccount.SID.value -logname (VerifyLogName $LogName) -maxevents $MaxEvents -wait
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
    Write-Host "INFO! User Located - $($userAccount.SamAccountName)" -ForegroundColor Yellow -BackgroundColor Black

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

else
{
    Write-Error "You should specified a valid option. See Get-Help EventRecord.ps1."
    exit 1
}
