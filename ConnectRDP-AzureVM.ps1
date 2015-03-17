[CmdletBinding()]
Param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$ServiceName
)

$VM = Get-AzureVM -ServiceName $ServiceName
$VMEndPoints = $VM | Get-AzureEndpoint
$VMRDPEndPoints = $VMEndPoints | ?{ $_.Name -match "Remote\s?Desktop" }

if ($VMRDPEndPoints.Length -eq 0) {
    Write-Host -ForegroundColor Green "No RDP ports"
    $VMPort = Get-Random -Minimum 1025 -Maximum 65530
    Write-Host -ForegroundColor Green "Created port $VMPort and assigning to VM"
    $VM | Add-AzureEndpoint -Name RemoteDesktop -Protocol TCP -LocalPort 3389 -PublicPort $VMPort
    $VM | Update-AzureVM
} else {
    $VMPort =  $VMRDPEndPoints[0].Port
    Write-Host -ForegroundColor Green "Found port $VMPort"
}

# Convert https://xxxx.cloudapp.net/ -> xxxx
$VMName = ([system.uri]$VM.DNSName).Host

Start-Process "mstsc" -ArgumentList "/v ${VMName}:$VMPort /f"