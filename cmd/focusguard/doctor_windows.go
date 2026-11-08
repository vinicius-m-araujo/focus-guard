//go:build windows

package main

import (
	"os"
	"path/filepath"
	"strings"
)

// stateFilePath localiza o state.json na instalação Windows (%PROGRAMDATA%).
func stateFilePath() string {
	return filepath.Join(os.Getenv("PROGRAMDATA"), "FocusGuard", "state.json")
}

// hostsFilePath localiza o arquivo hosts do Windows.
func hostsFilePath() string {
	return `C:\Windows\System32\drivers\etc\hosts`
}

// isElevated reporta se o processo atual roda com privilégio de
// administrador. No Windows a forma stdlib confiável é tentar um comando que
// só um admin consegue executar (net session falha com acesso negado para
// usuários comuns).
func isElevated() bool {
	out, err := execCommand("net", "session").CombinedOutput()
	if err != nil {
		_ = out
		return false
	}
	return true
}

// queryService consulta o estado de um serviço Windows via sc query. Um
// serviço inexistente (exit 1060) vira serviceMissing; qualquer outra falha
// de execução é reportada como erro.
func queryService(exec func(string, ...string) ([]byte, error), name string) (serviceState, error) {
	out, err := exec("sc", "query", name)
	if err != nil {
		if strings.Contains(strings.ToLower(string(out)), "1060") || strings.Contains(strings.ToLower(err.Error()), "1060") {
			return serviceMissing, nil
		}
		return serviceMissing, err
	}
	lower := strings.ToLower(string(out))
	if strings.Contains(lower, "running") {
		return serviceRunning, nil
	}
	return serviceInstalled, nil
}

