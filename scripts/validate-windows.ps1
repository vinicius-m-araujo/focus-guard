param([switch]$Race, [switch]$SkipInstall)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'FocusGuard desktop supports Windows only.' }
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$reportDir = Join-Path $root 'validation-results'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$script:results = @()
function Native {
    $command, $commandArgs = $args
    # PowerShell 5.1 turns redirected native stderr into error records.
    # Test warnings are diagnostic output; the process exit code decides success.
    $ErrorActionPreference = 'Continue'
    & $command @commandArgs
    $nativeExit = $LASTEXITCODE
    if ($nativeExit -ne 0) { throw "$command exited with code $nativeExit" }
}
function Check([string]$Name, [scriptblock]$Action) {
    Write-Host "`n== $Name =="
    $global:LASTEXITCODE = 0
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) { throw "Exit code $LASTEXITCODE" }
        $script:results += [pscustomobject]@{ Check = $Name; Result = 'PASS'; Detail = '' }
    } catch {
        $script:results += [pscustomobject]@{ Check = $Name; Result = 'FAIL'; Detail = $_.Exception.Message }
        Write-Warning $_.Exception.Message
    }
}
Check 'Platform policy' { & "$PSScriptRoot/test-windows-platform.ps1" }
Check 'Rule mirrors' {
    foreach ($dir in @('', 'cmd', 'internal', 'scripts', 'focusguard-ui')) {
        $source = Join-Path (Join-Path $root $dir) 'GEMINI.md'
        $mirror = Join-Path (Join-Path $root $dir) 'AGENT.md'
        if ((Get-FileHash $source).Hash -ne (Get-FileHash $mirror).Hash) { throw "Rule drift in $dir" }
    }
}
Check 'PowerShell syntax' {
    Get-ChildItem scripts -Filter '*.ps1' | ForEach-Object {
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$parseErrors)
        if ($parseErrors) { throw ($parseErrors -join "`n") }
    }
}
Check 'Installer UTF-8 BOM' {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $root 'scripts/install-daemon.ps1'))
    if (($bytes[0..2] -join ',') -ne '239,187,191') { throw 'Installer must retain UTF-8 BOM.' }
}
Check 'Go formatting' {
    $files = Native gofmt @('-l', 'cmd', 'internal', 'scripts')
    if ($LASTEXITCODE -ne 0 -or $files) { throw "Unformatted Go files: $files" }
}
Check 'IPC contract' { Native go @('run', './scripts/gen-contract/main.go', '--check') }
Push-Location focusguard-ui
try {
    if (-not $SkipInstall) { Check 'UI dependencies' { Native npm.cmd @('ci') } }
    Check 'UI tests' { Native npm.cmd @('test') }
    Check 'UI production build and types' { Native npm.cmd @('run', 'build') }
    Check 'UI dependency security audit' { Native npm.cmd @('audit', '--audit-level=high') }
} finally { Pop-Location }
Check 'Embed UI assets' {
    if (-not (Test-Path focusguard-ui/dist/index.html)) { throw 'UI build missing.' }
    Copy-Item focusguard-ui/dist/* cmd/focusguard-web/assets/ -Recurse -Force
}
Check 'Go build' { Native go @('build', './...') }
Check 'Go vet' { Native go @('vet', './...') }
Check 'Go tests and coverage' { Native go @('test', './...', '-count=1', '-timeout=120s', '-coverprofile=validation-results/coverage.out') }
Check 'Windows executables' {
    New-Item -ItemType Directory -Path bin -Force | Out-Null
    foreach ($binary in @('focusguard', 'focusguard-daemon', 'focusguard-web', 'focusguard-tray', 'focusguard-watchdog')) {
        Native go @('build', '-o', "bin/$binary.exe", "./cmd/$binary")
        if ($LASTEXITCODE -ne 0) { throw "Build failed: $binary" }
    }
}
Check 'Embedded tray icon' { Native go @('run', './scripts/verifyicon/main.go') }
Check 'Go dependency security audit' {
    Native go @('run', 'golang.org/x/vuln/cmd/govulncheck@v1.9.0', './...') |
        Tee-Object (Join-Path $reportDir 'govulncheck.txt')
}
if ($Race) { Check 'Go race detector' { Native go @('test', '-race', './...', '-count=1', '-timeout=600s') } }
$script:results | Format-Table -AutoSize
$script:results | ConvertTo-Json | Set-Content (Join-Path $reportDir 'checks.json') -Encoding UTF8
if ($script:results.Result -contains 'FAIL') { exit 1 }
