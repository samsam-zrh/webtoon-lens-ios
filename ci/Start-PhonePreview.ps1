param(
    [int]$Port = 8787,
    [switch]$Lan
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
Write-Host "Lecteur local Webtoon Lens"
Write-Host "PC:    http://localhost:$Port"
if ($Lan) { Write-Host "Téléphone : http://$ip`:$Port" }
Write-Host ""
Write-Host "Gardez cette fenêtre ouverte. Ajoutez -Lan pour un réseau privé de confiance."
Write-Host ""

Push-Location $previewPath
try {
    $env:WEBTOON_LENS_PREVIEW_PORT = "$Port"
    $env:WEBTOON_LENS_PREVIEW_HOST = if ($Lan) { "0.0.0.0" } else { "127.0.0.1" }
    python .\server.py
}
finally {
    Pop-Location
}
