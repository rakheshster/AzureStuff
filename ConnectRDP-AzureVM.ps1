[CmdletBinding()]
Param(
  [Parameter(Position=0, Mandatory=$true)]
  [string]$ServiceName
)

$VM = Get-AzureVM -ServiceName $ServiceName
$port =  (Get-AzureEndpoint -VM $VM -Name "Remote Desktop").Port
$ip = (Get-AzureEndpoint -VM $VM -Name "Remote Desktop").Vip

Start-Process "mstsc" -ArgumentList "/v ${ip}:$port /f"