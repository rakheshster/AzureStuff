# Import Azure module
# TODO: Put some error logic in here if the Azure module isn't available ...
Import-Module Azure

# Modify these to suit your scenario
# TODO: Convert these to parameters I can take from the command line/ pipe
$AzureSubscription = "Visual Studio Ultimate with MSDN"

# This name needs to be unique across Azure, hence I prefix with my name
$StorageAccount = "rakheshlocallyredundant"
$StorageType = "Standard_LRS"

# Earlier I was pulling in the VNetConfigXML file from the same directory as this script. 
# Not doing that any more but just leaving this behind as a reminder of those days ...
# $VNetConfigFile = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\AzureVNet.xml"

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

# Here's my Azure Network. It's an array of hash-tables defining each site (each *address space*, really). 
# NOTE: I don't do any validation of this whatsoever! If you make mistakes it will break the script/ your Azure VMs/ your Azure network. 
# TODO: Get this as a JSON file input perhaps? Looks like one anyway.
$AzureNetwork = @(
    @{
        Name = "London" 
        AddrSpace = "192.168.10.0/24"
        Subnet = @{ 
            "Servers" = "192.168.10.0/25" 
            "Clients" = "192.168.10.128/25"
        }
    },
    @{
        Name = "Dubai" 
        AddrSpace = "192.168.25.0/24"
        Subnet = @{ 
            "Servers" = "192.168.25.0/25" 
            "Clients" = "192.168.25.128/25"
        }
    },
    @{
        Name = "Muscat" 
        AddrSpace = "192.168.50.0/24"
        Subnet = @{ 
            "Servers" = "192.168.50.0/25" 
            "Clients" = "192.168.50.128/25"
        }
    }
)

# Here's my Azure VMs. Again, an array of hash-tables. 
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

# Create the XML file on the fly
# Start with the skeleton. Thanks to http://blogs.msdn.com/b/powershell/archive/2007/05/29/using-powershell-to-generate-xml-documents.aspx
# for reminding me I can use a here-string for XML. Previously I was reading this from a separate file
[xml]$VNetConfigXML = @"
<?xml version="1.0" encoding="utf-8"?>
<NetworkConfiguration xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://schemas.microsoft.com/ServiceHosting/2011/07/NetworkConfiguration">
</NetworkConfiguration>
"@

# Define each of the elements. See my blog post for an explanation: http://rakhesh.com/powershell/a-brief-intro-to-xml-powershell/
$VNConfig = $VNetConfigXML.CreateElement("VirtualNetworkConfiguration")

foreach ($site in $AzureNetwork) { 
    $VNSElement = $VNetConfigXML.CreateElement("VirtualNetworkSite")
    $AddrSpaceElement = $VNetConfigXML.CreateElement("AddressSpace")
    $AddrPrefixElement = $VNetConfigXML.CreateElement("AddressPrefix")
    $SubnetsElement = $VNetConfigXML.CreateElement("Subnets")

    # Set the attributes for the VirtualNetworkSites element
    $VNSElement.SetAttribute("name", $site.name)
    $VNSElement.SetAttribute("AffinityGroup", $AzureAffinityGroup)

    # Define the AddressPrefix element 
    $AddrPrefixElement.InnerText = $site.AddrSpace

    # Add this as a child to the Address Space element
    $AddrSpaceElement.AppendChild($AddrPrefixElement)

    # Create the Subnets element and child Subnet elements
    foreach ($subnetname in $site.Subnet.Keys) {
        # Create the Subnet element & set a name attribute
        $SubnetElement = $VNetConfigXML.CreateElement("Subnet")
        $SubnetElement.SetAttribute("name", $subnetname)

        # Define the inner text of the AddressPrefix element
        $AddrPrefixElement = $VNetConfigXML.CreateElement("AddressPrefix")
        $AddrPrefixElement.InnerText = $site.Subnet.$subnetname
        
        # Add AddressPrefix element as a child to Subnet
        $SubnetElement.AppendChild($AddrPrefixElement)
         
        # Add Subnet element as a child to Subnets element
         $SubnetsElement.AppendChild($SubnetElement)
     }

    # Add the Subnets & AddressSpace elements as children to VirtualNetworkSites
    $VNSElement.AppendChild($AddrSpaceElement)
    $VNSElement.AppendChild($SubnetsElement)

    # Append VirtualNetworkSites to VirtualNetworkConfiguration
    $VNConfig.AppendChild($VNSElement)
}

# Append VirtualNetworkConfiguration to the root
$VNetConfigXML.NetworkConfiguration.AppendChild($VNConfig)

# Save this as an XML file in a temp location
$VNetConfigFile = "$env:TEMP\$(get-random).xml"
$VNetConfigXML.Save($VNetConfigFile)

# -x- 

# Add your Azure account
#TODO: What happens if this fails?
Add-AzureAccount

# Create an affinity group
# TODO: If affinity group already exists then?
New-AzureAffinityGroup -Name $AzureAffinityGroup -Description "$AzureLocation affinity group" -Location $AzureLocation

# Import VNet config. This will over-write whatever exists. Also, remove the XML file once done. 
Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile
Remove-Item $VNetConfigFile -Force

# Create storage account.
# TODO: Again, what if it already exists? 
New-AzureStorageAccount -StorageAccountName $StorageAccount -AffinityGroup $AzureAffinityGroup -Type $StorageType

# Assign storage account to the subscription
Set-AzureSubscription -CurrentStorageAccountName $StorageAccount -SubscriptionName $AzureSubscription

#foreach ($site in $VNetDCs.Keys) {
#    $AzureVMName = $VNetDCs.$site
#    New-AzureVMConfig -Name $AzureVMName -InstanceSize $VMInstanceSize -ImageName $VMImageName | 
#        Add-AzureProvisioningConfig -Windows -AdminUsername $VMAdminUser -Password $VMAdminPass -TimeZone $VMTimeZone | 
#        Set-AzureSubnet -SubnetNames "Servers" | 
#        Set-AzureStaticVNetIP -IPAddress "10.0.0.15"
#}