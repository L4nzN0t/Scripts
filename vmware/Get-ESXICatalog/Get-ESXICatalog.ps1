<#
.SYNOPSIS

Retrieve the last version of the catalog.xml from Dell.

Author: Thomas Rodrigues (@L4nzN0t_)

VERSION 1.0.0

.DESCRIPTION

Get the last version of the catalog.xml file. This file has the the combatility matrix of Dell firmware server against VMware vSphere.

.PARAMETER ESXIVersion

Set the ESXI Version

.PARAMETER OutFile

Protocol to use during authentication

#LINKS
# https://www.dell.com/support/kbdoc/pt-br/000225259/firmware-catalog-for-dell-customized-vmware-esxi-7-x-images
# https://www.dell.com/support/kbdoc/en-in/000225273/firmware-catalog-for-dell-customized-vmware-esxi-8-x-images

#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]
    [ValidateSet("vSphere-07", "vSphere-08")]
    $ESXIVersion
)
$WORKSPACE_FOLDER = $PSScriptRoot
# $WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName

try {

    if ($ESXIVersion -eq "vSphere-07") {
        $url = "https://www.dell.com/support/kbdoc/en-in/000225273/firmware-catalog-for-dell-customized-vmware-esxi-8-x-images"
    } 
    elseif ($ESXIVersion -eq "vSphere-08") {
        $url = "https://www.dell.com/support/kbdoc/pt-br/000225259/firmware-catalog-for-dell-customized-vmware-esxi-7-x-images"
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
    
    # Baixar o conteúdo da página
    $pageContent = Invoke-WebRequest -Uri $url

    # Encontrar todos os links na página
    $links = $pageContent.Links | Where-Object { ($_.href -match "FOLDER*") -and ($_.href -like "*ESXi_Catalog.xml.gz") }

    # Usar expressão regular para extrair a parte desejada
    $folder_ids = @()
    foreach ($link in $links) {
        if ($link.href -match "FOLDER\d+M") {
            $folder_ids += $matches[0]
        }
    }

    # Encontrar o maior valor de acordo com a sequência numérica
    $latest_folder = $folder_ids | Sort-Object -Descending | Select-Object -First 1

    $latestUrl = $links | Where-Object { $_.href -match $latest_folder }

    # Credenciais (se necessário)
    $cred = Get-Credential

    $outputFile = "$WORKSPACE_FOLDER\ESXi_Catalog.xml.gz"

    # Usar WebClient para baixar o arquivo com autenticação
    $webClient = New-Object System.Net.WebClient
    #$webClient.UseDefaultCredentials = $true
    $webClient.Credentials = $cred
    #$webClients.Headers.Add("X-FORMS_BASED_AUTH_ACCEPTED", "f")
    $webClient.DownloadFile($latestUrl.href, $outputFile)

    # Caminho do arquivo compactado
    $compressedFile = "$WORKSPACE_FOLDER\ESXi_Catalog.xml.gz"

    # Caminho do arquivo descompactado
    $decompressedFile = "$WORKSPACE_FOLDER\ESXi_Catalog.xml"

    # Abrir o arquivo compactado para leitura
    $inputStream = [System.IO.File]::OpenRead($compressedFile)

    # Criar o arquivo descompactado para escrita
    $outputStream = [System.IO.File]::Create($decompressedFile)

    # Criar o GzipStream para descompactação
    $gzipStream = New-Object System.IO.Compression.GzipStream($inputStream, [System.IO.Compression.CompressionMode]::Decompress)

    # Copiar os dados descompactados para o arquivo de saída
    $gzipStream.CopyTo($outputStream)

    # Fechar os streams
    $gzipStream.Close()
    $outputStream.Close()
    $inputStream.Close()

    [xml] $xml = Get-Content $decompressedFile
s
    $catalogDate = [datetime] $xml.Manifest.dateTime

    Write-Host ""
    Write-Host "[SUCCESSFUL] - Catalog Updated !" -ForegroundColor Green
    Write-Host "[SUCCESSFUL] - Last update: $catalogDate" -ForegroundColor Green

    # Mover o arquivo descompactado para a pasta desejada
    Move-Item -Path "ESXi_Catalog.xml" -Destination $defaultCatalogFile -Force -Confirm:$false

    # Remover o arquivo compactado
    Remove-Item -Path $compressedFile
    # Remove-Item -Path $outputFile
}
catch {
    Write-Error $_
    exit 1
}