[CmdletBinding()]
Param(
[Parameter(Position=0, Mandatory=$true)]
[string]$ServiceName
)

$VM = Get-AzureVM -ServiceName $ServiceName
$VMPort =  (Get-AzureEndpoint -VM $VM -Name "Remote Desktop").Port
if ($VMPort -eq $null) { $VMPort = (Get-AzureEndpoint -VM $VM -Name "RemoteDesktop").Port }

$VMName = ([system.uri]$VM.DNSName).Host

Start-Process "mstsc" -ArgumentList "/v ${VMName}:$VMPort /f"