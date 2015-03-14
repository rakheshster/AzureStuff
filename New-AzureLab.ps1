# Import Azure module
# TODO: Put some error logic in here if the Azure module isn't available ...
Import-Module Azure

# Modify these to suit your scenario
# TODO: Convert these to parameters I can take from the command line/ pipe
$AzureSubscription = "Visual Studio Ultimate with MSDN"

# This name needs to be unique across Azure, hence I prefix with my name
$StorageAccount = "rakheshlocallyredundant"
$StorageType = "Standard_LRS"

# The Network config file. I expect this to be in the same folder as the script, and named AzureVNet.xml.
$VNetConfigFile = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\AzureVNet.xml"

# Preferred location
$AzureLocation = "SouthEast Asia" 

# I am going to call the affinity group same as my location. It cannot have spaces, so remove these. 
$AzureAffinityGroup = $AzureLocation -replace "\s*",""

# VHD image to use for installing
# Select a value via: `Get-AzureVMImage | ?{ $_.Label -match "^Windows Server 2012" } | fl ImageName,Label`
$VMImageName = "a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-R2-201412.01-en.us-127GB.vhd"

# VM size and other details
$VMInstanceSize = "Basic_A1" 
$VMAdminUser = Read-Host -Prompt ("VM Admin Username")
$VMAdminPass = Read-Host -Prompt ("VM Admin Password")
$VMTimeZone = "Arabian Standard Time"

# Here are my Azure VMs.
$AzureVMs = @(
    @{
        "Name" = "LONSDC01"
        "IPAddr" = "192.168.10.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "London"
        "Role" = "DC"
        "Comments" = "First DC"
    },
    @{
        "Name" = "DUBSDC01"
        "IPAddr" = "192.168.25.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "Dubai"
        "Role" = "DC"
        "Comments" = "First DC"
    },
    @{
        "Name" = "MUSSDC01"
        "IPAddr" = "192.168.50.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "Muscat"
        "Role" = "DC"
    }
)

# -x-

# Add your Azure account
#TODO: What happens if this fails?
Add-AzureAccount

# Create an affinity group
New-AzureAffinityGroup -Name $AzureAffinityGroup -Description "$AzureLocation affinity group" -Location $AzureLocation -ErrorAction SilentlyContinue

# Import VNet config. 
Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile

# Create storage account.
New-AzureStorageAccount -StorageAccountName $StorageAccount -AffinityGroup $AzureAffinityGroup -Type $StorageType -ErrorAction SilentlyContinue

# Assign storage account to the subscription
Set-AzureSubscription -CurrentStorageAccountName $StorageAccount -SubscriptionName $AzureSubscription

# Create the VMs
foreach ($VM in $AzureVMs) {
    $AzureVMConfig = New-AzureVMConfig -Name $VM.Name -InstanceSize $VMInstanceSize -ImageName $VMImageName |
    Add-AzureProvisioningConfig -Windows -AdminUsername $VMAdminUser -Password $VMAdminPass -TimeZone $VMTimeZone -NoRDPEndpoint |
    Set-AzureSubnet -SubnetNames $VM.Subnet
    
    if ($VM.IPAddr) {
        if ($(Test-AzureStaticVNetIP -IPAddress $VM.IPAddr -VNetName $VM.AddrSpaceName).IsAvailable) {
            $AzureVMConfig | Set-AzureStaticVNetIP -IPAddress $VM.IPAddr
        } else {
            Write-Host -ForegroundColor Red "You asked for a static IP to be set but it is not available."
        }
    }

    New-AzureService -ServiceName $VM.Name -AffinityGroup $AzureAffinityGroup
    $AzureVMConfig | New-AzureVM -ServiceName $VM.Name -VNetName $VM.AddrSpaceName
}

# Loop again, this time to get the certificates
foreach ($VM in $AzureVMs) {
    $AzureVMName = $VM.Name
    (Get-AzureCertificate -ServiceName $AzureVMName ).Data | Out-File "$env:TEMP\$AzureVMName.cer"
    Import-Certificate -FilePath "$env:TEMP\$AzureVMName.cer" -CertStoreLocation Cert:\LocalMachine\root
    Get-AzureWinRMUri -ServiceName $AzureVMName | ft Host,Port
}

foreach ($VM in $AzureVMs) {
    if (($VM.Role -eq "Primary DC") -and ($VM.Comments -match "First DC")) {
    # do first DC stuff here
    
    }

if (($VM.Role -eq "DC") {
    # do regular DC stuff here

    }

}