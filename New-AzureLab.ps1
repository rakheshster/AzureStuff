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
        # I define two address spaces here.
        # I don't need to define two, but I would like to keep the clients and servers in separate subnets (for future use).
        # With a /25 subnet for each, I don't have space for a gateway subnet. I have two options:
        # 1) Create a /26 subnet each (59 addresses each), with a /29 for Gateway (3 addresses) followed by many more /29 subnets (because you can't carve larger subnets after that).
        # 2) Create a separate address space for the gateway and subnet it the way you want. I am going to go with this option. 
        # Remember: Every subnet has 2 addresses reserved for the network & broadcast. Further, Azure reserves the first 3 addresses. 
        # This means the smallest Azure subnet you can have is /29 - which leaves 3 addresses for use. 
        AddrSpaces = @(
            @{
                AddrSpace = "192.168.10.0/24"
                Subnet = @{ 
                    # /25 => 2^7 = 128 addresses => 192.168.x.0-127 & 192.168.x.128-255
                    # .0 & .127 are network & broadcast. .1-.3 are reserved by Azure. So the usable range is .4-.126. 
                    # Similarly .128 & .255 are network & broadcast. And .129-.131 are reserved by Azure. So the usable range is .132-.254. 
                    "Servers" = "192.168.10.0/25" 
                    "Clients" = "192.168.10.128/25"
                }
            },
            @{
                AddrSpace = "192.168.11.0/24"
                Subnet = @{
                    # /28 => 2^4 = 16 addresses => 192.168.x.240-255
                    # .240 & .255 can't be used as they are network & broadcast. And .241-.243 are reserved by Azure. 
                    # So the usable range is .244-.254. 
                    "Gateway" = "192.168.11.240/28"
                }
            }
        )
    },
    @{
        Name = "Dubai" 
        AddrSpaces = @(
            @{
                AddrSpace = "192.168.25.0/24"
                Subnet = @{ 
                    "Servers" = "192.168.25.0/25" 
                    "Clients" = "192.168.25.128/25"
                }
            },
            @{
                AddrSpace = "192.168.26.0/24"
                Subnet = @{
                    # /28 => 2^4 = 16 addresses => 192.168.x.240-255
                    # .240 & .255 can't be used as they are network & broadcast. And .241-.243 are reserved by Azure. 
                    # So the usable range is .244-.254. 
                    "Gateway" = "192.168.26.240/28"
                }
            }
        )
    },
    @{
        Name = "Muscat" 
        AddrSpaces = @(
            @{
                AddrSpace = "192.168.50.0/24"
                Subnet = @{ 
                    "Servers" = "192.168.50.0/25" 
                    "Clients" = "192.168.50.128/25"
                }
            },
            @{
                AddrSpace = "192.168.51.0/24"
                Subnet = @{
                    # /28 => 2^4 = 16 addresses => 192.168.x.240-255
                    # .240 & .255 can't be used as they are network & broadcast. And .241-.243 are reserved by Azure. 
                    # So the usable range is .244-.254. 
                    "Gateway" = "192.168.51.240/28"
                }
            }
        )
    }
)

# Here's my Azure VMs. Again, an array of hash-tables. 
# Note: I don't do any validation, so make sure all this is accurate. 
$AzureVMs = @(
    @{
        "Name" = "LONSDC01"
        "IPAddr" = "192.168.10.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "London"
        "Role" = "Primary DC"
    },
    @{
        "Name" = "DUBSDC01"
        "IPAddr" = "192.168.25.4"
        "Subnet" = "Servers"
        "AddrSpaceName" = "Dubai"
        "Role" = "DC"        
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
    # Create VirtualNetworkSite entries
    # Create the XML entries first 
    $VNSElement = $VNetConfigXML.CreateElement("VirtualNetworkSite")   

    # Set the attributes for the VirtualNetworkSites element
    $VNSElement.SetAttribute("name", $site.name)
    $VNSElement.SetAttribute("AffinityGroup", $AzureAffinityGroup)

    # VirtualNetworkSite has THREE Children
    # 1) AddressSpace
    # Create the AddressSpace element & its children AddressPrefix elements
    $AddrSpaceElement = $VNetConfigXML.CreateElement("AddressSpace")

    foreach ($addrspace in $site.AddrSpaces) {
        # Create a new AddressPrefix element
        $AddrPrefixElement = $VNetConfigXML.CreateElement("AddressPrefix")

        # Set its value
        $AddrPrefixElement.InnerText = $addrspace.AddrSpace

        # Add it as a child to the AddressSpace element
        $AddrSpaceElement.AppendChild($AddrPrefixElement)
    
    }

    # 2) Subnets
    # Create the Subnets element and child Subnet elements
    $SubnetsElement = $VNetConfigXML.CreateElement("Subnets")

    foreach ($addrspace in $site.AddrSpaces) {
        foreach ($subnet in $addrspace.Subnet) {
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
        }
    }


    # 3) Gateway (not always!)

    # Add the Subnets & AddressSpace elements as children to VirtualNetworkSites
    $VNSElement.AppendChild($AddrSpaceElement)
    $VNSElement.AppendChild($SubnetsElement)
    # <--- add Gateway too with logic that makes it optional


    # create LocalNetworkSite entries

    

    
    # pull this up!



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