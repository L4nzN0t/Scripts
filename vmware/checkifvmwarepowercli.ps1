# Ensure the VMware PowerCLI module is installed and loaded
try {
    Import-Module VMware.VimAutomation.Core
}
catch [FileNotFoundException]
{
    Write-Verbose "Module VMware.PowerCLI not found."
    $answer = Read-Host "Do you want to install? (Y/N)"
    if ($answer.ToUpper() -eq "Y") { Install-Module -Name VMware.PowerCLI -Scope AllUsers}
    else { exit 1 }
}