import { useState } from "react";
import { FolderPlus, Lock, ShieldCheck } from "lucide-react";
import { api, DaemonError } from "@/api/client";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { EmptyCard, Screen, ScreenHeader } from "@/components/screen";
import { useData } from "@/context";
import { formatClock } from "@/hooks/useCountdown";
import { toast } from "@/lib/toast";
import { cn } from "@/lib/utils";

const DURATIONS = [
  { label: "30 min", value: "30m" },
  { label: "1 h", value: "1h" },
  { label: "2 h", value: "2h" },
  { label: "4 h", value: "4h" },
  { label: "8 h", value: "8h" },
];

// ConflictState guarda o domínio que o daemon recusou com Conflict:true, para
// o dialog "somar/substituir" poder reenviar com o domínio congelado (mesmo se
// o usuário editar o input enquanto o dialog está aberto).
interface ConflictState {
  domain: string;
  expires?: string;
}

export function Bloquear() {
  const { presets, daemonUp, refresh } = useData();
  const [mode, setMode] = useState<"preset" | "domain">("preset");
  const [preset, setPreset] = useState<string>("");
  const [domain, setDomain] = useState<string>("");
  const [duration, setDuration] = useState<string>("1h");
  const [customMin, setCustomMin] = useState<string>("");
  const [busy, setBusy] = useState(false);
  const [conflict, setConflict] = useState<ConflictState | null>(null);

  // Estados para criação de preset personalizado diretamente da tela de bloqueio
  const [createPresetOpen, setCreatePresetOpen] = useState(false);
  const [newPresetName, setNewPresetName] = useState("");
  const [newPresetLabel, setNewPresetLabel] = useState("");
  const [newPresetDomains, setNewPresetDomains] = useState("");
  const [creatingPreset, setCreatingPreset] = useState(false);

  const effectiveDuration = duration === "custom" ? `${customMin}m` : duration;

  const openCreatePreset = (initialDomain?: string) => {
    setNewPresetName("");
    setNewPresetLabel("");
    setNewPresetDomains(initialDomain ? initialDomain.trim() : "");
    setCreatePresetOpen(true);
  };

  const submitCreatePreset = async () => {
    const cleanName = newPresetName
      .trim()
      .toLowerCase()
      .replace(/\s+/g, "-")
      .replace(/[^a-z0-9_-]/g, "");

    if (!cleanName) {
      toast("Informe o nome do preset.", "err");
      return;
    }

    const doms = newPresetDomains
      .split(/[,\s\n]+/)
      .map((d) =>
        d
          .trim()
          .toLowerCase()
          .replace(/^https?:\/\//, "")
          .replace(/\/.*$/, "")
      )
      .filter(Boolean);

    const uniqueDoms = Array.from(new Set(doms));
    if (uniqueDoms.length === 0) {
      toast("Informe ao menos um domínio para o preset.", "err");
      return;
    }

    setCreatingPreset(true);
    try {
      const resp = await api.presetAdd(
        cleanName,
        newPresetLabel.trim() || cleanName,
        uniqueDoms
      );
      if (!resp.success) {
        toast(resp.message ?? "Falha ao criar preset.", "err");
        return;
      }
      toast(resp.message ?? "Preset criado com sucesso!");
      await refresh();
      setMode("preset");
      setPreset(cleanName);
      setCreatePresetOpen(false);
      setNewPresetName("");
      setNewPresetLabel("");
      setNewPresetDomains("");
    } catch (e) {
      toast(e instanceof DaemonError ? e.message : "Erro ao criar preset.", "err");
    } finally {
      setCreatingPreset(false);
    }
  };

  const submit = async (resolve?: { extend?: boolean; replace?: boolean }) => {
    if (duration === "custom") {
      const n = Number(customMin);
      if (!customMin.trim() || !Number.isFinite(n) || n <= 0) {
        toast("Digite a duração em minutos (maior que zero).", "err");
        return;
      }
    }
    if (!resolve) {
      if (mode === "preset" && !preset) {
        toast("Escolha uma categoria.", "err");
        return;
      }
      if (mode === "domain" && !domain.trim()) {
        toast("Digite o domínio a bloquear.", "err");
        return;
      }
    }
    setBusy(true);
    try {
      const resp = await api.block({
        preset: mode === "preset" ? preset : undefined,
        domain: conflict ? conflict.domain : mode === "domain" ? domain.trim() : undefined,
        duration: effectiveDuration,
        extend: resolve?.extend,
        replace: resolve?.replace,
      });
      if (resp.conflict) {
        setConflict({
          domain: mode === "domain" ? domain.trim() : (resp.conflict_block?.domain || preset),
          expires: resp.conflict_block?.expires_at,
        });
        return;
      }
      setConflict(null);
      if (!resp.success) {
        toast(resp.message ?? "Falha ao bloquear.", "err");
      } else {
        toast(resp.message ?? "Bloqueio aplicado!");
        setDomain("");
        await refresh();
      }
    } catch (e) {
      setConflict(null);
      toast(e instanceof DaemonError ? e.message : "Erro ao bloquear.", "err");
    } finally {
      setBusy(false);
    }
  };

  const selectedPresetObj = presets.find((p) => p.name === preset);

  return (
    <Screen>
      <ScreenHeader
        title="Bloquear"
        subtitle="Escolha uma categoria ou um domínio e a duração do bloqueio."
      />

      {daemonUp === false ? (
        <EmptyCard>
          <p>O daemon está desligado — bloqueio indisponível.</p>
        </EmptyCard>
      ) : (
        <Card className="max-w-2xl">
          <CardContent className="flex flex-col gap-5 px-5 py-5">
            <Tabs value={mode} onValueChange={(v) => setMode(v as "preset" | "domain")}>
              <TabsList className="w-full">
                <TabsTrigger value="preset" className="flex-1">
                  <ShieldCheck /> Categoria (preset)
                </TabsTrigger>
                <TabsTrigger value="domain" className="flex-1">
                  <Lock /> Domínio específico
                </TabsTrigger>
              </TabsList>
            </Tabs>

            {mode === "preset" ? (
              <div className="flex flex-col gap-3">
                <div className="flex flex-wrap items-center gap-2">
                  {presets.map((p) => (
                    <Button
                      key={p.name}
                      type="button"
                      variant={preset === p.name ? "default" : "outline"}
                      title={p.domains.join(", ")}
                      onClick={() => setPreset(p.name)}
                      className="h-7"
                    >
                      {p.label}
                      <span className="rounded-full bg-muted px-1.5 text-xs tabular-nums">
                        {p.domains.length}
                      </span>
                    </Button>
                  ))}
                  <Button
                    type="button"
                    variant="outline"
                    onClick={() => openCreatePreset()}
                    className="h-7 border-dashed gap-1 text-xs text-muted-foreground hover:text-foreground"
                    title="Criar novo preset personalizado"
                  >
                    <FolderPlus className="size-3.5" />
                    Novo preset
                  </Button>
                </div>

                {selectedPresetObj && (
                  <div className="rounded-lg border border-border/60 bg-muted/30 p-3 text-xs flex flex-col gap-1.5">
                    <div className="font-medium text-foreground">
                      Domínios incluídos neste preset ({selectedPresetObj.domains.length}):
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {selectedPresetObj.domains.map((d) => (
                        <span
                          key={d}
                          className="rounded bg-background px-1.5 py-0.5 font-mono text-[11px] border border-border/50 text-muted-foreground"
                        >
                          {d}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            ) : (
              <div className="flex flex-col gap-2">
                <div className="flex items-center justify-between">
                  <Label htmlFor="domain">Domínio</Label>
                  <Button
                    type="button"
                    variant="link"
                    size="sm"
                    onClick={() => openCreatePreset(domain)}
                    className="h-auto p-0 text-xs text-muted-foreground hover:text-foreground"
                  >
                    <FolderPlus className="size-3.5 mr-1" />
                    {domain.trim() ? "Criar preset com este domínio" : "Criar novo preset"}
                  </Button>
                </div>
                <Input
                  id="domain"
                  type="text"
                  placeholder="ex: youtube.com"
                  value={domain}
                  onChange={(e) => setDomain(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && void submit()}
                />
              </div>
            )}

            <div className="flex flex-col gap-2">
              <Label>Duração</Label>
              <div className="flex flex-wrap gap-2">
                {DURATIONS.map((d) => (
                  <Button
                    key={d.value}
                    type="button"
                    variant={duration === d.value ? "default" : "outline"}
                    onClick={() => setDuration(d.value)}
                    className="h-7"
                  >
                    {d.label}
                  </Button>
                ))}
                <Button
                  type="button"
                  variant={duration === "custom" ? "default" : "outline"}
                  onClick={() => setDuration("custom")}
                  className="h-7"
                >
                  personalizado
                </Button>
              </div>
              {duration === "custom" && (
                <div className={cn("flex items-center gap-2")}>
                  <Input
                    type="number"
                    min={1}
                    placeholder="minutos"
                    className="max-w-28"
                    value={customMin}
                    onChange={(e) => setCustomMin(e.target.value)}
                  />
                  <span className="text-sm text-muted-foreground">minutos</span>
                </div>
              )}
            </div>

            <Button onClick={() => void submit()} disabled={busy} className="w-full" size="lg">
              <Lock /> {busy ? "Bloqueando…" : "Bloquear"}
            </Button>
          </CardContent>
        </Card>
      )}

      {/* Diálogo de conflito de bloqueio */}
      <Dialog
        open={conflict !== null}
        onOpenChange={(open) => !open && setConflict(null)}
      >
        <DialogContent showCloseButton={false}>
          <DialogHeader>
            <DialogTitle>Já está bloqueado</DialogTitle>
            <DialogDescription>
              {conflict?.domain} já está bloqueado
              {conflict?.expires ? <> até {formatClock(conflict.expires)}</> : null}. O
              que você quer fazer?
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button
              variant="outline"
              disabled={busy}
              onClick={() => setConflict(null)}
            >
              Cancelar
            </Button>
            <Button variant="secondary" disabled={busy} onClick={() => void submit({ replace: true })}>
              Substituir
            </Button>
            <Button disabled={busy} onClick={() => void submit({ extend: true })}>
              Somar {effectiveDuration}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Diálogo para criação de preset personalizado diretamente do Bloquear */}
      <Dialog open={createPresetOpen} onOpenChange={setCreatePresetOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Criar preset personalizado</DialogTitle>
            <DialogDescription>
              Crie uma categoria com os domínios que você deseja bloquear juntos.
            </DialogDescription>
          </DialogHeader>
          <div className="flex flex-col gap-4 py-2">
            <div className="flex flex-col gap-2">
              <Label htmlFor="new-preset-name">Identificador / Nome</Label>
              <Input
                id="new-preset-name"
                type="text"
                placeholder="ex: foco-estudos"
                value={newPresetName}
                onChange={(e) => setNewPresetName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && void submitCreatePreset()}
              />
              <span className="text-[11px] text-muted-foreground">
                Identificador do preset (letras, números e hifens).
              </span>
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="new-preset-label">Rótulo de exibição (opcional)</Label>
              <Input
                id="new-preset-label"
                type="text"
                placeholder="ex: Foco nos Estudos"
                value={newPresetLabel}
                onChange={(e) => setNewPresetLabel(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && void submitCreatePreset()}
              />
            </div>
            <div className="flex flex-col gap-2">
              <Label htmlFor="new-preset-domains">Domínios a bloquear</Label>
              <Textarea
                id="new-preset-domains"
                placeholder="ex: youtube.com, twitter.com, reddit.com&#10;twitch.tv"
                rows={3}
                value={newPresetDomains}
                onChange={(e) => setNewPresetDomains(e.target.value)}
              />
              <span className="text-[11px] text-muted-foreground">
                Separe os domínios por vírgula, espaço ou quebra de linha.
              </span>
            </div>
          </div>
          <DialogFooter>
            <Button
              variant="outline"
              type="button"
              disabled={creatingPreset}
              onClick={() => setCreatePresetOpen(false)}
            >
              Cancelar
            </Button>
            <Button
              type="button"
              disabled={creatingPreset}
              onClick={() => void submitCreatePreset()}
            >
              <FolderPlus className="size-4" />
              {creatingPreset ? "Criando…" : "Criar e selecionar"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </Screen>
  );
}
