package autostart

import (
	"fmt"
	"os"
	"os/exec"
	"runtime"
)

type cmdRunner interface {
	CombinedOutput() ([]byte, error)
}

var goos = runtime.GOOS

var execCommand = func(name string, args ...string) cmdRunner {
	return exec.Command(name, args...)
}

var osMkdirAll = os.MkdirAll
var osStat = os.Stat

func Install(exePath string) error {
	if exePath == "" {
		return fmt.Errorf("autostart: caminho do executável não pode ser vazio")
	}
	if goos != "windows" {
		return fmt.Errorf("autostart: instalação via serviço Windows não é suportada em %s", goos)
	}
	return installWindows(exePath)
}

func Uninstall() error {
	if goos != "windows" {
		return fmt.Errorf("autostart: desinstalação via serviço Windows não é suportada em %s", goos)
	}
	return uninstallWindows()
}

func IsInstalled() (bool, error) {
	if goos != "windows" {
		return false, fmt.Errorf("autostart: plataforma não suportada: %s", goos)
	}
	return isInstalledWindows()
}

func InstallWatchdog(exePath string) error {
	if exePath == "" {
		return fmt.Errorf("autostart: caminho do watchdog não pode ser vazio")
	}
	if goos != "windows" {
		return fmt.Errorf("autostart: watchdog externo é exclusivo do Windows")
	}
	return installWatchdogWindows(exePath)
}

func UninstallWatchdog() error {
	if goos != "windows" {
		return fmt.Errorf("autostart: watchdog externo é exclusivo do Windows")
	}
	return uninstallWatchdogWindows()
}

func InstallTray(exePath string) error {
	if exePath == "" {
		return fmt.Errorf("autostart: caminho do executável não pode ser vazio")
	}
	if goos != "windows" {
		return fmt.Errorf("autostart: autostart do tray é exclusivo do Windows (chave Run)")
	}
	return installTrayWindows(exePath)
}

func UninstallTray() error {
	if goos != "windows" {
		return fmt.Errorf("autostart: autostart do tray é exclusivo do Windows (chave Run)")
	}
	return uninstallTrayWindows()
}

func IsTrayInstalled() (bool, error) {
	if goos != "windows" {
		return false, nil
	}
	return isTrayInstalledWindows()
}
