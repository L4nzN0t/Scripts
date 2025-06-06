<#
.SYNOPSIS

Retrieve the last version of the catalog.xml from Dell.

Author: Thomas Rodrigues (@L4nzN0t_)

VERSION 1.0.0

.DESCRIPTION

Get the last version of the catalog.xml file. This file has the the firmware combatility matrix of Dell servers against VMware vSphere.

.PARAMETER ESXIVersion

Set the ESXI Version for download.

.PARAMETER OutFile

Path to download catalog file.

.LINK
https://www.dell.com/support/kbdoc/pt-br/000225259/firmware-catalog-for-dell-customized-vmware-esxi-7-x-images
https://www.dell.com/support/kbdoc/en-in/000225273/firmware-catalog-for-dell-customized-vmware-esxi-8-x-images

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]
    [ValidateSet("vSphere-07", "vSphere-08")]
    $ESXIVersion,
    [string]
    $PathFile
)

try {

    if ($ESXIVersion -eq "vSphere-07") {
        $url = "https://www.dell.com/support/kbdoc/en-in/000225273/firmware-catalog-for-dell-customized-vmware-esxi-8-x-images"
    }
    elseif ($ESXIVersion -eq "vSphere-08") {
        $url = "https://www.dell.com/support/kbdoc/pt-br/000225259/firmware-catalog-for-dell-customized-vmware-esxi-7-x-images"
    }


    if ($PathFile)
    {
        if ((Test-Path $PathFile))
        {
            $WORKSPACE_FOLDER = $PathFile
        }
        else {
            $e = New-Object -TypeName System.IO.DirectoryNotFoundException -ArgumentList "Path does not exist: $path"
            throw $e
        }
    }
    else {
        $WORKSPACE_FOLDER = $PSScriptRoot
    }

    $defaultCatalogFile = "$WORKSPACE_FOLDER\Catalog.xml"

    if ((Test-Path $defaultCatalogFile))
    {
        if ((Get-Content $defaultCatalogFile).Length -eq 0) {
            Write-Host ""
            Write-Host "[INFO] - No catalog found!" -ForegroundColor Yellow
        }
        else {
            [xml] $xml = Get-Content $defaultCatalogFile
            $catalogDate = [datetime] $xml.Manifest.dateTime
            Write-Host ""
            Write-Host "[SUCCESSFUL] - Catalog Default!" -ForegroundColor Yellow
            Write-Host "[SUCCESSFUL] - Last update: $catalogDate" -ForegroundColor Yellow
        }

    } else {
        Write-Host ""
        Write-Host "[INFO] - No catalog found!" -ForegroundColor Yellow
        $defaultCatalogFile = New-Item -Type File -Path $WORKSPACE_FOLDER -Name Catalog.xml
    }

    $pageContent = Invoke-WebRequest -Uri $url
    $links = $pageContent.Links | Where-Object { ($_.href -match "FOLDER*") -and ($_.href -like "*ESXi_Catalog.xml.gz") }

    $folder_ids = @()
    foreach ($link in $links) {
        if ($link.href -match "FOLDER\d+M") {
            $folder_ids += $matches[0]
        }
    }

    $latest_folder = $folder_ids | Sort-Object -Descending | Select-Object -First 1
    $latestUrl = $links | Where-Object { $_.href -match $latest_folder }
    $outputFile = "$WORKSPACE_FOLDER\ESXi_Catalog.xml.gz"
    $headers = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" }
    Invoke-WebRequest $latestUrl.href -OutFile $outputFile -Headers $headers

    $compressedFile = "$WORKSPACE_FOLDER\ESXi_Catalog.xml.gz"
    $decompressedFile = "$WORKSPACE_FOLDER\ESXi_Catalog.xml"

    $inputStream = [System.IO.File]::OpenRead($compressedFile)
    $outputStream = [System.IO.File]::Create($decompressedFile)

    $gzipStream = New-Object System.IO.Compression.GzipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)
    $gzipStream.CopyTo($outputStream)

    $gzipStream.Close()
    $outputStream.Close()
    $inputStream.Close()

    [xml] $xml = Get-Content $decompressedFile

    $catalogDate = [datetime] $xml.Manifest.dateTime

    Write-Host ""
    Write-Host "[SUCCESSFUL] - Catalog Updated !" -ForegroundColor Green
    Write-Host "[SUCCESSFUL] - Last update: $catalogDate" -ForegroundColor Green

    Move-Item -Path $decompressedFile -Destination $defaultCatalogFile -Force -Confirm:$false
    Remove-Item -Path $compressedFile
}
catch {
    Write-Error $_
    exit 1
}
