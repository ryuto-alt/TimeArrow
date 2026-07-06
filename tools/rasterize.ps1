$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$root   = Split-Path -Parent $PSScriptRoot
$srcDir = Join-Path $root "assets\textures\src"
$outDir = Join-Path $root "assets\textures"

$browser = @(
  "C:\Program Files\Google\Chrome\Application\chrome.exe",
  "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
  "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $browser) { throw "Chrome/Edge not found for headless rasterize" }

$udd = Join-Path $env:TEMP "timearrow-rasterize-profile-$PID"
New-Item -ItemType Directory -Force -Path $udd | Out-Null

$targets = @(
  @{ name = "crushwall"; w = 320; h = 384 },
  @{ name = "bomb";      w = 220; h = 260 },
  @{ name = "ball";      w = 256; h = 256 },
  @{ name = "pendulum";  w = 200; h = 320 },
  @{ name = "vinevert";  w = 160; h = 384 },
  @{ name = "arrow";     w = 240; h = 72  },
  @{ name = "button";    w = 200; h = 90  },
  @{ name = "lattice";   w = 200; h = 400 },
  @{ name = "mirror";    w = 240; h = 240 }
)

foreach ($t in $targets) {
  $svgPath = Join-Path $srcDir "$($t.name).svg"
  if (-not (Test-Path $svgPath)) { Write-Host "SKIP (no svg): $($t.name)" -ForegroundColor Yellow; continue }
  $svgContent = Get-Content -Raw -Path $svgPath

  $htmlPath = Join-Path $outDir "_$($t.name).html"
  $html = @"
<!doctype html>
<html><head><meta charset="utf-8"><style>
  html,body{margin:0;padding:0;background:transparent;overflow:hidden;}
</style></head><body>
$svgContent
</body></html>
"@
  Set-Content -Path $htmlPath -Value $html -Encoding UTF8

  $pngPath = Join-Path $outDir "$($t.name)_rgba.png"
  if (Test-Path $pngPath) { Remove-Item -Force $pngPath }

  $winSize = "$($t.w),$($t.h)"
  $fileUrl = "file:///$($htmlPath -replace '\\','/')"
  $argList = @(
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
    "--user-data-dir=$udd", "--default-background-color=00000000",
    "--window-size=$winSize", "--screenshot=$pngPath", $fileUrl
  )
  $proc = Start-Process -FilePath $browser -ArgumentList $argList -Wait -PassThru -NoNewWindow
  Remove-Item -Force $htmlPath -ErrorAction SilentlyContinue

  if (Test-Path $pngPath) {
    Write-Host "OK: $($t.name) -> $pngPath"
  } else {
    Write-Host "FAILED: $($t.name)" -ForegroundColor Red
  }
}
