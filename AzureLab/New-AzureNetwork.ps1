[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)]
    [ValidateScript( { Test-Path $_ } ) ]
    [string]$VNetConfigFile
)

try {
    if ($VNetConfigFile -match "^\.") { 
        # if the path is relative, convert it to absolute. Else the Set-AzureVNetConfig cmdlet fails. 
        $VNetConfigFile = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)\$(Split-Path -Leaf $VNetConfigFile)"
    }
    # Import VNet config. This will overwrite the existing config. 
    Write-Host -ForegroundColor Green "Initializing network config from $VNetConfigFile"
    Set-AzureVNetConfig -ConfigurationPath $VNetConfigFile
} 

catch {
    Write-Error "Something went wrong here!"
    break
}

Write-Host -ForegroundColor Green "Waiting 30 seconds ..."
Start-Sleep -Seconds 30

# If $VNetSite has a GatewaySites property, then initialize gateway
[bool]$GatewayPresent = 0 # false, assume no Gateway present
Write-Host -ForegroundColor Green "Checking if Gateways are required"
foreach ($VNetSite in $(Get-AzureVNetSite)) {
    Write-Host -ForegroundColor Green -NoNewline "`t * Checking $($VNetSite.Name)"
    if ($VNetSite.GatewaySites) { 
        Write-Host -ForegroundColor Green -NoNewline " ... yes!"
        New-AzureVNetGateway -VNetName $VNetSite.Name -GatewayType DynamicRouting 
        $GatewayPresent = 1 # yes there is a Gateway present
    } else { Write-Host -ForegroundColor Green -NoNewline " ... no!" }
    Write-Host ""
}


if ($GatewayPresent) {
    Write-Host -ForegroundColor Green "Initializing Gateways for sites that require it"
    Write-Host -ForegroundColor Green "Remember: Gateways are charged per gateway per hour!"

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
    Write-Host -ForegroundColor Green "Turning off encryption for the tunnels & setting the shared key $GatewayKey"
    foreach ($VNetSite in $(Get-AzureVNetSite)) {
        foreach ($LocalSite in $VNetSite.GatewaySites) {
            Write-Host -ForegroundColor Green "`t Shared key: $($VnetSite.Name) <--> $($LocalSite.Name)"
            Set-AzureVNetGatewayKey -VNetName $VNetSite.Name -SharedKey $GatewayKey -LocalNetworkSiteName $LocalSite.Name
            Write-Host -ForegroundColor Green "`t Encryption: $($VnetSite.Name) <--> $($LocalSite.Name)"
            Set-AzureVNetGatewayIPsecParameters -VNetName $VNetSite.Name -EncryptionType NoEncryption -LocalNetworkSiteName $LocalSite.Name
        }
    }
}