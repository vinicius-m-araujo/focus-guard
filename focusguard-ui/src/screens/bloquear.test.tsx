import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { act, cleanup, fireEvent, render, screen } from "@testing-library/react";
import type { ApiResponse, Preset } from "@/api/types";
import { Bloquear } from "./Bloquear";

const mockRefresh = vi.fn();
const mockPresetAdd = vi.fn();
const mockBlock = vi.fn();
const mockToast = vi.fn();

vi.mock("@/context", () => ({
  useData: vi.fn(),
}));

vi.mock("@/api/client", () => ({
  api: {
    block: (...args: any[]) => mockBlock(...args),
    presetAdd: (...args: any[]) => mockPresetAdd(...args),
  },
  DaemonError: class DaemonError extends Error {},
}));

vi.mock("@/lib/toast", () => ({
  toast: (...args: any[]) => mockToast(...args),
}));

import { useData } from "@/context";
const useDataMock = vi.mocked(useData);

const samplePresets: Preset[] = [
  {
    name: "social",
    label: "Redes sociais",
    domains: ["twitter.com", "instagram.com"],
  },
  {
    name: "video",
    label: "Vídeos",
    domains: ["youtube.com", "netflix.com"],
  },
];

beforeEach(() => {
  vi.clearAllMocks();
  useDataMock.mockReturnValue({
    daemonUp: true,
    status: { success: true, blocks: [] } as ApiResponse,
    presets: samplePresets,
    stats: null,
    refresh: mockRefresh,
  });
});

afterEach(() => {
  cleanup();
});

describe("Bloquear - Criação de Preset Personalizado", () => {
  it("renderiza lista de presets e botão para criar novo preset", async () => {
    await act(async () => {
      render(<Bloquear />);
    });

    expect(screen.getByText("Redes sociais")).toBeDefined();
    expect(screen.getByText("Vídeos")).toBeDefined();
    expect(screen.getByRole("button", { name: /novo preset/i })).toBeDefined();
  });

  it("abre o diálogo de criação ao clicar em 'Novo preset'", async () => {
    await act(async () => {
      render(<Bloquear />);
    });

    const newPresetBtn = screen.getByRole("button", { name: /novo preset/i });
    await act(async () => {
      fireEvent.click(newPresetBtn);
    });

    expect(screen.getByText("Criar preset personalizado")).toBeDefined();
    expect(screen.getByLabelText(/identificador \/ nome/i)).toBeDefined();
    expect(screen.getByLabelText(/rótulo de exibição/i)).toBeDefined();
    expect(screen.getByLabelText(/domínios a bloquear/i)).toBeDefined();
  });

  it("valida campos obrigatórios ao tentar salvar preset vazio", async () => {
    await act(async () => {
      render(<Bloquear />);
    });

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /novo preset/i }));
    });

    const submitBtn = screen.getByRole("button", { name: /criar e selecionar/i });
    await act(async () => {
      fireEvent.click(submitBtn);
    });

    expect(mockToast).toHaveBeenCalledWith("Informe o nome do preset.", "err");
    expect(mockPresetAdd).not.toHaveBeenCalled();
  });

  it("cria preset personalizado com sucesso, atualiza o contexto e seleciona o preset", async () => {
    mockPresetAdd.mockResolvedValue({
      success: true,
      message: "Preset estudos criado (2 domínios)",
    });

    await act(async () => {
      render(<Bloquear />);
    });

    await act(async () => {
      fireEvent.click(screen.getByRole("button", { name: /novo preset/i }));
    });

    const nameInput = screen.getByLabelText(/identificador \/ nome/i);
    const labelInput = screen.getByLabelText(/rótulo de exibição/i);
    const domainsInput = screen.getByLabelText(/domínios a bloquear/i);

    await act(async () => {
      fireEvent.change(nameInput, { target: { value: "estudos" } });
      fireEvent.change(labelInput, { target: { value: "Foco nos Estudos" } });
      fireEvent.change(domainsInput, {
        target: { value: "https://youtube.com, reddit.com\n twitch.tv " },
      });
    });

    const submitBtn = screen.getByRole("button", { name: /criar e selecionar/i });
    await act(async () => {
      fireEvent.click(submitBtn);
    });

    expect(mockPresetAdd).toHaveBeenCalledWith(
      "estudos",
      "Foco nos Estudos",
      ["youtube.com", "reddit.com", "twitch.tv"]
    );
    expect(mockRefresh).toHaveBeenCalled();
    expect(mockToast).toHaveBeenCalledWith("Preset estudos criado (2 domínios)");
  });

  it("permite abrir o diálogo a partir da aba de domínio específico com domínio preenchido", async () => {
    await act(async () => {
      render(<Bloquear />);
    });

    // Alterna para aba "Domínio específico"
    const domainTab = screen.getByRole("tab", { name: /domínio específico/i });
    await act(async () => {
      fireEvent.pointerDown(domainTab, { button: 0 });
      fireEvent.mouseDown(domainTab, { button: 0 });
      fireEvent.click(domainTab);
    });

    const domainInput = screen.getByLabelText(/^domínio$/i);
    await act(async () => {
      fireEvent.change(domainInput, { target: { value: "discord.com" } });
    });

    // Clica no botão para criar preset a partir do domínio
    const createFromDomainBtn = screen.getByRole("button", { name: /criar preset com este domínio/i });
    await act(async () => {
      fireEvent.click(createFromDomainBtn);
    });

    expect(screen.getByText("Criar preset personalizado")).toBeDefined();
    const domainsInput = screen.getByLabelText(/domínios a bloquear/i) as HTMLTextAreaElement;
    expect(domainsInput.value).toBe("discord.com");
  });

  it("exibe lista de domínios incluídos quando um preset é selecionado", async () => {
    await act(async () => {
      render(<Bloquear />);
    });

    // Clica no preset "Redes sociais"
    const socialBtn = screen.getByRole("button", { name: /redes sociais/i });
    await act(async () => {
      fireEvent.click(socialBtn);
    });

    expect(screen.getByText(/domínios incluídos neste preset/i)).toBeDefined();
    expect(screen.getByText("twitter.com")).toBeDefined();
    expect(screen.getByText("instagram.com")).toBeDefined();
  });
});
