[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [ValidateScript( { Test-Path $_ } ) ]
    [string]$AzureEnvFile
)

# This is a script you run one time to set up the storage group etc. 

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

# I am going to call the affinity group same as my location. It cannot have spaces, so remove these. 
$AzureAffinityGroup = $AzureLocation -replace "\s*",""

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