[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [ValidateScript( { Test-Path $_ } ) ]
    [string]$AzureEnvFile
)

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

# Import Azure module
# TODO: Put some error logic in here if the Azure module isn't available ...
Import-Module Azure

# Previously I had all these as variables; now that I have a JSON file I don't want to go around changing the references everywhere
# So I'll just read these into the variables. 
$AzureSubscription = $AzureEnv.Subscription
$StorageAccount = $AzureEnv.StorageAccount
$StorageType = $AzureEnv.StorageType
$AzureLocation = $AzureEnv.Location
$VMImageName = $AzureEnv.VMImageName # Select a different value via: `Get-AzureVMImage | ?{ $_.Label -match "^Windows Server 2012" } | fl ImageName,Label`
$VMTimeZone = $AzureEnv.VMTimezone
$VMInstanceSize = $AzureEnv.VMInstanceSize

# I am going to call the affinity group same as my location. It cannot have spaces, so remove these. 
$AzureAffinityGroup = $AzureLocation -replace "\s*",""

$VMAdminUser = Read-Host -Prompt ("VM Admin Username")
$VMAdminPass = "Password"
# Password complexity check
while (($VMAdminPass.length -lt 8) -or ($VMAdminPass -notmatch "[~!#$%^&*()`]") -or ($VMAdminPass -notmatch "[0-9]")) { 
    $VMAdminPass = Read-Host -Prompt ("VM Admin Password (will be shown as you type; min 8 chars including 1 special & 1 num)") 
}

# Thanks to http://blogs.msdn.com/b/koteshb/archive/2010/02/13/powershell-creating-a-pscredential-object.aspx
# I use this object later
$VMCredObject = New-Object System.Management.Automation.PSCredential ($VMAdminUser, $(ConvertTo-SecureString $VMAdminPass -AsPlainText -Force))

# Here are my Azure VMs.
# Role "DC" implies DC+DNS.
$AzureVMs = @(
    @{
        "Name" = "LONSDC01"
        "IPAddr" = "192.168.10.4"
        "AddrSpaceName" = "RAXNET"
        "Subnet" = "LondonServers"
        "Role" = @("Primary DC")
        # older entries, remove sometime. in fact, TODO: make this object be an input to the script. 
        #"Subnet" = "Servers"
        #"AddrSpaceName" = "London"
        
    },
    @{
        "Name" = "DUBSDC01"
        "IPAddr" = "192.168.25.4"
        "AddrSpaceName" = "RAXNET"
        "Subnet" = "DubaiServers"
        "Role" = @("DC")
        # older entries, remove sometime. in fact, TODO: make this object be an input to the script. 
        #"Subnet" = "Servers"
        #"AddrSpaceName" = "Dubai"
        
    },
    @{
        "Name" = "MUSSDC01"
        "IPAddr" = "192.168.50.4"
        "AddrSpaceName" = "RAXNET"
        "Subnet" = "MuscatServers"
        "Role" = @("DC")
        # older entries, remove sometime. in fact, TODO: make this object be an input to the script. 
        #"Subnet" = "Servers"
        #"AddrSpaceName" = "Muscat"
        
    }
)

# -x-

# Add your Azure account
#TODO: What happens if this fails?
Write-Host -ForegroundColor Green "Launching new window to get Azure credentials"
Add-AzureAccount

# Create an affinity group
Write-Host -ForegroundColor Green "Creating Affinity Group: $AzureAffinityGroup"
New-AzureAffinityGroup -Name $AzureAffinityGroup -Description "$AzureLocation affinity group" -Location $AzureLocation -ErrorAction SilentlyContinue

# Create storage account.
Write-Host -ForegroundColor Green "Creating Storage Account $StorageAccount"
New-AzureStorageAccount -StorageAccountName $StorageAccount -AffinityGroup $AzureAffinityGroup -Type $StorageType -ErrorAction SilentlyContinue

# Assign storage account to the subscription
Write-Host -ForegroundColor Green "Assigning Storage Account $StorageAccount to subscription $AzureSubscription"
Set-AzureSubscription -CurrentStorageAccountName $StorageAccount -SubscriptionName $AzureSubscription

# Create the VMs
Write-Host -ForegroundColor Green "Creating VMs"
foreach ($VM in $AzureVMs) {
    Write-Host -ForegroundColor Green "* $($VM.Name)"
    $AzureVMConfig = New-AzureVMConfig -Name $VM.Name -InstanceSize $VMInstanceSize -ImageName $VMImageName |
        Add-AzureProvisioningConfig -Windows -AdminUsername $VMAdminUser -Password $VMAdminPass -TimeZone $VMTimeZone -NoRDPEndpoint |
        Set-AzureSubnet -SubnetNames $VM.Subnet
    
    if ($VM.IPAddr) {
        if ($(Test-AzureStaticVNetIP -IPAddress $VM.IPAddr -VNetName $VM.AddrSpaceName).IsAvailable) {
            $AzureVMConfig | Set-AzureStaticVNetIP -IPAddress $VM.IPAddr
            Write-Host -ForegroundColor Green "`t Static IP $($VM.IPAddr) set"
        } else {
            Write-Error "`t You asked for a Static IP $($VM.IPAddr) to be set but it is not available."
        }
    }

    Write-Host -ForegroundColor Green "`t Creating Service"
    New-AzureService -ServiceName $VM.Name -AffinityGroup $AzureAffinityGroup -ErrorAction SilentlyContinue
    Write-Host -ForegroundColor Green "`t Provisioning VM"
    $AzureVMConfig | New-AzureVM -ServiceName $VM.Name -VNetName $VM.AddrSpaceName
}

# Loop again, this time to get the certificates
Write-Host -ForegroundColor Green "Adding certificates to local store"
foreach ($VM in $AzureVMs) {
    Write-Host -ForegroundColor Green "* $($VM.Name)"
    $AzureVMName = $VM.Name
    (Get-AzureCertificate -ServiceName $AzureVMName).Data | Out-File "$env:TEMP\$AzureVMName.cer"
    Import-Certificate -FilePath "$env:TEMP\$AzureVMName.cer" -CertStoreLocation Cert:\LocalMachine\root
    Get-AzureWinRMUri -ServiceName $AzureVMName | ft Host,Port
}

# Adding roles
Write-Host -ForegroundColor Green "Adding roles"
foreach ($VM in $AzureVMs) {
    Write-Host -ForegroundColor Green "* $($VM.Name)"

    if ($VM.Role.Contains("Primary DC")) {
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

if ($VM.Role.Contains("DC")) {
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

}