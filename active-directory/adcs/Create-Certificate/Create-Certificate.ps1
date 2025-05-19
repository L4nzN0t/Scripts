<#
.SYNOPSIS

Create a certificate and signed using a Windows CA

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: Powershell 7 or higher

VERSION 1.0.0

.DESCRIPTION

Description

.PARAMETER Request

Request file with config to create the CSR.

#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
Param(
    [Parameter(Mandatory=$true)]
    [string]
    $Request
)

    
try {
    Clear-Host
    
    if (!($PSVersionTable.PSVersion.Major -ge 7))
    {
        throw "The script should be executed in powershell 7 or higher."
    }
    
    $WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
    $WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName
    
    $id = (Get-Random)
    $CA = ((certutil -dump | findstr "Config") -split ":")[-1].trim() -replace '"',''
    $CA = $CA -replace '`',''
    $CA = $CA -replace "'",""
    $pKEY = "$WORKSPACE_FOLDER\$id-private.key"

    if ((Test-Path $Request))
    {
        $cerINF = $Request
    }
    else {
        throw "Request.inf file not found."
    }

    $csRequest = "$WORKSPACE_FOLDER\$id-request.csr"
    $cERT = "$WORKSPACE_FOLDER\$id-cert.crt"
    $rESP = "$WORKSPACE_FOLDER\$id-cert.rsp"  
    $PFXcert = "$WORKSPACE_FOLDER\$id-cert.pfx"    
}
catch
{
    Write-Error $_
    exit 1
}


# SCRIPT EXECUTION

Function New-PrivateKey {
    ## CREATE PRIVATE KEY
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
    $rsa.ExportPkcs8PrivateKeyPem() | Out-File -FilePath $pKEY

    # CHECK IF PRIVATE KEY IS OK
    $rsaValidate = [System.Security.Cryptography.RSA]::Create()
    $rsaValidate.ImportFromPem((Get-Content $pKEY -Raw)) # The method itself fails if the private.key isn`t correct
    Write-Host "[SUCCESS] Private key created" -ForegroundColor Green
}

Function Save-PrivateKey {
    Write-Host "[SUCCESS] Private Key saved in: $pKEY" -ForegroundColor Green
    Write-Host ""
}
Function Save-CSR {
    Write-Host "[SUCCESS] CSR saved in: $csRequest" -ForegroundColor Green
    Write-Host ""
}
Function Save-Cert {
    Write-Host "[SUCCESS] CRT certificate file saved in: $cERT" -ForegroundColor Green
    Write-Host ""
}
Function Save-PFXCert {
    Write-Host "[SUCCESS] PFX certificate file saved in: $PFXcert" -ForegroundColor Green
    Write-Host ""
}

try {
    $CAName = ($CA -split "\.")[0]
    if (!($CAName -eq $env:COMPUTERNAME)) {
        Write-Host ""
        Write-Host "[WARNING] The script is not running in CA Server." -ForegroundColor Yellow
        Write-Host "[WARNING] The certificate will not be signed." -ForegroundColor Yellow
        Write-Host "[WARNING] Only the .csr file and private key will be generate." -ForegroundColor Yellow
        Write-Host ""
        $opt = Read-Host "Do you want to proceed? (Y/N)"
        if ($opt.ToUpper() -eq "Y") {
            ## CALL FUNCTION TO CREATE PRIVATE KEY
            New-PrivateKey

            ## CREATE CSR
            certreq.exe -new $cerINF $csRequest
            Write-Host "[SUCCESS] CSR file created" -ForegroundColor Green

            # SAVE CSR and PRIVATE KEY FILES
            Save-PrivateKey
            Save-CSR
        } 
        else {
            exit 0
        }
    } 
    else {
        Write-Host ""
        Write-Host "[INFO] The script is running in CA Server."
        Write-Host "[INFO] CA Found: $CA"
        
        ## CALL FUNCTION TO CREATE PRIVATE KEY
        New-PrivateKey

        ## CREATE CSR
        certreq.exe -new $cerINF $csRequest | Out-Null
        Write-Host "[SUCCESS] CSR file created" -ForegroundColor Green

        # SUBMIT THE CSR TO CA 
        Get-CATemplate | Sort-Object Name | Format-Table Name
        ## LIST THE CERTIFICATE TEMPLATES
        
        $oop = Read-Host "[INFO] Type the template name"
        certreq.exe -submit -attrib "CertificateTemplate:$oop" -q $csRequest $cERT
        Write-Host "[SUCCESS] Certificate created" -ForegroundColor Green

        ## INSTALL THE CERTIFICATE IN MACHINE
        certreq.exe -accept $cERT

        $serialNUMBER = (certutil.exe $cERT | findstr "Serial Number:") -replace "Serial Number:\s*",""
        $certTarget = Get-ChildItem -Path cert:\LocalMachine\my | Where-Object {$_.SerialNumber -eq $serialNUMBER }
        
        Write-Host "[INFO] Preparing to export certificate as pfx"
        $password = Read-Host "[INFO] Type the certificate password" -AsSecureString
        Export-PfxCertificate -Cert $certTarget.PSPath -FilePath $PFXcert -Password $password -ErrorAction Stop 
        
        Write-Host "[SUCCESS] Certificate exported" -ForegroundColor Green

        # SAVE CSR and PRIVATE KEY FILES
        Save-PrivateKey
        Save-CSR
        Save-Cert
        Save-PFXCert
    }

} catch {
    Write-Error $_
} finally {
    
}