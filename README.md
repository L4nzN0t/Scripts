# Scripts

All scripts should follow the example below:
```
C:/PS> ./script.ps1 -Username teste@vsphere.local -Password Password@123 -VCList vclist.txt

PARAMETERS
    [Mantadory]
    -VCList <String>
        List of vCenters to connect to.

    [Mantadory]
    -Username <String>
        Username to log in vCenter

    [Mantadory]
    -Password <SecureString>
        Password to log in vCenter
```