func platformCheckDefender(env doctorEnv) doctorResult {
	if env.exec == nil {
		return doctorResult{Name: "Windows Defender", Status: statusPass, Message: "não verificado"}
	}

	psScript := "$thr = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.ThreatName -match 'HostsFileHijack|FocusGuard' -or $_.Resources -match 'hosts' } | Select-Object -ExpandProperty ThreatName; " +
		"$pref = Get-MpPreference -ErrorAction SilentlyContinue; " +
		"$exPaths = $pref.ExclusionPath -join ';'; " +
		"$exProcs = $pref.ExclusionProcess -join ';'; " +
		"$fw = (Get-Service mpssvc -ErrorAction SilentlyContinue).Status; " +
		"$p53 = try { $u = [System.Net.Sockets.UdpClient]::new(53); $u.Close(); 'Free' } catch { 'Blocked: ' + $_.Exception.Message }; " +
		"$ics = (Get-Service SharedAccess -ErrorAction SilentlyContinue).Status; " +
		"Write-Output ('THREATS:' + ($thr -join ';')); " +
		"Write-Output ('EX_PATHS:' + $exPaths); " +
		"Write-Output ('EX_PROCS:' + $exProcs); " +
		"Write-Output ('FIREWALL:' + $fw); " +
		"Write-Output ('PORT53:' + $p53); " +
		"Write-Output ('ICS:' + $ics)"

	out, err := env.exec("powershell", "-NoProfile", "-NonInteractive", "-Command", psScript)
	if err != nil {
		// Defender pode estar desativado ou outro antivírus ativo
		return doctorResult{Name: "Windows Defender", Status: statusPass, Message: "Windows Defender não ativo ou gerenciado por terceiros"}
	}

	lines := strings.Split(string(out), "\n")
	var threats, exPaths, exProcs, firewall, port53, ics string
	hasTags := false

	for _, l := range lines {
		l = strings.TrimSpace(l)
		switch {
		case strings.HasPrefix(l, "THREATS:"):
			threats = strings.TrimPrefix(l, "THREATS:")
			hasTags = true
		case strings.HasPrefix(l, "EX_PATHS:"):
			exPaths = strings.TrimPrefix(l, "EX_PATHS:")
			hasTags = true
		case strings.HasPrefix(l, "EX_PROCS:"):
			exProcs = strings.TrimPrefix(l, "EX_PROCS:")
			hasTags = true
		case strings.HasPrefix(l, "FIREWALL:"):
			firewall = strings.TrimPrefix(l, "FIREWALL:")
			hasTags = true
		case strings.HasPrefix(l, "PORT53:"):
			port53 = strings.TrimPrefix(l, "PORT53:")
			hasTags = true
		case strings.HasPrefix(l, "ICS:"):
			ics = strings.TrimPrefix(l, "ICS:")
			hasTags = true
		}
	}

	if !hasTags {
		// Fallback para saídas legadas ou mockadas simples
		outStr := strings.ToLower(string(out))
		if strings.Contains(outStr, "focusguard") {
			return doctorResult{Name: "Windows Defender", Status: statusPass, Message: "FocusGuard está na lista de exclusões do Windows Defender"}
		}
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusWarn,
			Message: "FocusGuard não está na lista de exclusões do Windows Defender (pode gerar falsos positivos)",
			Fix:     "Execute no PowerShell como Administrador: Add-MpPreference -ExclusionPath 'C:\\Program Files\\FocusGuard', '$env:ProgramData\\FocusGuard' -ExclusionProcess 'focusguard-daemon.exe','focusguard.exe'",
		}
	}

	// 1. Verificação de ameaças / falsos positivos (ex: HostsFileHijack)
	if strings.TrimSpace(threats) != "" {
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusFail,
			Message: "Windows Defender detectou ameaça/falso positivo (" + threats + ") no arquivo hosts ou FocusGuard",
			Fix:     "Abra Segurança do Windows > Proteção contra vírus e ameaças > Histórico de proteção, selecione 'Permitir no dispositivo' e adicione exclusão: Add-MpPreference -ExclusionPath 'C:\\Windows\\System32\\drivers\\etc\\hosts' -ExclusionProcess 'focusguard-daemon.exe'",
		}
	}

	// 2. Verificação do serviço Windows Defender Firewall (mpssvc)
	if firewall != "" && !strings.EqualFold(firewall, "Running") {
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusWarn,
			Message: "serviço Windows Defender Firewall (mpssvc) parado (" + firewall + ") — regras de bloqueio de rede inativas",
			Fix:     "Inicie o serviço do firewall no PowerShell como Administrador: Start-Service mpssvc (ou 'net start mpssvc').",
		}
	}

	// 3. Verificação de conflito / bloqueio na porta 53 (DNS)
	if strings.HasPrefix(port53, "Blocked") {
		if strings.EqualFold(ics, "Running") {
			return doctorResult{
				Name:    "Windows Defender",
				Status:  statusWarn,
				Message: "porta 53/DNS está bloqueada ou em uso (" + port53 + "), em conflito com o Compartilhamento de Conexão (SharedAccess)",
				Fix:     "Desative o serviço SharedAccess: Stop-Service SharedAccess; Set-Service SharedAccess -StartupType Manual",
			}
		}
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusWarn,
			Message: "porta 53/DNS está bloqueada ou em uso (" + port53 + ")",
			Fix:     "Verifique se outro serviço DNS ou firewall está bloqueando a porta 53.",
		}
	}

	// 4. Verificação de exclusões do Windows Defender
	lowerPaths := strings.ToLower(exPaths)
	lowerProcs := strings.ToLower(exProcs)

	if strings.Contains(lowerPaths, "must be an administrator") {
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusPass,
			Message: "Windows Defender ativo; execute o doctor como administrador para inspecionar a lista de exclusões",
		}
	}

	hasFocusGuard := strings.Contains(lowerPaths, "focusguard") || strings.Contains(lowerProcs, "focusguard")
	hasHosts := strings.Contains(lowerPaths, "hosts")

	if hasFocusGuard && hasHosts {
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusPass,
			Message: "FocusGuard e arquivo hosts protegidos nas exclusões do Windows Defender",
		}
	}

	if hasFocusGuard && !hasHosts {
		return doctorResult{
			Name:    "Windows Defender",
			Status:  statusWarn,
			Message: "FocusGuard está na lista de exclusões, mas o arquivo hosts não (risco de falso positivo HostsFileHijack)",
			Fix:     "Execute no PowerShell como Administrador: Add-MpPreference -ExclusionPath 'C:\\Windows\\System32\\drivers\\etc\\hosts'",
		}
	}

	return doctorResult{
		Name:    "Windows Defender",
		Status:  statusWarn,
		Message: "FocusGuard e arquivo hosts não estão na lista de exclusões do Windows Defender (risco de falso positivo)",
		Fix:     "Execute no PowerShell como Administrador: Add-MpPreference -ExclusionPath 'C:\\Program Files\\FocusGuard', '$env:ProgramData\\FocusGuard', 'C:\\Windows\\System32\\drivers\\etc\\hosts' -ExclusionProcess 'focusguard-daemon.exe','focusguard.exe'",
	}
}
