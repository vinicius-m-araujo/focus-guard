param(
    [Parameter(Mandatory=$false)]
    [string]$CertificatePath,

    [Parameter(Mandatory=$false)]
    [string]$CertificatePassword,

    [Parameter(Mandatory=$false)]
    [string]$SearchPath = ".",

    [Parameter(Mandatory=$false)]
    [string]$TimestampServer = "http://timestamp.digicert.com",

    [Parameter(Mandatory=$false)]
    [string]$Description = "FocusGuard - bloqueio focado de distracoes",

    [Parameter(Mandatory=$false)]
    [switch]$VerifyOnly,

    [Parameter(Mandatory=$false)]
    [switch]$TestCert,

    [Parameter(Mandatory=$false)]
    [string]$CertThumbprint,

    [Parameter(Mandatory=$false)]
    [switch]$NoTimestamp
)

# sign-windows.ps1 - Assina binarios Windows (.exe, .msi) com Authenticode.
#
# Uso com certificado oficial (PFX):
#   .\scripts\sign-windows.ps1 -CertificatePath cert.pfx -CertificatePassword "senha" -SearchPath "bin"
#
# Uso com certificado local de teste (auto-assinado / desenvolvimento):
#   .\scripts\sign-windows.ps1 -TestCert -SearchPath "bin"
#
# Uso com certificado do repositorio Windows por Thumbprint:
#   .\scripts\sign-windows.ps1 -CertThumbprint "THUMBPRINT" -SearchPath "bin"
#
# Apenas verificar assinaturas existentes:
#   .\scripts\sign-windows.ps1 -SearchPath "bin" -VerifyOnly
#
# CI (GitHub Actions):
#   O certificado e salvo como GitHub Secret (base64 do PFX) e decodificado
#   antes de chamar este script. Ver .github/workflows/release.yml -> sign-windows.
#
# O script e idempotente: arquivos ja assinados sao ignorados (verificacao
# automatica via Get-AuthenticodeSignature). Suporta signtool.exe ou o motor
# nativo Set-AuthenticodeSignature do PowerShell como fallback.

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------- Validacoes
if (-not (Test-Path $SearchPath)) {
    Write-Error "Diretorio nao encontrado: $SearchPath"
    exit 1
}

$isTestCert = $false
$certObj = $null

