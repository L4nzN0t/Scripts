function FunctionName {
    <#
    .SYNOPSIS

    Gets the current user who is authenticating to LDAP

    Author: Lee Christensen (@tifkin_)
    License: BSD 3-Clause
    Required Dependencies: None

    .DESCRIPTION

    Gets the current user who is authenticating to LDAP. It does so by using the
    LDAP_SERVER_WHO_AM_I_OID extended operation (MS-ADTS 3.1.1.3.4.2.4
    LDAP_SERVER_WHO_AM_I_OID - https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/faf0b8c6-8c59-439f-ac62-dc4c078ed715).

    .PARAMETER Server

    LDAP server to connect to (likely a Domain Controller)

    .PARAMETER AuthType

    Protocol to use during authentication

    .PARAMETER Certificate

    Certificate (.pfx file) to use during authentication

    .PARAMETER Certificate

    Certificate file's password

    .PARAMETER UseSSL

    Whether to use SSL/TLS (LDAPS) when connecting

    .PARAMETER Signing

    Connect with Signing enabled

    .PARAMETER Sealing

    Connect with Sealing enabled

    .PARAMETER VerifyServerCertificate

    Verify that the server certificate is trusted

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

            [Parameter(Mandatory=$true, ParameterSetName = 'PasswordAuth')]
            [ValidateNotNullOrEmpty()]
            [string]
            $Domain,

            [Parameter(Mandatory=$true, ParameterSetName = 'PasswordAuth')]
            [ValidateNotNullOrEmpty()]
            [string]
            $Username,

            [Parameter(Mandatory=$true, ParameterSetName = 'PasswordAuth')]
            [string]
            $Password,

            [Parameter(Mandatory=$false)]
            [switch]
            $UseSSL = $false,

            [Parameter(Mandatory=$false)]
            [switch]
            $Signing = $false,

            [Parameter(Mandatory=$false)]
            [switch]
            $Sealing = $false,

            [Parameter(Mandatory=$false)]
            [switch]
            $VerifyServerCertificate
        )

        try {

        } catch {

        } finally {

        }
    }
