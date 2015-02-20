$VMName = ""
$InstanceSize = "Basic_A1"
$ImageName = "a699494373c04fc0bc8f2bb1389d6106__Win2K8R2SP1-Datacenter-201412.01-en.us-127GB.vhd"
$Location = "Southeast Asia"

$Domain = ""
$Subnet= "RAXNET1-24"
$IPAddress = "192.168.24.11"
$VNet = "RAXNET1"
$AdminPassword =""
$DomainPassword = ""

$VMConfig = New-AzureVMConfig -Name $VMName -InstanceSize $InstanceSize -ImageName $ImageName
$VMConfig | Add-AzureProvisioningConfig -WindowsDomain -Domain $Domain -DomainUserName "rakhesh" -DomainPassword $DomainPassword -JoinDomain $Domain `
            -DisableAutomaticUpdates -TimeZone "Arabian Standard Time" `
            -AdminUsername "rakhesh" -Password $AdminPassword

$VMConfig | Set-AzureSubnet -SubnetNames $Subnet
$VMConfig | Set-AzureStaticVNetIP -IPAddress $IPAddress

New-AzureService -ServiceName $VMName -Location $Location
New-AzureVM -ServiceName $VMName -VNetName $VNet