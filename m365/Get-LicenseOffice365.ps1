<#
.SYNOPSIS

List the users and assigned licenses in M365

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: Microsoft Graph SDK

VERSION 1.0.0

.DESCRIPTION

Get all users of m365 enviroment and check which licenses they have.

#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    
)


try {
    Clear-Host
    # Ensure the Microsoft Graph module is installed and loaded
    Import-Module Microsoft.Graph -Scope CurrentUser
    
    Connect-MgGraph -NoWelcome -Scopes "User.Read.All","Group.Read.All"
    Write-Verbose "Connected to Microsoft Graph API"
    
    $WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
    $WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName

}
catch
{
    Write-Error $_
}


# SCRIPT EXECUTION
try {
    $properties = @{
        DisplayName = ''
        UserPrincipalName = ''
        License = @()
    }

    $users = Get-MgUser -Filter 'assignedLicenses/$count ne 0' -ConsistencyLevel eventual -CountVariable unlicensedUserCount -All
    Start-Sleep -Seconds 5
    Write-Host ""
    Write-Verbose "Find $($users.Count) users with valid licenses..."
    Write-Host ""

    $usersWithLicenses = [System.Collections.ArrayList]::new()
    $i = 0
    foreach($user in $users)
    {
        $userLicenses = Get-MgUserLicenseDetail -UserId $user.Id
        $tempObj = New-Object psobject -Property $properties
        $tempObj.DisplayName = $user.DisplayName
        $tempObj.UserPrincipalName = $user.UserPrincipalName
        $tempObj.License.Clear()
        foreach ($userLicense in $userLicenses) {
            $license = switch -Regex ($userLicense.SkuPartNumber) {
                "VISIOCLIENT"   { "Visio Plan 2" }
                "STREAM"    { "Microsoft Stream" }
                "VIRTUAL_AGENT_USL" { "Power Virtual Agent User License" }
                "POWER_BI_INDIVIDUAL_USER"  { "Power BI" }
                "FLOW_PER_USER" { "Power Automate per user plan" }
                "Dynamics_365_Field_Service_Enterprise_viral_trial" { "Dynamics 365 Field Service Viral Trial" }
                "VIRTUAL_AGENT_BASE"    { "Power Virtual Agent" }
                "POWER_BI_PRO"  { "Power BI Pro" }
                "WINDOWS_STORE" { "Windows Store for Business" }
                "POWERAPPS_PER_APP_IW"  { "PowerApps per app baseline access" }
                "PROJECTESSENTIALS" { "Project Online Essentials" }
                "DYN365_CUSTOMER_VOICE_ADDON"   { "Dynamics 365 Customer Voice Additional Responses" }
                "FLOW_FREE" { "Microsoft Power Automate Free" }
                "IDENTITY_THREAT_PROTECTION"    { "Microsoft 365 E5 Security" }
                "PROJECTPREMIUM"    { "Project Online Premium" }
                "CCIBOTS_PRIVPREV_VIRAL"    { "Power Virtual Agents Viral Trial" }
                "PBI_PREMIUM_P1_ADDON"  { "Power BI Premium P1" }
                "FORMS_PRO" { "Dynamics 365 Customer Voice Trial" }
                "POWERAPPS_VIRAL"   { "Microsoft Power Apps Plan 2 Trial" }
                "CDS_FILE_CAPACITY" { "Common Data Service for Apps File Capacity" }
                "DYN365_ENTERPRISE_P1_IW"   { "Dynamics 365 P1 Tria for Information Workers" }
                "POWER_BI_STANDARD" { "Microsoft Fabric (Free)" }
                "DYN365_CUSTOMER_VOICE_BASE"    { "Dynamics 365 Customer Voice" }
                "Power_Pages_vTrial_for_Makers" { "Power Pages vTrial for Makers" }
                "POWERAPPS_PER_USER"    { "Power Apps per user plan" }
                "POWERAPPS_PORTALS_LOGIN_T3"    { "Power Apps Portals login capacity add-on Tier 3" }
                "SPE_E3"    { "Microsoft 365 E3" }
                "PROJECTPROFESSIONAL"   { "Project Plan 3" }
                "CDS_DB_CAPACITY"   { "Common Data Service Database Capacity" }
                "Teams_Premium_(for_Departments)"   { "Teams Premium (for Departments)" }
                "CDS_LOG_CAPACITY"  { "Common Data Service Log Capacity" }
                "VISIO_PLAN1_DEPT"  { "Visio Plan 1" }
                "POWERAPPS_DEV" { "Microsoft Power Apps for Developer" }
                # Adicione outros casos conforme necessário para diferentes tipos de licenças
                Default             { $userLicense.SkuPartNumber }
            }
            $tempObj.License += $license
        }
        Write-Host "$i - User computed - $($user.DisplayName)" -ForegroundColor DarkGreen
        $i++
        $usersWithLicenses.Add($tempObj) | Out-Null
    }

    Start-Sleep -Seconds 5
    Write-Verbose "Preparing to export data..."

    Start-Sleep -Seconds 5

    # Exibe os resultados formatados em uma tabela
    $usersWithLicenses | ForEach-Object {
        $_.License = ($_.License -join ", ")
        $_
    } | Export-Csv "$WORKSPACE_FOLDER\licenses_users_m365.csv"
    Write-Host "Data exported to $($WORKSPACE_FOLDER)\LicensesOffice365.csv" -ForegroundColor DarkRed

} catch {
    Write-Error $_
}