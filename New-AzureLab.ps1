Import-Module Azure

$AzureSubscription = "Visual Studio Ultimate with MSDN"
$AzureLocation = "SouthEast Asia"
$VNetConfigFile = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\AzureVNet.xml"
$StorageAccount = "rakheshlocallyredundant"
$StorageType = "Standard_LRS"

# Affinity group name cannot have spaces
$AzureAffinityGroup = $AzureLocation -replace "\s*",""

New-AzureAffinityGroup -Name $AzureAffinityGroup -Description "$AzureLocation affinity group" -Location $AzureLocation
Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile
New-AzureStorageAccount -StorageAccountName $StorageAccount -AffinityGroup $AzureAffinityGroup -Type $StorageType
Set-AzureSubscription -CurrentStorageAccountName $StorageAccount -SubscriptionName $AzureSubscription