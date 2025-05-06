<#
.SYNOPSIS

What the script does

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: VMware PowerCLI

VERSION 1.0.0

.DESCRIPTION

Description

.PARAMETER Server

LDAP server to connect to (likely a Domain Controller)

.PARAMETER AuthType

Protocol to use during authentication

.PARAMETER Certificate

Certificate (.pfx file) to use during authentication

#>
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory=$false)]
        [string]
        $Server,

        [Parameter(Mandatory=$false)]
        [ValidateSet('Anonymous','Basic','Negotiate','Ntlm','Digest','Sicily','Dpa','Msn','External','Kerberos')]
        $AuthType,

        [Parameter(Mandatory=$false, ParameterSetName = 'CertAuth')]
        [string]
        $Certificate,

        [Parameter(Mandatory=$false, ParameterSetName = 'CertAuth')]
        [string]
        $CertificatePassword,

        [Parameter(Mandatory=$false)]
        [switch]
        $UseSSL = $false

    )

    
    try {
        # Ensure the VMware PowerCLI module is installed and loaded
        Import-Module VMware.VimAutomation.Core

        Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
        # Connect to each vCenter
        $vCenters = "<vcenter_server01>,<vcenter_server02>,<vcenter_server03>" -split ","
        $WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
        $WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName

        foreach ($vCenter in $vCenters)
        {
            try {
                Connect-VIServer -Server $vCenter -User "user@vsphere.local" -Password "pass" -ErrorAction Stop
            } catch {
                Write-Host "[ERROR] Error connecting to vCenter Server: $_" -ForegroundColor Red
                # exit
            }
        }
    }
    catch
    {
        Write-Error $_
    }

    


    # SCRIPT EXECUTION
    try {
        
    } catch {

    } finally {

    }