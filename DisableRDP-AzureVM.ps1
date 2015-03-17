[CmdletBinding()]
Param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$ServiceName
)

$VM = Get-AzureVM -ServiceName $ServiceName 

try {
    $VM | Remove-AzureEndpoint -Name "RemoteDesktop" | Update-AzureVM
}
catch {
    $VM | Remove-AzureEndpoint -Name "Remote Desktop" | Update-AzureVM
}