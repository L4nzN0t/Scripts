########################################################################################################################
# THE SAMPLES DESCRIBED IN THIS DOCUMENT ARE UNDOCUMENTED SAMPLE CODE. THESE SAMPLES ARE PROVIDED "AS IS" WITHOUT
# WARRANTY OF ANY KIND. MICROSOFT FURTHER DISCLAIMS ALL IMPLIED WARRANTIES INCLUDING WITHOUT LIMITATION ANY
# IMPLIED WARRANTIES OF MERCHANTABILITY OR OF FITNESS FOR A PARTICULAR PURPOSE. THE ENTIRE RISK ARISING OUT
# OF THE USE OR PERFORMANCE OF THE SAMPLES RE-MAINS WITH YOU. IN NO EVENT SHALL
# MICROSOFT OR ITS SUPPLIERS BE LIABLE FOR ANY DAMAGES WHATSOEVER (INCLUDING, WITHOUT LIMITATION, DAMAGES FOR
# LOSS OF BUSINESS PROFITS, BUSINESS INTERRUPTION, LOSS OF BUSINESS INFORMATION, OR OTHER PECUNIARY LOSS) ARISING
# OUT OF THE USE OF OR INABILITY TO USE THE SAMPLES, EVEN IF MICROSOFT HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH
# DAMAGES. BECAUSE SOME STATES DO NOT ALLOW THE EXCLUSION OR LIMITATION OF LIABILITY FOR CONSEQUENTIAL OR INCIDENTAL
# DAMAGES, THE ABOVE LIMITATION MAY NOT APPLY TO YOU
########################################################################################################################
<#
    ### Script
        Script Powershell com a função de listar informações da Floresta
    ### Versionamento
        V 1.8 - Original script
		V 1.8.1 - Versão que modifica o local de saída do script

#>

[CmdletBinding()]
param (
	[parameter(Mandatory=$false)]$Server
)

### Variáveis do log
    $data = Get-Date -Format yyyyMMdd                               #Captura a data
	$Diretorio = "c:\Temp\_DCInfo\"                                 #Determina o diretório de LOG
    $NomeDoArquivo = "ADForestInfo - " + $data + ".html"             #Determina o nome do ARQUIVO DE SAÍDA
    $path = Join-Path $Diretorio -ChildPath $NomeDoArquivo          #Cria o caminho completo do SAÍDA
    if (-not (Test-Path $Diretorio))                                #Valida se o diretório de LOG já existe
    {
        New-Item -Path $Diretorio -ItemType Directory |Out-Null     #Cria o diretório de LOG
    }

. "$PSScriptRoot\Get-MyWBSummary.ps1"

$adForest = Get-ADForest
if (-not($Server)) {$adDomainsList = $adForest.Domains} else {$adDomainsList = $Server}

$adDCs = @()
$adDomains = @()

