#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
Prepares an EXISTING enterprise Microsoft CA for VCF 9.1 certificate management.
.DESCRIPTION
Run locally in Windows PowerShell 5.1 on the issuing CA (CA and IIS co-located).
Default mode is a read-only preflight/plan. Use -Apply to make changes.
Requires ActiveDirectory, ServerManager and ADCSAdministration modules, and an
existing dedicated AD user. Does not build a new PKI or create accounts/passwords.
See README.md for prerequisites, permission implications, validation and recovery.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)][string]$ServiceAccount,
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_-]{0,63}$')]
    [string]$TemplateName = 'VMwareVCF',
    [string]$TemplateDisplayName = 'VMware VCF',
    [string]$DomainController,
    [string]$SiteName = 'Default Web Site',
    [string]$BackupRoot = "$env:ProgramData\VCF-CA-Preparation",
    [switch]$InstallMissingWebRoles,
    [switch]$Apply,
    [switch]$RestartServices
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param([string]$File, [string[]]$Arguments)
    $result = & $File @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "$File failed ($LASTEXITCODE): $($result -join [Environment]::NewLine)" }
    $result
}
function Get-AdAttribute {
    param($Object, [string]$Name)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return ,$property.Value }
    return $null
}
function Get-TemplateEntry {
    param([string]$Dn)
    $entry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$DomainController/$Dn")
    $entry.Options.SecurityMasks = [System.DirectoryServices.SecurityMasks]::Dacl
    $null = $entry.NativeObject
    return $entry
}
function Set-TemplatePermissions {
    param([string]$Dn, [System.Security.Principal.SecurityIdentifier]$AccountSid)
    $entry = Get-TemplateEntry $Dn
    try {
        $acl = $entry.ObjectSecurity
        # Dedicated template only: preserve administrative ACLs, remove broad
        # Enroll/Autoenroll grants inherited from the source/default container.
        $acl.SetAccessRuleProtection($true, $true)
        $enroll = [guid]'0e10c968-78fb-11d2-90d4-00c04f79dc55'
        $autoenroll = [guid]'a05b8cc2-17bc-4802-a710-e7c15ab866a2'
        foreach ($rule in @($acl.GetAccessRules($true,$true,[System.Security.Principal.SecurityIdentifier]))) {
            if ($rule.IdentityReference -eq $AccountSid) {
                if ($rule.AccessControlType -eq 'Deny') { throw 'Existing template denies access to the service account; review its ACL manually.' }
                $acl.RemoveAccessRuleSpecific($rule)
            } elseif ($rule.AccessControlType -eq 'Allow' -and
                ($rule.ActiveDirectoryRights -band [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight)) {
                if ($rule.ObjectType -in @($enroll,$autoenroll)) {
                    $acl.RemoveAccessRuleSpecific($rule)
                } elseif ($rule.ObjectType -eq [guid]::Empty -and
                    $rule.ActiveDirectoryRights -ne [System.DirectoryServices.ActiveDirectoryRights]::GenericAll) {
                    throw 'Template has an unscoped extended-right grant; review before configuring.'
                }
            }
        }
        $acl.AddAccessRule([System.DirectoryServices.ActiveDirectoryAccessRule]::new(
            $AccountSid, [System.DirectoryServices.ActiveDirectoryRights]::GenericRead,
            [System.Security.AccessControl.AccessControlType]::Allow))
        $acl.AddAccessRule([System.DirectoryServices.ActiveDirectoryAccessRule]::new(
            $AccountSid, [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
            [System.Security.AccessControl.AccessControlType]::Allow, $enroll))
        $entry.ObjectSecurity = $acl
        $entry.CommitChanges()
    } finally { $entry.Dispose() }
}
function Get-CaSecurityWithAccount {
    param([byte[]]$Bytes, [System.Security.Principal.SecurityIdentifier]$AccountSid)
    $sd = [System.Security.AccessControl.RawSecurityDescriptor]::new($Bytes,0)
    if ($null -eq $sd.DiscretionaryAcl) { throw 'CA has a null DACL; refusing to modify it.' }
    for ($i = $sd.DiscretionaryAcl.Count - 1; $i -ge 0; $i--) {
        $ace = $sd.DiscretionaryAcl[$i]
        if ($ace -is [System.Security.AccessControl.KnownAce] -and $ace.SecurityIdentifier -eq $AccountSid) {
            if ($ace.IsInherited -or $ace.AceType -ne [System.Security.AccessControl.AceType]::AccessAllowed) {
                throw 'CA account has inherited, denied or special ACEs. Review manually.'
            }
            $sd.DiscretionaryAcl.RemoveAce($i)
        }
    }
    # CA_ACCESS_OFFICER (2) | CA_ACCESS_ENROLL (512). No Manage CA grant.
    $newAce = [System.Security.AccessControl.CommonAce]::new(
        [System.Security.AccessControl.AceFlags]::None,
        [System.Security.AccessControl.AceQualifier]::AccessAllowed,514,$AccountSid,$false,$null)
    $insert = 0
    while ($insert -lt $sd.DiscretionaryAcl.Count -and
        $sd.DiscretionaryAcl[$insert].AceType -eq [System.Security.AccessControl.AceType]::AccessDenied) { $insert++ }
    $sd.DiscretionaryAcl.InsertAce($insert,$newAce)
    $output = New-Object byte[] $sd.BinaryLength
    $sd.GetBinaryForm($output,0)
    return ,$output
}

if ($PSVersionTable.PSEdition -ne 'Desktop') { throw 'Use Windows PowerShell 5.1 (powershell.exe), not PowerShell 7.' }
Import-Module ServerManager
Import-Module ActiveDirectory
Import-Module ADCSAdministration
if (-not $DomainController) { $DomainController = (Get-ADDomainController -Discover -Writable).HostName }
$ad = @{ Server = $DomainController }
$computer = Get-CimInstance Win32_ComputerSystem
if (-not $computer.PartOfDomain) { throw 'The CA must be domain joined.' }
$caBase = 'HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration'
$caName = (Get-ItemProperty -LiteralPath $caBase).Active
if (-not $caName) { throw 'An existing, configured CA is required.' }
$caPath = Join-Path $caBase $caName
$caState = Get-ItemProperty -LiteralPath $caPath
if ($caState.CAType -notin @(0,1)) { throw 'Only an Enterprise Root or Enterprise Subordinate CA is supported.' }
if ((Get-Service CertSvc).Status -ne 'Running') { throw 'CertSvc must be running before preflight.' }
$caConfig = "$($computer.DNSHostName).$($computer.Domain)\$caName"
$accountName = ($ServiceAccount -split '\\')[-1]
if ($accountName -match '@') {
    $user = Get-ADUser -Filter { UserPrincipalName -eq $accountName } -Properties Enabled,MemberOf,PrimaryGroupID @ad
} else {
    $user = Get-ADUser -Identity $accountName -Properties Enabled,MemberOf,PrimaryGroupID @ad
}
if (-not $user -or -not $user.Enabled) { throw 'Supply an existing enabled dedicated AD user in the CA domain.' }
$domain = Get-ADDomain @ad
if ($domain.DNSRoot -ne $computer.Domain -or $user.SID.AccountDomainSid.Value -ne $domain.DomainSID.Value) {
    throw 'Service account, selected domain controller and CA must be in the same domain.'
}
if ($ServiceAccount -match '\\') {
    $resolvedSid = ([System.Security.Principal.NTAccount]::new($ServiceAccount)).Translate([System.Security.Principal.SecurityIdentifier])
    if ($resolvedSid.Value -ne $user.SID.Value) { throw 'Service account name resolves to a different SID.' }
}
$sid = [System.Security.Principal.SecurityIdentifier]$user.SID
if ($user.PrimaryGroupID -ne 513 -and -not ($user.MemberOf -contains "CN=Domain Users,CN=Users,$($domain.DistinguishedName)")) {
    throw 'The account must have Domain Users membership.'
}
$root = Get-ADRootDSE @ad
$pki = "CN=Public Key Services,CN=Services,$($root.ConfigurationNamingContext)"
$templatesDn = "CN=Certificate Templates,$pki"
$templateDn = "CN=$TemplateName,$templatesDn"
$source = Get-ADObject -Identity "CN=WebServer,$templatesDn" -Properties * @ad
$existing = @(Get-ADObject -SearchBase $templatesDn -SearchScope OneLevel -LDAPFilter "(cn=$TemplateName)" -Properties * @ad)
$marker = 'Managed by Configure-VcfMicrosoftCA.ps1; dedicated VCF template'
if ($existing.Count -gt 0 -and $existing[0].description -ne $marker) {
    throw "Template $TemplateName already exists and is not owned by this script. Use a new dedicated name."
}
$publishedBefore = @(Get-CATemplate | Select-Object -ExpandProperty Name)
$securityBefore = [byte[]]$caState.Security
$securityAfter = Get-CaSecurityWithAccount $securityBefore $sid
$requiredFeatures = @('ADCS-Cert-Authority','ADCS-Web-Enrollment','Web-Basic-Auth','Web-Scripting-Tools')
$missing = @(Get-WindowsFeature -Name $requiredFeatures | Where-Object { -not $_.Installed } | Select-Object -ExpandProperty Name)
if ($missing -contains 'ADCS-Cert-Authority') { throw 'Configure an enterprise CA before running this script.' }
Write-Host "CA: $caConfig`nDC: $DomainController`nAccount: $($user.SamAccountName) [$sid]"
Write-Host "Plan: install missing web roles [$($missing -join ', ')]; configure CertSrv; create/update $TemplateName; publish; set CA and template ACLs."
Write-Host 'Template: 2008 R2/Windows 7 compatibility; supply subject; no Server Authentication policy; Basic Constraints CA=false; add nonrepudiation.'
Write-Host 'CA account direct rights: Issue/Manage Certificates + Request Certificates. Template direct rights: Read + Enroll.'
if (-not $Apply -or $WhatIfPreference) {
    Write-Host 'PREVIEW ONLY. No changes made. Apply requires an existing valid IIS HTTPS binding on the chosen site.'
    return
}
if ($missing.Count -gt 0 -and -not $InstallMissingWebRoles) { throw 'Missing web roles. Rerun with -InstallMissingWebRoles.' }
if (-not $PSCmdlet.ShouldProcess($caConfig,'Configure IIS, dedicated AD template and CA permissions')) { return }

$backup = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory -Path $backup -Force | Out-Null
# Backups may contain IIS configuration; restrict to local administrators/SYSTEM.
$folderAcl = [System.Security.AccessControl.DirectorySecurity]::new()
$folderAcl.SetAccessRuleProtection($true,$false)
foreach ($principal in @('S-1-5-18','S-1-5-32-544')) {
    $folderAcl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
        [System.Security.Principal.SecurityIdentifier]::new($principal), 'FullControl',
        'ContainerInherit, ObjectInherit','None','Allow'))
}
Set-Acl -LiteralPath $backup -AclObject $folderAcl
[IO.File]::WriteAllBytes((Join-Path $backup 'ca-security.bin'),$securityBefore)
$publishedBefore | Export-Clixml (Join-Path $backup 'published-templates.xml')
$source | Export-Clixml (Join-Path $backup 'source-webserver.xml')
$existing | Export-Clixml (Join-Path $backup 'previous-template.xml')
if ($existing.Count) {
    $beforeEntry = Get-TemplateEntry $templateDn
    try { $beforeEntry.ObjectSecurity.GetSecurityDescriptorSddlForm('Access') | Set-Content (Join-Path $backup 'template-dacl.sddl') }
    finally { $beforeEntry.Dispose() }
}
$manifest = [ordered]@{ CA=$caConfig; CARegistryPath=$caPath; TemplateDN=$templateDn; NewTemplate=($existing.Count -eq 0); DC=$DomainController; Site=$SiteName; MissingFeatures=$missing; OidDN=$null }
$manifest | ConvertTo-Json | Set-Content (Join-Path $backup 'manifest.json')
Write-Host "Recovery files: $backup"
try {
    if ($missing.Count) {
        $install = Install-WindowsFeature -Name $missing -IncludeManagementTools
        if (-not $install.Success -or $install.RestartNeeded -eq 'Yes') { throw 'Role installation failed or requires reboot. Reboot if required, then rerun.' }
    }
    Import-Module WebAdministration
    Import-Module ADCSDeployment
    if (-not (Test-Path "IIS:\Sites\$SiteName")) { throw "IIS site $SiteName does not exist." }
    $appcmd = "$env:windir\System32\inetsrv\appcmd.exe"
    $iisBackupName = 'VCF-CA-' + (Split-Path $backup -Leaf)
    Invoke-Native $appcmd @('add','backup',$iisBackupName) | Out-Null
    $iisBackupName | Set-Content (Join-Path $backup 'iis-backup-name.txt')
    $https = @(Get-WebBinding -Name $SiteName -Protocol https | Where-Object { $_.certificateHash })
    if ($https.Count -eq 0) { throw 'Provision a valid HTTPS binding and server certificate on the selected IIS site, then rerun. No TLS binding was created.' }
    foreach ($binding in $https) {
        $hash = $binding.certificateHash
        if ($hash -is [byte[]]) { $hash = [BitConverter]::ToString($hash).Replace('-','') }
        $cert = Get-Item "Cert:\LocalMachine\$($binding.certificateStoreName)\$hash"
        if (-not $cert.HasPrivateKey -or $cert.NotAfter -le (Get-Date) -or $cert.NotBefore -gt (Get-Date)) {
            throw 'An HTTPS binding has an expired/not-yet-valid certificate or lacks its private key.'
        }
    }
    if (-not (Test-Path "IIS:\Sites\$SiteName\CertSrv")) {
        if ($SiteName -ne 'Default Web Site') { throw 'For a custom site, configure Web Enrollment on that site before running.' }
        Install-AdcsWebEnrollment -CAConfig $caConfig -Force | Out-Null
    }
    if (-not (Test-Path "IIS:\Sites\$SiteName\CertSrv")) { throw 'CertSrv application missing after Web Enrollment configuration.' }
    $location = "$SiteName/CertSrv"
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $location -Filter 'system.webServer/security/access' -Name sslFlags -Value 'Ssl'
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $location -Filter 'system.webServer/security/authentication/basicAuthentication' -Name enabled -Value $true
    # HTTPS-only and no anonymous access to the enrollment application.
    Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $location -Filter 'system.webServer/security/authentication/anonymousAuthentication' -Name enabled -Value $false

    # Clone only template configuration, never directory identity/system attributes.
    $attrs = @{}
    foreach ($name in @('flags','revision','pKIDefaultKeySpec','pKIExpirationPeriod','pKIOverlapPeriod',
        'pKICriticalExtensions','pKIDefaultCSPs','pKIKeyUsage','msPKI-Minimal-Key-Size',
        'msPKI-Private-Key-Flag','msPKI-Enrollment-Flag','msPKI-Certificate-Name-Flag',
        'msPKI-RA-Signature','pKIExtendedKeyUsage','msPKI-Certificate-Application-Policy')) {
        $value = Get-AdAttribute $source $name
        if ($null -ne $value -and @($value).Count -gt 0) {
            if ($value -is [byte[]]) { $attrs[$name] = [byte[]]$value }
            elseif ($value -is [Microsoft.ActiveDirectory.Management.ADPropertyValueCollection]) {
                if ($value.Count -eq 1) { $attrs[$name] = $value[0] } else { $attrs[$name] = @($value) }
            } else { $attrs[$name] = $value }
        }
    }
    $attrs['displayName'] = $TemplateDisplayName
    $attrs['description'] = $marker
    $attrs['msPKI-Template-Schema-Version'] = 3
    $attrs['msPKI-Template-Minor-Revision'] = 1
    $attrs['revision'] = 100
    $attrs['msPKI-Private-Key-Flag'] = ([int]$source.'msPKI-Private-Key-Flag' -band 0xF0F0FFFF) -bor 0x03030000
    $attrs['msPKI-Certificate-Name-Flag'] = 1
    $attrs['msPKI-Enrollment-Flag'] = ([int]$source.'msPKI-Enrollment-Flag' -bor 0x8000)
    $sourceKeyUsage = [byte[]]$source.pKIKeyUsage
    $keyUsage = [byte[]]$sourceKeyUsage.Clone()
    $keyUsage[0] = $keyUsage[0] -bor 0x40
    $attrs['pKIKeyUsage'] = $keyUsage
    $attrs['msPKI-RA-Signature'] = 0
    $clear = @()
    foreach ($policy in @('pKIExtendedKeyUsage','msPKI-Certificate-Application-Policy')) {
        $policies = @(Get-AdAttribute $source $policy | ForEach-Object { $_ } | Where-Object { $_ -and $_ -ne '1.3.6.1.5.5.7.3.1' })
        if ($policies.Count) { $attrs[$policy] = $policies } else { $attrs.Remove($policy); $clear += $policy }
    }
    if ($existing.Count -eq 0) {
        $oidContainer = "CN=OID,$pki"
        $forestOid = (Get-ADObject -Identity $oidContainer -Properties 'msPKI-Cert-Template-OID' @ad).'msPKI-Cert-Template-OID'
        if (-not $forestOid) { throw 'Forest enterprise OID prefix was not found.' }
        $oidName = [guid]::NewGuid().ToString('N')
        $oid = "$forestOid.$(Get-Random -Minimum 10000000 -Maximum 2147483647).$(Get-Random -Minimum 10000000 -Maximum 2147483647)"
        $manifest.OidDN = "CN=$oidName,$oidContainer"
        $manifest | ConvertTo-Json | Set-Content (Join-Path $backup 'manifest.json')
        New-ADObject -Name $oidName -Type 'msPKI-Enterprise-Oid' -Path $oidContainer -OtherAttributes @{
            'displayName'=$TemplateDisplayName; 'flags'=1; 'msPKI-Cert-Template-OID'=$oid
        } @ad
        $attrs['msPKI-Cert-Template-OID'] = $oid
        New-ADObject -Name $TemplateName -Type 'pKICertificateTemplate' -Path $templatesDn -OtherAttributes $attrs @ad
    } else {
        $attrs['msPKI-Template-Minor-Revision'] = [int]$existing[0].'msPKI-Template-Minor-Revision' + 1
        Set-ADObject -Identity $templateDn -Replace $attrs @ad
        $clearPresent = @($clear | Where-Object { $null -ne (Get-AdAttribute $existing[0] $_) })
        if ($clearPresent.Count) { Set-ADObject -Identity $templateDn -Clear $clearPresent @ad }
    }
    Set-TemplatePermissions $templateDn $sid
    Set-ItemProperty -LiteralPath $caPath -Name Security -Value $securityAfter
    # Additive publication: never replaces the CA's existing template list.
    if ($TemplateName -notin $publishedBefore) { Add-CATemplate -Name $TemplateName -Force }
    if ($RestartServices) {
        Restart-Service CertSvc
        Stop-WebSite -Name $SiteName
        Start-WebSite -Name $SiteName
    } else {
        Write-Warning 'Changes are saved. Restart CertSvc and the selected IIS site in a maintenance window, then validate.'
    }
    $after = Get-ADObject -Identity $templateDn -Properties * @ad
    if ($after.'msPKI-Template-Schema-Version' -ne 3 -or
        $after.'msPKI-Certificate-Name-Flag' -ne 1 -or
        -not ([int]$after.'msPKI-Enrollment-Flag' -band 0x8000) -or
        ([byte[]]$after.pKIKeyUsage)[0] -ne $keyUsage[0] -or
        @(Get-AdAttribute $after 'pKIExtendedKeyUsage' | ForEach-Object { $_ }) -contains '1.3.6.1.5.5.7.3.1') { throw 'Template attribute verification failed.' }
    $basic = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Location $location -Filter 'system.webServer/security/authentication/basicAuthentication' -Name enabled
    if (-not $basic.Value) { throw 'IIS Basic authentication verification failed.' }
    $storedSecurity = [byte[]](Get-ItemProperty -LiteralPath $caPath).Security
    if ([Convert]::ToBase64String($storedSecurity) -ne [Convert]::ToBase64String($securityAfter)) { throw 'CA security verification failed.' }
    if ($TemplateName -notin @(Get-CATemplate | Select-Object -ExpandProperty Name)) { throw 'Template publication verification failed. Check AD replication and retry.' }
    $report = [ordered]@{ CA=$caConfig; Template=$TemplateName; Account=$user.UserPrincipalName;
        Backup=$backup; RestartRequested=[bool]$RestartServices; Result='Configuration saved; authenticated enrollment must still be tested' }
    $report | ConvertTo-Json | Set-Content (Join-Path $backup 'result.json')
    [pscustomobject]$report
} catch {
    Write-Warning "Configuration stopped; previous steps may already be applied. Recovery files: $backup"
    throw
}
