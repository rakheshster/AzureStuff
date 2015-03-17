Get-AzureVNetSite | %{ Remove-AzureVNetGateway -VNetName $_.Name }

Write-Host -ForegroundColor Yellow "Waiting 30 seconds"
Start-Sleep -Seconds 30
Set-AzureVNetConfig -ConfigurationPath D:\Dropbox\Scripts\AzureStuff\AzureLab\AzureVNet-Empty.xml

Get-AzureVNetSite | %{ Remove-AzureVNetGateway -VNetName $_.Name }