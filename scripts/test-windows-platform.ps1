$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$release = Get-Content (Join-Path $root '.goreleaser.yaml') -Raw
if ($release -match '(?m)^\s+- (id: .*linux|linux)\s*$') {
    throw 'GoReleaser must publish Windows desktop artifacts only.'
}
$linuxSources = Get-ChildItem (Join-Path $root 'cmd'), (Join-Path $root 'internal') -Recurse -Filter '*_linux*.go'
if ($linuxSources) { throw "Linux implementations remain: $($linuxSources.FullName -join ', ')" }
$ci = Get-Content (Join-Path $root '.github/workflows/test.yml') -Raw
if ($ci -notmatch 'runs-on: windows-latest') { throw 'Desktop validation must run on Windows.' }
if ($ci -match 'libgtk|appindicator|linux-full-suite') { throw 'Desktop CI still depends on Linux.' }
if (Test-Path (Join-Path $root 'android')) { throw 'Android module must be removed.' }
Write-Host 'Windows platform policy: PASS'
