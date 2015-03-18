[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [ValidateScript( { Test-Path $_ } ) ]
    [string]$AzureEnvFile,

    [Parameter(Mandatory=$True)]
    [ValidateScript( { Test-Path $_ } ) ]
    [string]$AzureVMDefns,

    [Parameter(Mandatory=$True)]
    [string]$VMName
)

# You run this script point it to the env file, a VM defns file, and specifying a VM you want to initialize. The script will then do the needful.

# This script must be run with admin rights, if not do it for the user
# Thanks to http://stackoverflow.com/a/11440595 for the snippet below
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host -ForegroundColor Yellow "Launching a new window to run this script with admin rights ..."
    $Arguments = "& '" + $MyInvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $Arguments
    break
}

# Convert relative path to absolute; not needed here so commenting it out
# if ($AzureEnvFile -match "^\.") { 
#    $AzureEnvFile = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\$(Split-Path -Leaf $AzureEnvFile)"
# }

# Create a hashtable from the JSON file
# ConvertFrom-JSON takes as input a string but Get-Content returns an array
# So convert the array to a string by -join or double quotes like thus: "$(Get-Content $AzureEnvFile)" | ConvertFrom-Json
$AzureEnv = (Get-Content $AzureEnvFile) -join "`n" | ConvertFrom-Json
$AzureVMs = (Get-Content $AzureVMDefns) -join "`n" | ConvertFrom-Json

# Import Azure module
# TODO: Put some error logic in here if the Azure module isn't available ...
Import-Module Azure

# Add your Azure account
#TODO: What happens if this fails?
Write-Host -ForegroundColor Green "Launching new window to get Azure credentials"
Add-AzureAccount

$VMAdminUser = Read-Host -Prompt ("VM Admin Username")
$VMAdminPass = "Password"
# Password complexity check
while (($VMAdminPass.length -lt 8) -or ($VMAdminPass -notmatch "[~!#$%^&*()`]") -or ($VMAdminPass -notmatch "[0-9]")) { 
    $VMAdminPass = Read-Host -Prompt ("VM Admin Password (will be shown as you type; min 8 chars including 1 special & 1 num)") 
}

# Thanks to http://blogs.msdn.com/b/koteshb/archive/2010/02/13/powershell-creating-a-pscredential-object.aspx
# I use this object later
$VMCredObject = New-Object System.Management.Automation.PSCredential ($VMAdminUser, $(ConvertTo-SecureString $VMAdminPass -AsPlainText -Force))

# Create the VM config
Write-Host -ForegroundColor Green -NoNewline "Creating VM: "
$VM = $AzureVMs | ?{ $_.Name -eq $VMName }
if ($VM -eq $null) { Write-Error "Unable to find VM $VMName!"; break } else { Write-Host -ForegroundColor Green "$($VM.Name)" }

$AzureVMConfig = New-AzureVMConfig -Name $VM.Name -InstanceSize $VM.InstanceSize -ImageName $VM.ImageName |
        Add-AzureProvisioningConfig -Windows -AdminUsername $VMAdminUser -Password $VMAdminPass -TimeZone $VM.TimeZone -NoRDPEndpoint |
        Set-AzureSubnet -SubnetNames $VM.Subnet
    
if ($VM.IPAddr) {
    if ($(Test-AzureStaticVNetIP -IPAddress $VM.IPAddr -VNetName $VM.AddrSpaceName).IsAvailable) {
        $AzureVMConfig | Set-AzureStaticVNetIP -IPAddress $VM.IPAddr
        Write-Host -ForegroundColor Green "`t Static IP $($VM.IPAddr) set"
    } else {
        Write-Error "`t You asked for a Static IP $($VM.IPAddr) to be set but it is not available."
    }
}

# Create service & provision the VM
Write-Host -ForegroundColor Green "Creating Service"
New-AzureService -ServiceName $VM.Name -AffinityGroup $($AzureEnv.Location -replace "\s*","") -ErrorAction SilentlyContinue
Write-Host -ForegroundColor Green "Provisioning VM"
$AzureVMConfig | New-AzureVM -ServiceName $VM.Name -VNetName $VM.AddrSpaceName

(Get-AzureCertificate -ServiceName $VM.Name).Data | Out-File "$env:TEMP\$($VM.Name).cer"
Import-Certificate -FilePath "$env:TEMP\$($VM.Name).cer" -CertStoreLocation Cert:\LocalMachine\root
Get-AzureWinRMUri -ServiceName $VM.Name | ft Host,Port

# Adding roles
Write-Host -ForegroundColor Green "Adding roles"

if ($VM.Role -eq "Primary DC") {
    # Do first DC stuff here
    Write-Host -ForegroundColor Green "`t This is the first DC in the domain/ forest"
    $InstallAD = {
        Write-Host -ForegroundColor Green "`t Installing role"
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart
        #$ADPassword = Read-Host -Prompt "`t`t AD Password? (will be shown on screen)"
        #$ADPasswordSS = ConvertTo-SecureString -String $ADPassword -AsPlainText -Force
        
        Write-Host -ForegroundColor Green "`t Promoting to DC"
        Install-ADDSForest -DomainName AzureLab.local -DomainNetbiosName AzureLab -DomainMode Win2012R2 -ForestMode Win2012R2 -InstallDns -NoDnsOnNetwork -Force
    }
    
    Invoke-Command -ConnectionUri $(Get-AzureWinRMUri -ServiceName $VM.Name -Name $VM.Name) -Credential $VMCredObject -ScriptBlock $InstallAD
    Write-Host -ForegroundColor Green "`t The machine may reboot and we will lose connection - don't panic!"
}

if ($VM.Role  -eq "DC") {
    # Do regular DC stuff here
    Write-Host -ForegroundColor Green "`t This is a regular DC+DNS"

    $InstallAD = {
        Write-Host -ForegroundColor Green "`t Installing role"
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart
        
        Write-Host -ForegroundColor Green "`t Promoting to DC"
        Install-ADDSDomainController -InstallDns -DomainName AzureLab.local
    }
    
    Invoke-Command -ConnectionUri $(Get-AzureWinRMUri -ServiceName $VM.Name -Name $VM.Name) -Credential $VMCredObject -ScriptBlock $InstallAD
}