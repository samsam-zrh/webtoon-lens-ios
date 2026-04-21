param(
    [int]$Port = 8787
)

$ErrorActionPreference = "Stop"

$previewPath = Resolve-Path "$PSScriptRoot\..\PhonePreview"
$ipConfig = Get-NetIPConfiguration |
    Where-Object {
        $_.IPv4Address -and
        $_.NetAdapter.Status -eq "Up" -and
        $_.IPv4DefaultGateway
    } |
    Select-Object -First 1

if ($ipConfig) {
    $ip = $ipConfig.IPv4Address.IPAddress
} else {
    $ip = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object {
            $_.IPAddress -notlike "127.*" -and
            $_.IPAddress -notlike "169.254.*" -and
            $_.PrefixOrigin -ne "WellKnown"
        } |
        Select-Object -First 1 -ExpandProperty IPAddress
}

if (-not $ip) {
    $ip = "localhost"
}

Write-Host ""
Write-Host "Webtoon Lens phone preview"
Write-Host "PC:    http://localhost:$Port"
Write-Host "Phone: http://$ip`:$Port"
Write-Host ""
Write-Host "Keep this window open. Put your phone on the same Wi-Fi."
Write-Host ""

Push-Location $previewPath
try {
    $env:WEBTOON_LENS_PREVIEW_PORT = "$Port"
    python .\server.py
}
finally {
    Pop-Location
}
