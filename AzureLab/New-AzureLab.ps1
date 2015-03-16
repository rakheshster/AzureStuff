# This script must be run with admin rights, if not do it for the user
# Thanks to http://stackoverflow.com/a/11440595 for the snippet below
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Write-Host -ForegroundColor Yellow "Launching a new window to run this script with admin rights ..."
    $Arguments = "& '" + $MyInvocation.mycommand.definition + "'"
    Start-Process powershell -Verb runAs -ArgumentList $Arguments
    break
}

# Import Azure module
# TODO: Put some error logic in here if the Azure module isn't available ...
Import-Module Azure

# Modify these to suit your scenario
# TODO: Convert these to parameters I can take from the command line/ pipe
$AzureSubscription = "Visual Studio Ultimate with MSDN"

# This name needs to be unique across Azure, hence I prefix with my name
$StorageAccount = "rakheshlocallyredundant"
$StorageType = "Standard_LRS"

# The Network config file. 
$VNetConfigFile = Get-Random
while (!(Test-Path $VNetConfigFile)) { $VNetConfigFile = Read-Host -Prompt ("Enter full path to XML file containing VNet config") }

# Preferred location
$AzureLocation = "SouthEast Asia" 

# I am going to call the affinity group same as my location. It cannot have spaces, so remove these. 
$AzureAffinityGroup = $AzureLocation -replace "\s*",""

# VHD image to use for installing
# Select a value via: `Get-AzureVMImage | ?{ $_.Label -match "^Windows Server 2012" } | fl ImageName,Label`
$VMImageName = "a699494373c04fc0bc8f2bb1389d6106__Windows-Server-2012-R2-201412.01-en.us-127GB.vhd"

$VMTimeZone = "Arabian Standard Time"

# VM size and other details
$VMInstanceSize = "Basic_A1" 
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
        "Subnet" = "Servers"
        "AddrSpaceName" = "London"
        "Role" = @("Primary DC")
    },
    @{
        "Name" = "DUBSDC01"
        "IPAddr" = "192.168.25.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "Dubai"
        "Role" = @("DC")
    },
    @{
        "Name" = "MUSSDC01"
        "IPAddr" = "192.168.50.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "Muscat"
        "Role" = @("DC")
    }
)

# -x-

# Add your Azure account
#TODO: What happens if this fails?
Add-AzureAccount

# Create an affinity group
Write-Host -ForegroundColor Green "Creating Affinity Group: $AzureAffinityGroup"
New-AzureAffinityGroup -Name $AzureAffinityGroup -Description "$AzureLocation affinity group" -Location $AzureLocation -ErrorAction SilentlyContinue

# Clear an existing errors
$Error.Clear()

# Import VNet config. This will overwrite the existing config. 
Write-Host -ForegroundColor Green "Initializing network config from $VNetConfigFile"
Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile

# TODO: Is this correct?
if ($Error) { Write-Error "Something went wrong here!"; break }

Write-Host -ForegroundColor Green "Waiting 30 seconds ..."
Start-Sleep -Seconds 30

# If $VNetSite has a GatewaySites property, then initialize gateway
[bool]$GatewayPresent = 0 # false, assume no Gateway present
Write-Host -ForegroundColor Green "Initializing Gateways for sites that require it"
Write-Host -ForegroundColor Green "Remember: Gateways are charged per gateway per hour!"
foreach ($VNetSite in $(Get-AzureVNetSite)) {
    if ($VNetSite.GatewaySites) { 
        Write-Host -ForegroundColor Green "`t $($VNetSite.Name)"
        New-AzureVNetGateway -VNetName $VNetSite.Name -GatewayType DynamicRouting 
        $GatewayPresent = 1 # yes there is a Gateway present
    }
}

if ($GatewayPresent) {
    # Once the gateways are up and running get the public IP address & modify the XML file
    # But first read the XML file so we can change it
    [xml]$XMLFile = Get-Content $VNetConfigFile
    foreach ($VNetSite in $(Get-AzureVNetSite)) {
        Write-Host -ForegroundColor Green "Getting public IP address of gateway in $($VNetSite.Name)"
        ($XMLFile.NetworkConfiguration.VirtualNetworkConfiguration.LocalNetworkSites.LocalNetworkSite | ?{ $_.name -eq $VNetSite.Name}).VPNGatewayAddress = (Get-AzureVNetGateway -VNetName $VNetSite.Name).VIPAddress
    }

    # Save XML file
    $TempVNetFile = "$env:TEMP\$(get-random).xml"
    $XMLFile.Save($TempVNetFile)

    # Re-read it
    Set-AzureVNetConfig -ConfigurationPath $TempVNetFile
    Remove-Item -Force $TempVNetFile

    $GatewayKey = Get-Random
    Write-Host -ForegroundColor Green "Turning off encryption for the tunnels & setting the shared key"
    foreach ($VNetSite in $(Get-AzureVNetSite)) {
        foreach ($LocalSite in $VNetSite.GatewaySites) {
            Write-Host -ForegroundColor Green "`t Shared key: $($VnetSite.Name) <--> $($LocalSite.Name)"
            Set-AzureVNetGatewayKey -VNetName $VNetSite.Name -SharedKey $GatewayKey -LocalNetworkSiteName $LocalSite.Name
            Write-Host -ForegroundColor Green "`t Encryption: $($VnetSite.Name) <--> $($LocalSite.Name)"
            Set-AzureVNetGatewayIPsecParameters -VNetName $VNetSite.Name -EncryptionType NoEncryption -LocalNetworkSiteName $LocalSite.Name
        }
    }
}

