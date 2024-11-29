<#

.SYNOPSIS

Get GPO where cpassword attribute was configured. Should be executed in a domain controller.

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: None

VERSION: 1.0.0


.DESCRIPTION

Search all GPOs in the domain and check which ones have the cpassword attribute configured.

.LINK
https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/2c15cbf0-f086-4c74-8b70-1f2fa45dd4be?redirectedfrom=MSDN
https://support.microsoft.com/en-us/topic/ms14-025-vulnerability-in-group-policy-preferences-could-allow-elevation-of-privilege-may-13-2014-60734e15-af79-26ca-ea53-8cd617073c30

#>


$files = Get-ChildItem -Path C:\Windows\SYSVOL*\domain\Policies -Include groups.xml -Recurse
$global:allobj = @()
$count = 0
Function Decrypt
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
    return $plaintext
}

Write-Host ""
Write-Host "Searching in GPO's ... " -ForegroundColor Cyan
Write-Host ""

foreach ($file in $files)
{

    try {
        $xml = [xml] (Get-Content $file.FullName)
        if ($file.FullName -match '{[0-9A-Fa-f\-]+}') {
            $guid = $matches[0]
        }
        $gpo = [xml](Get-GPOReport -Guid $guid -ReportType XML -ErrorAction stop)
        Write-Host "INFO! GPO Found: '$($gpo.GPO.Name)'" -ForegroundColor Yellow -BackgroundColor Black

        if ($xml.Groups.User.Properties.cpassword)
        {
            $password = Decrypt $xml.Groups.User.Properties.cpassword
            $obj = [PSCustomObject]@{
                GPOName = $gpo.GPO.Name
                FileName = $file.FullName
                User = $xml.Groups.User.name
                CPassword = $xml.Groups.User.Properties.cpassword
                DecryptedPassword =  $password
                Linked = ''
                Empty = $gpo.GPO.isEmpty
            }
            if ($gpo.GPO.LinksTo)
            {
                $obj.Linked = "True"
            } else
            {
                $obj.Linked = "False"
            }
            $global:allobj += $obj
        } else {
            $count += 1
        }
    } catch
    {
        Continue
    }
}
if ($count -eq $files.Count)
{
    Write-Host ""
    Write-Host "INFO! NO GPO had cpassword attribute enabled" -ForegroundColor Green -BackgroundColor Black
} else
{
    Write-Host ""
    Write-Host "****** SUMMARY ******" -ForegroundColor Cyan
    $global:allobj | Format-Table GPOName, User, DecryptedPassword, Linked, Empty
}
