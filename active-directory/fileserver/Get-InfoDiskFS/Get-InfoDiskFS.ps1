Clear-Host
$global:fileservers = "<fileserver01>,<fileserver02>,<fileserver03>" -split ","
$WORKSPACE_FOLDER = Get-Item $MyInvocation.MyCommand.Definition
$WORKSPACE_FOLDER = $WORKSPACE_FOLDER.DirectoryName

if (-not (Test-Path -Path "$WORKSPACE_FOLDER\logs"))
{
    mkdir "$WORKSPACE_FOLDER\logs"
}

Function Logger
{
    param([string]$content)
    $log = "[$(Get-Date -Format "dd/MM/yyyy HH:mm K")] " + $content

    try {
        Add-Content -Path "$WORKSPACE_FOLDER\logs\$(Get-Date -UFormat "%Y-%m-%d").log" -Value $log
    }
    catch {
        exit(1)
    }
}

Function Check_Requirements
{
    if ((Get-InstalledModule -Name SqlServer))
    {
        if (Get-Module -Name SqlServer)
        {
            $module = Get-Module -Name SqlServer

            Logger "Modulo: $($module.Name) carregado!"
            Logger "Caminho: $($module.Path)"
        }
        else {
            Logger "Modulo SqlServer não importado"
            Logger "Preparando para importar..."
            try{
                Import-Module -Name SqlServer -Force
                Logger "Modulo SQLServer importado com sucesso!"
            }
            catch {
                Logger "Erro ao importar modulo SQLServer!"
                Logger $Error[0]
            }
        }
    }
    else
    {
        Logger "Modulo não encontrado!"
        Logger "Preparando para instalar..."
        try {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
            Install-module SQLServer -Force -Confirm:$false -SkipPublisherCheck
            Import-module SQLServer -Force -SkipEditionCheck
            Logger "Modulo SQLServer instalado com sucesso!"
        }
        catch {
            Logger "Erro ao instalar modulo SQLServer"
            exit 1
        }

    }

    if ((Get-InstalledModule -Name AdPreview) -and (Get-Module -Name AdPreview))
    {
        Write-host "existe"
    }
    else
    {
        Write-host "Não existe"
    }
}

Function __Main__
{
    # Verifica se os modulos necessários para execução do scrip estão instalados e carregados
    Check_Requirements

    ## Processo para coletar informações nos servidores remotos
    $scriptBlock = {
    if ((Get-volume -FileSystemLabel "FILESHARE" -ErrorAction SilentlyContinue))
        {
            Get-Volume -FileSystemLabel "FILESHARE"
        }
        if ((Get-volume -FileSystemLabel "FILE SERVER" -ErrorAction SilentlyContinue))
        {
            Get-Volume -FileSystemLabel "FILE SERVER"
        }
    }
    ## Coletar informações dos servidores
    Logger "Coletando informacoes dos servidores..."
    $disks = foreach ($fileserver in $global:fileservers)
    {
        Invoke-Command -ComputerName $fileserver -ScriptBlock $scriptBlock
    }
    Logger "Informacoes coletadas!"

    # Parâmetros de conexão com o banco de dados SQL Server
    $serverName = "<db_server>"
    $databaseName = "<db_name>"
    $username = "<db_user>"
    $password = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String("<base64_db_password>"))

    # Criar uma string de conexão
    $connectionString = "Server=$serverName;Database=$databaseName;User Id=$username;Password=$password;TrustServerCertificate=True"

    # Estabelecer uma conexão com o banco de dados
    Logger "Iniciando conexao com o banco de dados..."
    timeout.exe /t 3 > $null

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection
        $connection.ConnectionString = $connectionString
        $connection.Open()
        Logger "Conexao estabelecida!"

        for ($i = 0;$i -lt $disks.Count;$i++)
        {
            $diskLetter = $disks[$i].DriveLetter
            $fsLabel = $disks[$i].FileSystemLabel
            $fileSystem = $disks[$i].FileSystem
            $diskType = $disks[$i].DriveType
            $healthStatus = $disks[$i].HealthStatus
            $operationalStatus = $disks[$i].OperationalStatus
            $sizeRemaining = $disks[$i].SizeRemaining
            $size = $disks[$i].Size
            $computerName = $disks[$i].PSComputerName

            # Instrução SQL de inserção
            $insertQuery = "INSERT INTO [dbo].Disco (DriveLetter, FileSystemLabel, FileSystem, DriveType, HealthStatus, OperationalStatus, SizeRemaining, Size, PSComputerName)
            VALUES ('$diskletter', '$fsLabel', '$filesystem', '$disktype', '$healthstatus', '$operationalstatus', $sizeremaining, $size, '$computerName')
            "

            # Insere dados dentro do SQL
            Invoke-SQLcmd -ConnectionString $connectionString -Query $insertQuery
            Logger "Dados inseridos na tabela. ComputerName = $computerName"

        }

        # Fechar a conexão com o banco de dados
        $connection.Close()
        Logger "Dados gravados no banco de dados"
        Logger "Preparando para desconectar"
        timeout /t 3 > $null
        Logger "Conexao encerrada!"
    }
    catch
    {
        Logger "Falha ao iniciar conexao com o banco de dados..."
        Logger $Error[0].ToString()
        Logger "Conexao encerrada!"
        exit 1
    }
    $global:fileservers.Clear()
}
__Main__


