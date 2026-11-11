# Build LightCraft with the additional extensions applied (Windows, PowerShell 5.1 or 7).
#
#   powershell -ExecutionPolicy Bypass -File scripts\build.ps1            build the app
#   powershell -ExecutionPolicy Bypass -File scripts\build.ps1 -Work D:\lcx   choose where sources go
#
# The same steps as scripts/build.sh: fetch the release named in upstream.lock, check the pinned
# commit, apply patches\*.patch on a fresh branch, fetch the pinned craft-fonts (Chinese UI
# fonts) and run `cargo build --release --locked -p lightcraft --features lightcraft/heif`. The app is
# <work>\lightcraft\target\release\lightcraft.exe. Upstream's packaging\windows\package.ps1 makes
# an installer from that tree if you want one (it needs the WiX toolset).
#
# Needs: Git for Windows, a Rust toolchain (rustup, MSVC; Rust 1.95 or newer) and the Visual
# Studio C++ build tools.
param([string]$Work = "")
$ErrorActionPreference = "Stop"

$here = Split-Path -Parent $PSScriptRoot
$lock = @{}
foreach ($line in Get-Content (Join-Path $here "upstream.lock")) {
    if ($line -match '^\s*([A-Z_]+)=(.*)$') { $lock[$Matches[1]] = $Matches[2].Trim() }
}
if ($Work -eq "") { $Work = Join-Path $here "build" }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
$Work = (Resolve-Path $Work).Path
$src = Join-Path $Work "lightcraft"

function Git-Run {
    & git @args
    if ($LASTEXITCODE -ne 0) { throw "git $args failed" }
}

foreach ($tool in "git", "cargo") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not installed" }
}

Write-Host "==> LightCraft $($lock.UPSTREAM_TAG)"
if (-not (Test-Path (Join-Path $src ".git"))) {
    Git-Run init -q $src
    Git-Run -C $src remote add origin $lock.UPSTREAM_REPO
}
# LF files, as the patches have: every command below (checkout, clean, am) uses this repo setting
Git-Run -C $src config core.autocrlf false
Git-Run -C $src fetch -q --depth 1 origin "refs/tags/$($lock.UPSTREAM_TAG):refs/tags/$($lock.UPSTREAM_TAG)"
$actual = (& git -C $src rev-list -n 1 $lock.UPSTREAM_TAG).Trim()
if ($actual -ne $lock.UPSTREAM_COMMIT) {
    throw "$($lock.UPSTREAM_TAG) is $actual upstream, not the pinned $($lock.UPSTREAM_COMMIT)"
}

$patches = Get-ChildItem (Join-Path $here "patches") -Filter *.patch | Sort-Object Name | ForEach-Object { $_.FullName }
Write-Host "==> applying $($patches.Count) patches"
# no `git am` in progress is the usual case: its error must not stop the script (PowerShell 5.1)
& { $ErrorActionPreference = 'Continue'; & git -C $src am --abort 2>$null | Out-Null }
Git-Run -C $src checkout -q --force -B lcx $lock.UPSTREAM_TAG
Git-Run -C $src clean -qfd
# no 3-way fallback: a patch that no longer applies fails the same way in every work dir
Git-Run -C $src -c "user.name=LightCraft additional extensions" -c "user.email=noreply@example.invalid" am -q @patches

$fonts = Join-Path $Work "craft-fonts"
Write-Host "==> craft-fonts $($lock.CRAFT_FONTS_REV)"
if (-not (Test-Path (Join-Path $fonts ".git"))) {
    if (Test-Path $fonts) { Remove-Item -Recurse -Force $fonts }
    Git-Run clone -q --no-checkout $lock.CRAFT_FONTS_REPO $fonts
}
& { $ErrorActionPreference = 'Continue'; & git -C $fonts rev-parse -q --verify "$($lock.CRAFT_FONTS_REV)^{commit}" 2>$null | Out-Null }
if ($LASTEXITCODE -ne 0) { Git-Run -C $fonts fetch -q origin $lock.CRAFT_FONTS_REV }
# every run: the pinned revision, with any missing or changed file put back
Git-Run -C $fonts checkout -q --force --detach $lock.CRAFT_FONTS_REV
$env:CRAFT_FONTS_DIR = $fonts
# fail the build rather than ship a UI whose Chinese is empty boxes
$env:CRAFT_FONTS_REQUIRED = "1"

Push-Location $src
try {
    # HEIC/HEIF photos open, as in upstream's release builds
    & cargo build --release --locked -p lightcraft --features lightcraft/heif
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
} finally {
    Pop-Location
}
Write-Host "==> done: $src\target\release\lightcraft.exe"