$adDomainsList | %{

	$counter = 0
	$adDomain = Get-ADDomain -Server $_
	# SID-500: Administrator
	# SID-512: Domain Admins
	# SID-519: Enterprise Admins
	# SID-518: Schema Admins
	$adDomainHash = @{
		"Domain" = $adDomain.DNSRoot;
		"DomainSID" = $adDomain.DomainSID;
		"NetBIOSName" = $adDomain.NetBIOSName;
		"DomainMode" = $adDomain.DomainMode;
        "ParentDomain" = $adDomain.ParentDomain;
		"SID500" = (Get-ADUser "$($adDomain.DomainSID)-500" -Server $_).Name;
		"SID512" = (Get-ADGroup "$($adDomain.DomainSID)-512" -Server $_).Name;
		"SID519" = if($adDomain.DNSRoot -eq $adDomain.Forest){(Get-ADGroup "$($adDomain.DomainSID)-519" -Server $_).Name};
		"SID518" = if($adDomain.DNSRoot -eq $adDomain.Forest){(Get-ADGroup "$($adDomain.DomainSID)-518" -Server $_).Name};
	}
	$adDomains += New-Object PSObject -Property $adDomainHash

	$adDCsList = Get-ADDomainController -Server $_ -Filter *
	foreach($adDC in $adDCsList) {
		# Increase counter for progress bar
		$counter++

		# Display progress bar
		Write-Progress -Activity "Retrieving Domain Controllers in domain '$_'" -Status "Processing Domain Controller '$($adDC.Hostname)'" -PercentComplete (100 * ($counter/@($adDCsList).count))
		$nic = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled = 'True'" -Property * -ComputerName $adDC.Hostname
		$cs = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $adDC.Hostname | Select-Object HypervisorPresent, Model, NumberOfProcessors, NumberOfLogicalProcessors,
        @{L="RamGB";E={"{0:0.##}" -f ($_.TotalPhysicalMemory/1GB)}}
        $volumes = Get-WmiObject -Class Win32_Volume -ComputerName $adDC.Hostname | ?{$_.DriveType -eq 3 -and $_.DriveLetter -ne $null} | Select-Object DriveLetter, Label,
		@{L="SizeGB";E={"{0:0.##}" -f ($_.Capacity/1GB)}}

		$backup = (Get-MyWBSummary -ComputerName $adDC.Hostname -Last 1 -ErrorAction SilentlyContinue -ErrorVariable sessionErrors).CanRecover
		$adDCHash = [ordered]@{
			"Domain" = $adDomain.DNSRoot;
			"DC Name" = $adDC.Name;
			"Operating System" = $adDC.OperatingSystem;
			"Build" = $adDC.OperatingSystemVersion;
			"Is VM" = $cs.HypervisorPresent;
			"Model" = $cs.Model;
			"CPU" = $cs.NumberOfProcessors;
            "vCPU" = $cs.NumberOfLogicalProcessors;
            "RAM (GB)" = $cs.RamGB;
			"Volumes" = ($volumes| %{"$($_.DriveLetter) $($_.Label -replace '.+','($0)') $($_.SizeGB) GB"}) -Join "; ";
			"Site" = $adDC.Site;
			"Is GC" = $adDC.IsGlobalCatalog;
			"Is RODC" = $adDC.IsReadOnly;
			"IPv4" = $adDC.IPv4Address;
			"Gateway" = $nic.DefaultIPGateway -join ", ";
			"DNS Servers" = $nic.DNSServerSearchOrder -join ", ";
            # Un-comment if you are using WINS
			# "DNSEnabledForWINSResolution" = $nic.DNSEnabledForWINSResolution;
			# "WINSprimaryServer" = $nic.WINSprimaryServer -join ", ";
			# "WINSSecondaryServer" = $nic.WINSSecondaryServer -join ", ";
			"FSMO Roles" = $adDC.OperationMasterRoles -join ", ";
			"Backup Type" = $backup;
		}
		$adDCs += New-Object PSObject -Property $adDCHash
	}
	Write-Progress -Activity "Retrieving Domain Controller in domain '$_'" -Status "Completed" -Completed
}

$htmlHeader = @"
<title>Active Directory Information - $($adForest.Name)</title>
<style>
    h1 {
        font-family: Arial, Helvetica, sans-serif;
        color: #e68a00;
        font-size: 28px;
    }
    h2 {
        font-family: Arial, Helvetica, sans-serif;
        color: #000099;
        font-size: 16px;
    }
	h3 {
        font-family: Arial, Helvetica, sans-serif;
        font-size: 14px;
    }

	table {
		font-size: 12px;
		border: 0px;
		font-family: Arial, Helvetica, sans-serif;
	}
    td {
		padding: 4px;
		margin: 0px;
		border: 0;
	}
    th {
        background: #395870;
        background: linear-gradient(#49708f, #293f50);
        color: #fff;
        font-size: 11px;
        padding: 10px 15px;
        vertical-align: middle;
	}

    tbody tr:nth-child(even) {
        background: #f0f0f2;
    }

    #CreationDate {
		font-family: Arial, Helvetica, sans-serif;
		font-style: italic;
        color: #ff3300;
        font-size: 12px;
    }

</style>
"@


$htmlBody = "<h1>Forest: $($adForest.Name) | Forest Functional Level: $($adForest.ForestMode)</h1>"
$htmlBody += "<p id='CreationDate'>Creation Date: $(Get-Date -Format 'yyyy.MM.dd HH:mm')</p>"

$adDomains | Sort-Object ParentDomain, Domain | %{
	$domain = $_.Domain
	$htmlAdDomain = "<h2>Domain: $($_.Domain) | NetBIOS Name: $($_.NetBIOSName) | Domain Functional Level: $($_.DomainMode) $($_.ParentDomain -replace '.+','| Parent Domain: $0')</h2>"
	$htmlAdDomain += "<h3>Domain SID: $($_.DomainSID) | SID-500: $($_.SID500) | SID-512: $($_.SID512) $($_.SID519 -replace '.+','| SID-519: $0') $($_.SID518 -replace '.+','| SID-518: $0')</h3>"
	$htmlBody += $adDCs | Where-Object {$_.Domain -eq $domain} | Select-Object -Property * -ExcludeProperty Domain | ConvertTo-Html -Fragment -PreContent $htmlAdDomain
}

$report = ConvertTo-Html -Body $htmlBody -Head $htmlHeader
$report | Out-File $path
