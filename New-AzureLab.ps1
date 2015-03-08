# Import Azure module
# TODO: Put some error logic in here if the Azure module isn't available ...
Import-Module Azure

# Modify these to suit your scenario
# TODO: Convert these to parameters I can take from the command line/ pipe
$AzureSubscription = "Visual Studio Ultimate with MSDN"
$StorageAccount = "rakheshlocallyredundant"
$StorageType = "Standard_LRS"

# Replace with an absolute path or different filename if that's your case
# Else I expect it to be a filed called AzureVNet.XML in the same directory as this script
$VNetConfigFile = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\AzureVNet.xml"

# Preferred location
# Note: this gets used in the affinity group name below and is also references in $VNetConfigFile so change there too
$AzureLocation = "SouthEast Asia" 

# I am going to call the affinity group same as my location. It cannot have spaces, so remove these. 
$AzureAffinityGroup = $AzureLocation -replace "\s*",""

# VHD image to use for installing
# Select a value via for example: `Get-AzureVMImage | ?{ $_.Label -match "^Windows Server 2012" } | fl ImageName,Label`
$VMImageName = "a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-R2-201412.01-en.us-127GB.vhd"

$VMInstanceSize = "Basic_A1" 
$VMAdminUser = "xxxx"
$VMAdminPass = "xxxx"
$VMTimeZone = "Arabian Standard Time"

$AzureDC = @{
    "London" = "LONSDC01"
    "Muscat" = "MUSSDC01"
    "Dubai" = "DUBSDC01"
}

# -x-

# Create an affinity group
# TODO: If affinity group already exists then ...?
New-AzureAffinityGroup -Name $AzureAffinityGroup -Description "$AzureLocation affinity group" -Location $AzureLocation

# Import VNet config. This will over-write whatever exists. 
Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile

# Create storage account.
# TODO: Again, what if it already exists? 
New-AzureStorageAccount -StorageAccountName $StorageAccount -AffinityGroup $AzureAffinityGroup -Type $StorageType

# Assign storage account to the subscription
Set-AzureSubscription -CurrentStorageAccountName $StorageAccount -SubscriptionName $AzureSubscription

foreach ($site in $AzureDC.Keys) {
    $AzureVMName = $AzureDC.$site
    $AzureVMConfig = New-AzureVMConfig -Name $AzureVMName -InstanceSize $VMInstanceSize -ImageName $VMImageName 
    $AzureVMConfig | Add-AzureProvisioningConfig -Windows -AdminUsername $VMAdminUser -Password $VMAdminPass -TimeZone $VMTimeZone
}