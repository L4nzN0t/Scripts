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
    Listando as GPOs que estão sem configuração ou GPOs sem links
#>
<#
    Versionamento
    V 1.0 - Criação do script
    V 1.1 - Alterando path
#>

### Variáveis do log
$data = Get-Date -Format yyyyMMdd                               #Captura a data
$Diretorio = "c:\Temp\_DCInfo\"                                 #Determina o diretório de LOG
$NomeDoArquivo = "DCInfoGPO - " + $data + ".csv"                 #Determina o nome do ARQUIVO DE SAÍDA
$path = Join-Path $Diretorio -ChildPath $NomeDoArquivo          #Cria o caminho completo do SAÍDA
$NomeDoArquivoLog = "DCInfoGPO - " + $data + ".log"              #Determina o nome do ARQUIVO DE LOG
$logpath = Join-Path $Diretorio -ChildPath $NomeDoArquivoLog    #Cria o caminho completo do LOG
$NomeDoArquivoLXML = "DCInfoGPO - " + $data + ".XML"             #Determina o nome do ARQUIVO DE XML
$XMLpath = Join-Path $Diretorio -ChildPath $NomeDoArquivoLXML   #Cria o caminho completo do LXML
if (-not (Test-Path $Diretorio))                                #Valida se o diretório de LOG já existe
{
    New-Item -Path $Diretorio -ItemType Directory |Out-Null     #Cria o diretório de LOG
}

### Iniciando
Start-Transcript -Path $logpath -Append -ErrorAction SilentlyContinue   #Iniciando LOG
get-date -Format "dd/MM/yyyy HH:mm:ss"                                  #Display da data de início
Write-Host "### Script em funcionamento ###"                            #Display Script em funcionamento
$Resultado = @()                                                        #Cria variável vazia de Resultado
$CTSemDadoSemLink = 0                                                   #Cria variável com valor 0
$CTSemDado = 0                                                          #Cria variável com valor 0
$CTSemLink = 0                                                          #Cria variável com valor 0
$CTOK = 0                                                               #Cria variável com valor 0

### Gerenco export das GPOs em XML
Get-GPOReport -All -ReportType XML -Path $XMLpath

###Importando o arquivo XML
[xml]$XmlDocument = Get-Content -Path ($XMLpath)
$Gpos = $XmlDocument.report.gpo


### Identificando as GPOs
foreach ($GPO in $GPOS)
{
    $GpoName = $Gpo.Name
    $GpoUserADVer = $Gpo.User.VersionDirectory
    $GpoCompADVer = $Gpo.Computer.VersionDirectory
    #$GposNoLink = $GPO | Where-Object {!$_.LinksTo}
    $GposNoLink = if($GPO.LinksTo -ne $null){$GPO.LinksTo}else{$null}
    #$GposNoLink = if($GPO.LinksTo -ne $null){$GPO}
    $GpoModDate =  $Gpo.ModifiedTime

    if (($GpoUserADVer -eq 0 -and $GpoCompADVer -eq 0) -and $GposNoLink -eq $null)
                {
                    Write-Host "."
                    $Dados = "NO"
                    $Link = "NO"
                    $CTSemDadoSemLink = $CTSemDadoSemLink + 1
                }
            elseif (($GpoUserADVer -ne 0 -or $GpoCompADVer -ne 0) -and $GposNoLink -eq $null)
                {
                    Write-Host "."
                    $Dados = "YES"
                    $Link = "NO"
                    $CTSemLink = $CTSemLink + 1
                }
            elseif (($GpoUserADVer -eq 0 -and $GpoCompADVer -eq 0) -and $GposNoLink -ne $null)
                {
                    Write-Host "."
                    $Dados = "NO"
                    $Link = "YES"
                    $CTSemDado = $CTSemDado + 1
                }
            elseif (($GpoUserADVer -ne 0 -or $GpoCompADVer -ne 0) -and $GposNoLink -ne $null)
                {
                    Write-Host "."
                    $Dados = "YES"
                    $Link = "YES"
                    $CTOK = $CTOK + 1
                }
        #Início do Report
        $Coleta = New-Object PSobject
        Add-Member NoteProperty -InputObject $Coleta -Name "GPO" -value $GpoName
        Add-Member NoteProperty -InputObject $Coleta -Name "Dados" -value $Dados
        Add-Member NoteProperty -InputObject $Coleta -Name "Link" -value $Link

        $Resultado += $Coleta

}
$Resultado |Export-Csv -Delimiter ";" -LiteralPath $Path -NoTypeInformation        #Exporta o resultado para CSV
<#
### Mostra na Tela o resultado
    $Resultado |ft -a
    Write-Host "Total de GPOs OK $ctok"
    Write-Host "Total de GPOs Sem Link $CTSemLink"
    Write-Host "Total de GPOs Sem Dados $CTSemDado"
    Write-Host "Total de GPOs Sem Link e Sem Dados $CTSemDadoSemLink"
#>
### Finalizando
get-date -Format "dd/MM/yyyy HH:mm:ss"                      #Display da data de início
Write-Host "#### Fim do Scrip ####"                         #Display da mensagem entre aspas
Stop-Transcript                                             #Para o Transcription