# Create storage account.
Write-Host -ForegroundColor Green "Creating Storage Account $StorageAccount"
New-AzureStorageAccount -StorageAccountName $StorageAccount -AffinityGroup $AzureAffinityGroup -Type $StorageType -ErrorAction SilentlyContinue

# Assign storage account to the subscription
Write-Host -ForegroundColor Green "Assigning Storage Account $StorageAccount to subscription $AzureSubscription"
Set-AzureSubscription -CurrentStorageAccountName $StorageAccount -SubscriptionName $AzureSubscription

# Create the VMs
Write-Host -ForegroundColor Green "Creating VMs"
foreach ($VM in $AzureVMs) {
    Write-Host -ForegroundColor Green "`t $($VM.Name)"
    $AzureVMConfig = New-AzureVMConfig -Name $VM.Name -InstanceSize $VMInstanceSize -ImageName $VMImageName |
        Add-AzureProvisioningConfig -Windows -AdminUsername $VMAdminUser -Password $VMAdminPass -TimeZone $VMTimeZone -NoRDPEndpoint |
        Set-AzureSubnet -SubnetNames $VM.Subnet
    
    if ($VM.IPAddr) {
        if ($(Test-AzureStaticVNetIP -IPAddress $VM.IPAddr -VNetName $VM.AddrSpaceName).IsAvailable) {
            $AzureVMConfig | Set-AzureStaticVNetIP -IPAddress $VM.IPAddr
            Write-Host -ForegroundColor Green "`t Static IP $($VM.IPAddr) set"
        } else {
            Write-Error "`t`t You asked for a Static IP $($VM.IPAddr) to be set but it is not available."
        }
    }

    Write-Host -ForegroundColor Green "`t`t Creating Service"
    New-AzureService -ServiceName $VM.Name -AffinityGroup $AzureAffinityGroup -ErrorAction SilentlyContinue
    Write-Host -ForegroundColor Green "`t`t Provisioning VM"
    $AzureVMConfig | New-AzureVM -ServiceName $VM.Name -VNetName $VM.AddrSpaceName
}

# Loop again, this time to get the certificates
Write-Host -ForegroundColor Green "Adding certificates to local store"
foreach ($VM in $AzureVMs) {
    Write-Host -ForegroundColor Green "`t $($VM.Name)"
    $AzureVMName = $VM.Name
    (Get-AzureCertificate -ServiceName $AzureVMName).Data | Out-File "$env:TEMP\$AzureVMName.cer"
    Import-Certificate -FilePath "$env:TEMP\$AzureVMName.cer" -CertStoreLocation Cert:\LocalMachine\root
    Get-AzureWinRMUri -ServiceName $AzureVMName | ft Host,Port
}

# Adding roles
Write-Host -ForegroundColor Green "Adding roles"
foreach ($VM in $AzureVMs) {
    Write-Host -ForegroundColor Green "`t $($VM.Name)"

    if ($VM.Role.Contains("Primary DC")) {
    # Do first DC stuff here
    Write-Host -ForegroundColor Green "`t`t This is the first DC in the domain/ forest"
    $InstallAD = {
        Write-Host -ForegroundColor Green "`t`t Installing role"
        #Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart
        #$ADPassword = Read-Host -Prompt "`t`t AD Password? (will be shown on screen)"
        #$ADPasswordSS = ConvertTo-SecureString -String $ADPassword -AsPlainText -Force
        
        Write-Host -ForegroundColor Green "`t`t Promoting to DC"
        Install-ADDSForest -DomainName AzureLab.local -DomainNetbiosName AzureLab -DomainMode Win2012R2 -ForestMode Win2012R2 -InstallDns -NoDnsOnNetwork -Force
        }
    
    Invoke-Command -ConnectionUri $(Get-AzureWinRMUri -ServiceName $VM.Name -Name $VM.Name) -Credential $VMCredObject -ScriptBlock $InstallAD
    Write-Host -ForegroundColor Green "The machine will reboot and we will lose connection"
    }

if ($VM.Role.Contains("DC")) {
    # Do regular DC stuff here
    Write-Host -ForegroundColor Green "`t`t This is a regular DC+DNS"
    $InstallAD = {
        Write-Host -ForegroundColor Green "`t`t Installing role"
        Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -Restart
        
        Write-Host -ForegroundColor Green "`t`t Promoting to DC"
        Install-ADDSDomainController -InstallDns -DomainName AzureLab.local
        }
    
    Invoke-Command -ConnectionUri $(Get-AzureWinRMUri -ServiceName $VM.Name -Name $VM.Name) -Credential $VMCredObject -ScriptBlock $InstallAD
    }

}