if ($TestCert) {
    $isTestCert = $true
    # Procurar certificado de teste existente no repositorio do usuario
    $existing = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Subject -match "CN=FocusGuard Development Test" -and $_.NotAfter -gt (Get-Date) } |
        Select-Object -First 1

    if ($existing) {
        $certObj = $existing
        Write-Host "==> Usando certificado de teste existente: $($certObj.Subject) [Thumbprint: $($certObj.Thumbprint)]" -ForegroundColor Cyan
    } elseif (-not $VerifyOnly) {
        Write-Host "==> Criando novo certificado de teste auto-assinado (Authenticode)..." -ForegroundColor Yellow
        $certObj = New-SelfSignedCertificate `
            -Type CodeSigningCert `
            -Subject "CN=FocusGuard Development Test" `
            -CertStoreLocation "Cert:\CurrentUser\My" `
            -FriendlyName "FocusGuard Development Test" `
            -NotAfter (Get-Date).AddYears(1) `
            -HashAlgorithm "SHA256"
        Write-Host "==> Certificado de teste criado: $($certObj.Subject) [Thumbprint: $($certObj.Thumbprint)]" -ForegroundColor Green
    }
} elseif ($VerifyOnly) {
    # Modo apenas verificacao geral - dispensa certificado
} elseif ($CertThumbprint) {
    $cleanThumb = $CertThumbprint.Replace(" ", "").ToUpper()
    $certObj = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $cleanThumb } |
        Select-Object -First 1

    if (-not $certObj) {
        Write-Error "Certificado com thumbprint '$CertThumbprint' nao encontrado nos repositorios Cert:\CurrentUser\My ou Cert:\LocalMachine\My."
        exit 1
    }
    Write-Host "==> Usando certificado do repositorio: $($certObj.Subject) [Thumbprint: $($certObj.Thumbprint)]" -ForegroundColor Cyan
} elseif ($CertificatePath) {
    if (-not (Test-Path $CertificatePath)) {
        Write-Error "Certificado nao encontrado: $CertificatePath"
        exit 1
    }
    if ($CertificatePassword) {
        $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath, $CertificatePassword)
    } else {
        $certObj = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath)
    }
} else {
    $helpMsg = "Certificado nao especificado.`n" +
        "Formas de uso:`n" +
        "  1) Certificado PFX oficial:`n" +
        "     .\scripts\sign-windows.ps1 -CertificatePath cert.pfx -CertificatePassword `"senha`" -SearchPath `"bin`"`n" +
        "  2) Certificado local de teste (auto-assinado):`n" +
        "     .\scripts\sign-windows.ps1 -TestCert -SearchPath `"bin`"`n" +
        "  3) Certificado por Thumbprint:`n" +
        "     .\scripts\sign-windows.ps1 -CertThumbprint `"THUMBPRINT`" -SearchPath `"bin`"`n" +
        "  4) Apenas verificar assinaturas existentes:`n" +
        "     .\scripts\sign-windows.ps1 -SearchPath `"bin`" -VerifyOnly"
    Write-Error $helpMsg
    exit 1
}

# ---------------------------------------------------------------- Encontrar signtool.exe (ou fallback PowerShell)
$signtool = $null
$cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
if ($cmd) {
    $signtool = $cmd.Source
} else {
    $sdks = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\x64\signtool.exe",
        "${env:ProgramFiles(x86)}\Windows Kits\10\bin\x86\signtool.exe",
        "${env:ProgramFiles}\Windows Kits\10\bin\x64\signtool.exe"
    )
    foreach ($sdk in $sdks) {
        if (Test-Path $sdk) {
            $signtool = $sdk
            break
        }
    }
    if (-not $signtool) {
        $kitVersioned = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName -Last 1
        if ($kitVersioned) {
            $signtool = $kitVersioned
        }
    }
}

if ($signtool) {
    Write-Host "==> Usando signtool: $signtool" -ForegroundColor Cyan
} else {
    Write-Host "==> signtool.exe nao encontrado; usando motor nativo Set-AuthenticodeSignature do PowerShell." -ForegroundColor Yellow
}

# ---------------------------------------------------------------- Encontrar arquivos
$files = Get-ChildItem -Path $SearchPath -Recurse -Include *.exe,*.msi -File
if ($files.Count -eq 0) {
    Write-Host "Nenhum arquivo .exe ou .msi encontrado em $SearchPath" -ForegroundColor Yellow
    exit 0
}

Write-Host "==> Encontrados $($files.Count) arquivo(s) em ${SearchPath}:" -ForegroundColor Cyan
foreach ($f in $files) {
    $rel = $f.FullName.Replace("$((Resolve-Path $SearchPath).Path)\", "")
    Write-Host "  - $rel" -ForegroundColor Gray
}

# ---------------------------------------------------------------- Verificar se ja assinados
$toSign = @()
$alreadySigned = @()
foreach ($f in $files) {
    $sig = Get-AuthenticodeSignature -FilePath $f.FullName
    if ($sig.Status -eq "Valid") {
        $alreadySigned += $f
        $rel = $f.FullName.Replace("$((Resolve-Path $SearchPath).Path)\", "")
        Write-Host "  [SKIP] $rel - ja assinado (Status: Valid)" -ForegroundColor DarkGray
    } elseif ($isTestCert -and $sig.SignerCertificate -ne $null -and $certObj -and $sig.SignerCertificate.Thumbprint -eq $certObj.Thumbprint) {
        $alreadySigned += $f
        $rel = $f.FullName.Replace("$((Resolve-Path $SearchPath).Path)\", "")
        Write-Host "  [SKIP] $rel - ja assinado com este certificado de teste" -ForegroundColor DarkGray
    } else {
        $toSign += $f
    }
}

if ($alreadySigned.Count -gt 0) {
    Write-Host "" -ForegroundColor Gray
    Write-Host "  $($alreadySigned.Count) arquivo(s) ja assinado(s) - ignorando." -ForegroundColor Yellow
}

if ($toSign.Count -eq 0) {
    Write-Host "" -ForegroundColor Green
    Write-Host "==> Todos os arquivos ja estao assinados." -ForegroundColor Green
    exit 0
}

if ($VerifyOnly) {
    Write-Host "" -ForegroundColor Yellow
    Write-Host "==> Modo verificacao: $($toSign.Count) arquivo(s) NAO assinado(s) ou invalidos:" -ForegroundColor Yellow
    foreach ($f in $toSign) {
        $rel = $f.FullName.Replace("$((Resolve-Path $SearchPath).Path)\", "")
        $sig = Get-AuthenticodeSignature -FilePath $f.FullName
        Write-Host "  [FAIL] $rel - Status: $($sig.Status)" -ForegroundColor Red
    }
    exit 1
}

# ---------------------------------------------------------------- Assinar
Write-Host "" -ForegroundColor Gray
Write-Host "==> Assinando $($toSign.Count) arquivo(s)..." -ForegroundColor Green

$signed = 0
$failed = 0
$useTimestamp = (-not $NoTimestamp) -and (-not [string]::IsNullOrWhiteSpace($TimestampServer))

foreach ($f in $toSign) {
    $rel = $f.FullName.Replace("$((Resolve-Path $SearchPath).Path)\", "")
    Write-Host "  Assinando: $rel" -ForegroundColor Cyan -NoNewline

    try {
        if ($signtool -and $CertificatePath) {
            $signArgs = @("sign", "/f", $CertificatePath)
            if ($CertificatePassword) {
                $signArgs += @("/p", $CertificatePassword)
            }
            $signArgs += @("/fd", "SHA256")
            if ($useTimestamp) {
                $signArgs += @("/tr", $TimestampServer, "/td", "SHA256")
            }
            $signArgs += @("/d", $Description)
            $signArgs += $f.FullName

            $result = & $signtool $signArgs 2>&1
            if ($LASTEXITCODE -ne 0 -and $useTimestamp) {
                # Tentar sem timestamp se o timestamp server falhar
                $signArgsNoTs = @("sign", "/f", $CertificatePath)
                if ($CertificatePassword) { $signArgsNoTs += @("/p", $CertificatePassword) }
                $signArgsNoTs += @("/fd", "SHA256", "/d", $Description, $f.FullName)
                $result = & $signtool $signArgsNoTs 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                $sig = Get-AuthenticodeSignature -FilePath $f.FullName
                if ($sig.Status -eq "Valid" -or $sig.SignerCertificate -ne $null) {
                    Write-Host " [OK]" -ForegroundColor Green
                    $signed++
                } else {
                    Write-Host " [WARN: $($sig.Status)]" -ForegroundColor Yellow
                    $signed++
                }
            } else {
                Write-Host " [ERRO]" -ForegroundColor Red
                Write-Host "    $result" -ForegroundColor Red
                $failed++
            }
        } elseif ($signtool -and $certObj -and -not $CertificatePath) {
            $signArgs = @("sign", "/sha1", $certObj.Thumbprint, "/s", "My", "/fd", "SHA256")
            if ($useTimestamp) {
                $signArgs += @("/tr", $TimestampServer, "/td", "SHA256")
            }
            $signArgs += @("/d", $Description, $f.FullName)

            $result = & $signtool $signArgs 2>&1
            if ($LASTEXITCODE -ne 0 -and $useTimestamp) {
                $signArgsNoTs = @("sign", "/sha1", $certObj.Thumbprint, "/s", "My", "/fd", "SHA256", "/d", $Description, $f.FullName)
                $result = & $signtool $signArgsNoTs 2>&1
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Host " [OK]" -ForegroundColor Green
                $signed++
            } else {
                # Fallback para Set-AuthenticodeSignature
                $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $certObj -HashAlgorithm SHA256
                if ($sig.SignerCertificate -ne $null) {
                    Write-Host " [OK - Set-AuthenticodeSignature]" -ForegroundColor Green
                    $signed++
                } else {
                    Write-Host " [ERRO]" -ForegroundColor Red
                    Write-Host "    $result" -ForegroundColor Red
                    $failed++
                }
            }
        } else {
            # Motor nativo PowerShell Set-AuthenticodeSignature
            $sig = $null
            if ($useTimestamp) {
                try {
                    $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $certObj -HashAlgorithm SHA256 -TimestampServer $TimestampServer -ErrorAction Stop
                } catch {
                    $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $certObj -HashAlgorithm SHA256 -ErrorAction Stop
                }
            } else {
                $sig = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $certObj -HashAlgorithm SHA256 -ErrorAction Stop
            }

            if ($sig.Status -eq "Valid") {
                Write-Host " [OK]" -ForegroundColor Green
                $signed++
            } elseif ($sig.SignerCertificate -ne $null) {
                Write-Host " [OK - TestCert]" -ForegroundColor Green
                $signed++
            } else {
                Write-Host " [ERRO: $($sig.Status)]" -ForegroundColor Red
                Write-Host "    $($sig.StatusMessage)" -ForegroundColor Red
                $failed++
            }
        }
    } catch {
        Write-Host " [EXCECAO]" -ForegroundColor Red
        Write-Host "    $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

# ---------------------------------------------------------------- Resumo
Write-Host "" -ForegroundColor Gray
Write-Host "==> Resumo da assinatura:" -ForegroundColor Cyan
Write-Host "  Assinados: $signed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Falhas:    $failed" -ForegroundColor Red
}
if ($alreadySigned.Count -gt 0) {
    Write-Host "  Ignorados: $($alreadySigned.Count) (ja assinados)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------- Verificacao final
Write-Host "" -ForegroundColor Gray
Write-Host "==> Verificando assinaturas..." -ForegroundColor Cyan
$allFiles = Get-ChildItem -Path $SearchPath -Recurse -Include *.exe,*.msi -File
$valid = 0
$invalid = 0
foreach ($f in $allFiles) {
    $sig = Get-AuthenticodeSignature -FilePath $f.FullName
    $rel = $f.FullName.Replace("$((Resolve-Path $SearchPath).Path)\", "")
    if ($sig.Status -eq "Valid") {
        Write-Host "  [OK] $rel (Valid)" -ForegroundColor Green
        $valid++
    } elseif ($sig.SignerCertificate -ne $null -and ($isTestCert -or ($certObj -and $sig.SignerCertificate.Thumbprint -eq $certObj.Thumbprint))) {
        Write-Host "  [OK - TestCert] $rel ($($sig.SignerCertificate.Subject))" -ForegroundColor Cyan
        $valid++
    } else {
        Write-Host "  [FAIL] $rel - $($sig.Status): $($sig.StatusMessage)" -ForegroundColor Red
        $invalid++
    }
}

Write-Host "" -ForegroundColor Gray
if ($invalid -gt 0) {
    Write-Host "==> $invalid arquivo(s) com assinatura invalida!" -ForegroundColor Red
    exit 1
} else {
    Write-Host "==> Todos os $valid arquivo(s) estao assinados corretamente." -ForegroundColor Green
    exit 0
}
