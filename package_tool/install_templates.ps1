param(
    [string]$Version = "4.7.2.stable",
    [string]$Url = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$dir = Join-Path $env:APPDATA ("Godot\export_templates\{0}" -f $Version)
$probe = Join-Path $dir "windows_release_x86_64.exe"

if (Test-Path $probe) {
    Write-Host "[templates] already installed: $dir"
    exit 0
}

Write-Host "[templates] not found for $Version, installing..."
Write-Host "[templates] downloading: $Url"
Write-Host "[templates] (~1.2GB, one-time; please wait)"

$zip = Join-Path $env:TEMP ("godot_tpl_{0}.zip" -f $Version)
$ex  = Join-Path $env:TEMP ("godot_tpl_{0}" -f $Version)

try {
    Invoke-WebRequest -Uri $Url -OutFile $zip -MaximumRedirection 5
} catch {
    Write-Host "[ERROR] download failed: $($_.Exception.Message)"
    exit 2
}

if (Test-Path $ex) { Remove-Item $ex -Recurse -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $ex)
} catch {
    Write-Host "[ERROR] extract failed: $($_.Exception.Message)"
    exit 3
}

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item (Join-Path $ex "templates\*") $dir -Recurse -Force

Remove-Item $zip -Force -ErrorAction SilentlyContinue
Remove-Item $ex -Recurse -Force -ErrorAction SilentlyContinue

if (Test-Path $probe) {
    Write-Host "[templates] installed OK: $dir"
    exit 0
} else {
    Write-Host "[ERROR] install finished but template still missing: $probe"
    exit 4
}
