# Plugin `claude-usage` para Noctalia — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portar el plugin `claude-usage` de Caelestia (QML+JS, 85% hecho, bloqueado) a Noctalia 5 (Luau), conservando su lógica probada y su diseño aprobado.

**Architecture:** Un `[[service]]` headless es el único que toca red, ficheros, temporizador y notificaciones; publica un objeto ya calculado en `noctalia.state`, y un `[[widget]]` de barra y un `[[panel]]` lo observan y solo pintan. `logic.luau` concentra toda la lógica pura y no llama a ninguna API host, lo que permite probarlo con el intérprete `luau` sin levantar el shell.

**Tech Stack:** Luau 0.703 (nixpkgs), Noctalia 5.0.0, `plugin_api = 3`, direnv + devshell de `~/nixos-config`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-07-claude-usage-noctalia-design.md`. Es la autoridad. Cualquier desviación se anota en el ledger, no se decide sobre la marcha.
- **Fuente que se traduce:** `~/Projects/caelestia-plugins/.claude/worktrees/claude-usage/claude-usage/logic.js` (rama `feat/claude-usage`, 506 líneas, 69 tests verdes). **Es una transcripción, no un rediseño.** Los nombres públicos se conservan letra por letra salvo donde este plan diga lo contrario.
- **`logic.luau` NO puede llamar a ninguna API host.** Ni `noctalia.*`, ni `ui.*`. Si necesita algo del entorno, se le pasa por parámetro. Esta es la regla que hace la suite ejecutable.
- **Luau no trae JSON ni `Date`.** Consecuencias obligatorias en todo el plan:
  - `parseCredentials` y `extractCache` reciben **tablas ya decodificadas**, no texto. El `noctalia.json.decode` vive en `service.luau`. Desaparece `safeParse`.
  - Las fechas viajan como **epoch en milisegundos (number)**, nunca como objeto. Donde `logic.js` decía `resetsAt: Date`, aquí es `resetsAt: number?`.
  - `validDate(v)` pasa a ser `validMs(v)`: number finito y `> 0`, o `nil`.
- **`parseRetryAfter` NO se porta.** `HttpResponse` de Noctalia no expone cabeceras (spec §8). Se elimina, y el 429 cae al backoff por `failures`.
- **`table.sort` de Luau no es estable.** Todo comparador necesita desempate total y determinista (spec §4.2).
- **Zona horaria de las pruebas:** `TZ=Europe/Madrid`, fijada por el lanzador. Sin ella los formatos de hora no son deterministas.
- **Idioma de las cadenas de usuario:** español, exactamente como en `logic.js` (`"Sesión 5 h"`, `"Semana"`, `"reiniciando…"`, `"en 34 min"`, `"mañana a las 07:00"`). Los textos de UI van por `noctalia.tr` con `translations/es.json` y `en.json`.
- **Seguridad:** el token nunca a `noctalia.log`, ni a la UI, ni a mensajes de error, ni a argv. Los fixtures ya están anonimizados; se copian tal cual.
- **Commits:** frecuentes, uno por tarea como mínimo. Autoría de daf3r, **sin `Co-Authored-By: Claude`**, email `isaacdavid959@users.noreply.github.com`.

## Estructura de ficheros

| Fichero | Responsabilidad |
| --- | --- |
| `claude-usage/plugin.toml` | Manifiesto: metadatos, 3 entradas, 6 ajustes |
| `claude-usage/logic.luau` | Lógica pura. Cero API host. El grueso de las pruebas |
| `claude-usage/service.luau` | `[[service]]`: http, ficheros, temporizador, notify, estado |
| `claude-usage/widget.luau` | `[[widget]]`: píldora de barra |
| `claude-usage/panel.luau` | `[[panel]]`: desglose |
| `claude-usage/translations/{en,es}.json` | Textos |
| `claude-usage/tests/run.fish` | Lanzador con `TZ` fija |
| `claude-usage/tests/*.test.luau` | Suite portada, un fichero por área |
| `claude-usage/tests/fixtures/*.json` | Copiados de Caelestia sin tocar |
| `~/nixos-config/devshells/default.nix` | Añade el devshell `noctalia-plugins` |

---

### Task 1: Devshell, andamiaje y arnés de pruebas

Sin un `luau` en el PATH y un lanzador que sepa fallar, ninguna tarea siguiente es verificable. Esta tarea no entrega producto: entrega la capacidad de probar.

**Files:**
- Modify: `~/nixos-config/devshells/default.nix`
- Create: `~/Projects/noctalia-plugins/.envrc`
- Create: `~/Projects/noctalia-plugins/claude-usage/tests/run.fish`
- Create: `~/Projects/noctalia-plugins/claude-usage/tests/harness.luau`
- Create: `~/Projects/noctalia-plugins/claude-usage/tests/smoke.test.luau`
- Create: `~/Projects/noctalia-plugins/claude-usage/logic.luau`

**Interfaces:**
- Consumes: nada.
- Produces: `harness.luau` expone `describe(name, fn)`, `test(name, fn)`, `eq(actual, expected, msg)`, `truthy(v, msg)`, `nilish(v, msg)` y `report() -> boolean`. Todas las tareas siguientes escriben tests con esa API.

- [ ] **Step 1: Añadir el devshell a la config de Nix**

En `~/nixos-config/devshells/default.nix`, dentro del atributo que devuelve el conjunto de shells, añadir junto a los existentes:

```nix
  # Plugins propios de Noctalia. Se escriben en Luau, que no es un lenguaje
  # con toolchain que merezca estar en el sistema: solo hace falta aquí, para
  # correr la suite de logic.luau sin levantar el shell gráfico.
  noctalia-plugins = pkgs.mkShell {
    packages = with pkgs; [
      luau # 0.703 — intérprete y `luau-analyze`
      fish # el lanzador de tests es fish, como el resto del proyecto
    ];
  };
```

- [ ] **Step 2: Aplicar la config y comprobar que `luau` existe**

```bash
sudo nixos-rebuild switch --flake ~/nixos-config
```

Después, en `~/Projects/noctalia-plugins`:

```bash
echo 'use flake ~/nixos-config#noctalia-plugins' > .envrc
direnv allow
luau --version
```

Esperado: imprime `0.703` (o superior). Si `direnv` no está activo en el directorio, `nix develop ~/nixos-config#noctalia-plugins -c luau --version` sirve igual.

- [ ] **Step 3: Escribir el arnés de pruebas**

Luau no trae framework de test. `harness.luau`:

```lua
--!strict
-- Arnés mínimo. No hay framework de test en Luau; esto es lo justo para
-- que la suite portada de Caelestia se lea igual que la original.

local M = {}

local passed = 0
local failed = 0
local currentSuite = ""

function M.describe(name: string, fn: () -> ())
  currentSuite = name
  fn()
  currentSuite = ""
end

function M.test(name: string, fn: () -> ())
  local label = if currentSuite ~= "" then `{currentSuite} > {name}` else name
  local ok, err = pcall(fn)
  if ok then
    passed += 1
  else
    failed += 1
    print(`not ok - {label}`)
    print(`  {err}`)
  end
end

-- Comparación profunda: las tablas normalizadas se comparan enteras.
local function deepEq(a: any, b: any): boolean
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in a do
    if not deepEq(v, b[k]) then return false end
  end
  for k in b do
    if a[k] == nil then return false end
  end
  return true
end

function M.eq(actual: any, expected: any, msg: string?)
  if not deepEq(actual, expected) then
    error(`{msg or "eq"}: esperado {tostring(expected)}, recibido {tostring(actual)}`, 2)
  end
end

function M.truthy(v: any, msg: string?)
  if not v then error(`{msg or "truthy"}: valor falsy`, 2) end
end

function M.nilish(v: any, msg: string?)
  if v ~= nil then error(`{msg or "nilish"}: esperado nil, recibido {tostring(v)}`, 2) end
end

function M.report(): boolean
  print(`# pass {passed}`)
  print(`# fail {failed}`)
  return failed == 0
end

return M
```

- [ ] **Step 4: Escribir el lanzador**

`tests/run.fish`:

```fish
#!/usr/bin/env fish
# Lanzador de las pruebas de logic.luau.
# TZ fija: sin ella los formatos de hora no son deterministas (igual que en
# el run.fish original de Caelestia).

set -l here (dirname (status --current-filename))
set -lx TZ Europe/Madrid

set -l status_total 0
for f in $here/*.test.luau
  luau $f; or set status_total 1
end
exit $status_total
```

- [ ] **Step 5: Escribir el test de humo, que debe fallar**

`logic.luau` arranca prácticamente vacío:

```lua
--!strict
-- Lógica pura del plugin claude-usage. Traducción de logic.js (Caelestia).
--
-- REGLA: este fichero no llama a NINGUNA API host. Ni noctalia.*, ni ui.*.
-- Lo que necesite del entorno se le pasa por parámetro. Es lo que permite
-- correr la suite con `luau` sin levantar el shell.
--
-- Luau no trae JSON ni Date: las fechas viajan como epoch en milisegundos.

local M = {}

return M
```

`tests/smoke.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

h.describe("arnés", function()
  h.test("logic.luau se puede importar y expone SEVERITY_RANK", function()
    h.eq(Logic.SEVERITY_RANK.critical, 2)
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 6: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL — `# fail 1`, con el error de indexar `SEVERITY_RANK` que es `nil`.

- [ ] **Step 7: Implementar lo mínimo**

En `logic.luau`, antes del `return M`:

```lua
-- Una severidad que no conocemos se trata como la más grave: si Anthropic
-- añade un estado nuevo, preferimos un falso rojo a un silencio.
M.SEVERITY_RANK = { normal = 0, warning = 1, critical = 2 }
```

- [ ] **Step 8: Ejecutar y confirmar que pasa**

Run: `fish claude-usage/tests/run.fish`
Expected: `# pass 1`, `# fail 0`, exit 0.

- [ ] **Step 9: Copiar los fixtures heredados**

```bash
cp ~/Projects/caelestia-plugins/.claude/worktrees/claude-usage/claude-usage/tests/fixtures/*.json \
   ~/Projects/noctalia-plugins/claude-usage/tests/fixtures/
ls ~/Projects/noctalia-plugins/claude-usage/tests/fixtures/
```

Esperado: `usage-credits-on.json`, `usage-no-limits.json`, `usage-normal.json`, `usage-warning.json`.

Verificar que no llevan datos de cuenta:

```bash
grep -riE 'accountUuid|@|organization' ~/Projects/noctalia-plugins/claude-usage/tests/fixtures/ || echo "limpios"
```

Esperado: `limpios`.

- [ ] **Step 10: Commit**

```bash
cd ~/Projects/noctalia-plugins
git add claude-usage .envrc
git commit -m "test: add the luau harness, runner and inherited fixtures"
cd ~/nixos-config && git add devshells/default.nix
git commit -m "feat: add a noctalia-plugins devshell with luau"
```

---

### Task 2: Normalización del payload

**Files:**
- Modify: `claude-usage/logic.luau`
- Create: `claude-usage/tests/normalize.test.luau`

**Interfaces:**
- Consumes: `M.SEVERITY_RANK` de Task 1.
- Produces:
  - `M.severityRank(severity: string?) -> number`
  - `M.limitLabel(kind: string, scopeName: string?) -> string`
  - `M.PRIMARY_KINDS: {string}` — `{"session", "weekly_all"}`
  - `M.normalizeUsage(payload: {[string]: any}?, source: string, fetchedAtMs: number?) -> Normalized`

  donde `Normalized = { limits: {Limit}, extraUsage: Extra?, source: string, fetchedAt: number? }`,
  `Limit = { key: string, label: string, percent: number, severity: string, resetsAt: number?, scope: string?, primary: boolean }`,
  `Extra = { enabled: boolean, everEnabled: boolean, usedMinor: number, limitMinor: number, currency: string, exponent: number, percent: number, disabledReason: string? }`.

**Nota de traducción:** `parseDate(value)` de `logic.js` devolvía un `Date` a partir de una cadena ISO. Aquí se llama `M.parseIsoMs(value: string?) -> number?` y devuelve epoch en ms. Luau no parsea ISO 8601: hay que hacerlo con captura de patrón y `os.time`, y **restar el offset porque `os.time` interpreta en hora local mientras la API da UTC con offset explícito**.

- [ ] **Step 1: Escribir los tests que fallan**

`tests/normalize.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

h.describe("severityRank", function()
  h.test("conoce los tres estados", function()
    h.eq(Logic.severityRank("normal"), 0)
    h.eq(Logic.severityRank("warning"), 1)
    h.eq(Logic.severityRank("critical"), 2)
  end)
  h.test("una severidad desconocida se rankea como crítica", function()
    h.eq(Logic.severityRank("meltdown"), 2)
    h.eq(Logic.severityRank(nil), 2)
  end)
end)

h.describe("limitLabel", function()
  h.test("etiqueta las tres clases", function()
    h.eq(Logic.limitLabel("session", nil), "Sesión 5 h")
    h.eq(Logic.limitLabel("weekly_all", nil), "Semana")
    h.eq(Logic.limitLabel("weekly_scoped", "Opus"), "Opus · semanal")
  end)
  h.test("weekly_scoped sin nombre de modelo", function()
    h.eq(Logic.limitLabel("weekly_scoped", nil), "Sublímite semanal")
  end)
  h.test("un kind desconocido se devuelve tal cual", function()
    h.eq(Logic.limitLabel("monthly_xyz", nil), "monthly_xyz")
  end)
end)

h.describe("parseIsoMs", function()
  h.test("parsea una fecha UTC con offset Z", function()
    h.eq(Logic.parseIsoMs("2026-08-07T05:00:00Z"), 1786251600000)
  end)
  h.test("devuelve nil ante basura o ausencia", function()
    h.nilish(Logic.parseIsoMs("no soy una fecha"))
    h.nilish(Logic.parseIsoMs(nil))
    h.nilish(Logic.parseIsoMs(""))
  end)
end)

h.describe("normalizeUsage", function()
  h.test("payload nil devuelve la forma vacía sin lanzar", function()
    local r = Logic.normalizeUsage(nil, "api", 1000)
    h.eq(#r.limits, 0)
    h.nilish(r.extraUsage)
    h.eq(r.source, "api")
  end)

  h.test("limits[] es la fuente canónica", function()
    local payload = {
      limits = {
        { kind = "session", percent = 42.4, severity = "normal",
          resets_at = "2026-08-07T05:00:00Z" },
        { kind = "weekly_all", percent = 88, severity = "warning",
          resets_at = "2026-08-08T05:00:00Z" },
        { kind = "weekly_scoped", percent = 3, severity = "normal",
          resets_at = "2026-08-08T05:00:00Z",
          scope = { model = { display_name = "Opus" } } },
      },
    }
    local r = Logic.normalizeUsage(payload, "api", 1000)
    h.eq(#r.limits, 3)
    h.eq(r.limits[1].key, "session")
    h.eq(r.limits[1].percent, 42) -- redondeado
    h.eq(r.limits[1].primary, true)
    h.eq(r.limits[3].key, "weekly_scoped:Opus")
    h.eq(r.limits[3].label, "Opus · semanal")
    h.eq(r.limits[3].scope, "Opus")
    h.eq(r.limits[3].primary, false)
  end)

  h.test("sin limits[] cae a five_hour / seven_day", function()
    local payload = {
      limits = {},
      five_hour = { utilization = 42, resets_at = "2026-08-07T05:00:00Z" },
      seven_day = { utilization = 88, resets_at = "2026-08-08T05:00:00Z" },
    }
    local r = Logic.normalizeUsage(payload, "cache", 1000)
    h.eq(#r.limits, 2)
    h.eq(r.limits[1].key, "session")
    h.eq(r.limits[2].key, "weekly_all")
    -- los objetos sueltos no traen severidad
    h.eq(r.limits[1].severity, "normal")
    h.eq(r.limits[1].primary, true)
  end)

  h.test("campos ausentes degradan a cero sin lanzar", function()
    local r = Logic.normalizeUsage({ limits = { { kind = "session" } } }, "api", nil)
    h.eq(r.limits[1].percent, 0)
    h.eq(r.limits[1].severity, "normal")
    h.nilish(r.limits[1].resetsAt)
  end)
end)

h.describe("normalizeUsage / extraUsage", function()
  h.test("spend tiene preferencia sobre extra_usage", function()
    local payload = {
      limits = {},
      spend = {
        enabled = true, percent = 8,
        used = { amount_minor = 240, currency = "USD", exponent = 2 },
        limit = { amount_minor = 3000, currency = "USD", exponent = 2 },
      },
      extra_usage = {
        is_enabled = false, credits_ever_enabled = true,
        used_credits = 99, monthly_limit = 99, currency = "EUR",
      },
    }
    local r = Logic.normalizeUsage(payload, "api", 1000)
    h.eq(r.extraUsage.usedMinor, 240)
    h.eq(r.extraUsage.limitMinor, 3000)
    h.eq(r.extraUsage.currency, "USD")
    h.eq(r.extraUsage.enabled, true)
    h.eq(r.extraUsage.everEnabled, true)
  end)

  h.test("sin spend, extra_usage convierte créditos decimales a menores", function()
    local payload = {
      limits = {},
      extra_usage = {
        is_enabled = true, credits_ever_enabled = true,
        used_credits = 2.4, monthly_limit = 3000,
        currency = "USD", decimal_places = 2, utilization = 8,
        disabled_reason = nil,
      },
    }
    local r = Logic.normalizeUsage(payload, "api", 1000)
    h.eq(r.extraUsage.usedMinor, 240)
    h.eq(r.extraUsage.exponent, 2)
    h.eq(r.extraUsage.percent, 8)
  end)

  h.test("sin spend ni extra_usage devuelve nil", function()
    local r = Logic.normalizeUsage({ limits = {} }, "api", 1000)
    h.nilish(r.extraUsage)
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL, con errores de "attempt to call a nil value" en `severityRank`.

- [ ] **Step 3: Implementar**

Añadir a `logic.luau`, antes del `return M`:

```lua
function M.severityRank(severity: string?): number
  local rank = if severity ~= nil then M.SEVERITY_RANK[severity] else nil
  return if rank == nil then 2 else rank
end

function M.limitLabel(kind: string, scopeName: string?): string
  if kind == "session" then return "Sesión 5 h" end
  if kind == "weekly_all" then return "Semana" end
  if kind == "weekly_scoped" then
    return if scopeName then `{scopeName} · semanal` else "Sublímite semanal"
  end
  return kind
end

M.PRIMARY_KINDS = { "session", "weekly_all" }

local function isPrimaryKind(kind: string): boolean
  for _, k in M.PRIMARY_KINDS do
    if k == kind then return true end
  end
  return false
end

-- Luau no parsea ISO 8601. La API entrega "2026-08-07T05:00:00+00:00" o
-- "...Z". os.time interpreta su tabla en hora LOCAL, así que se calcula el
-- desfase local↔UTC una vez y se corrige, y después se aplica el offset que
-- venga en la propia cadena.
local function localUtcOffsetSeconds(): number
  local t = os.time({ year = 2000, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
  local utc = os.time(os.date("!*t", t) :: any)
  return t - utc
end

function M.parseIsoMs(value: string?): number?
  if type(value) ~= "string" or value == "" then return nil end
  local y, mo, d, hh, mm, ss = string.match(
    value, "^(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
  if not y then return nil end

  local base = os.time({
    year = tonumber(y) :: number, month = tonumber(mo) :: number,
    day = tonumber(d) :: number, hour = tonumber(hh) :: number,
    min = tonumber(mm) :: number, sec = tonumber(ss) :: number,
  })
  if not base then return nil end
  base += localUtcOffsetSeconds()

  -- Offset explícito de la cadena: Z (0) o ±HH:MM
  local sign, oh, om = string.match(value, "([%+%-])(%d%d):?(%d%d)$")
  if sign then
    local delta = (tonumber(oh) :: number) * 3600 + (tonumber(om) :: number) * 60
    base += if sign == "+" then -delta else delta
  end

  return base * 1000
end

local function scopeNameOf(limit: {[string]: any}): string?
  local scope = limit.scope
  if type(scope) ~= "table" then return nil end
  local model = scope.model
  if type(model) ~= "table" then return nil end
  local name = model.display_name
  return if type(name) == "string" and name ~= "" then name else nil
end

local function limitKey(kind: string, scopeName: string?): string
  return if scopeName then `{kind}:{scopeName}` else kind
end

local function num(v: any, fallback: number): number
  return if type(v) == "number" and v == v then v else fallback
end

-- `spend` es la fuente preferida: trae importes en unidades menores y
-- exponente explícito. `extra_usage` da los créditos en decimal y hay que
-- convertirlos.
local function normalizeExtraUsage(payload: {[string]: any}): {[string]: any}?
  local extra = payload.extra_usage
  local spend = payload.spend
  if type(extra) ~= "table" and type(spend) ~= "table" then return nil end

  if type(spend) == "table" and type(spend.used) == "table"
     and type(spend.limit) == "table" then
    return {
      enabled = not not spend.enabled,
      everEnabled = if type(extra) == "table"
        then not not extra.credits_ever_enabled else true,
      usedMinor = num(spend.used.amount_minor, 0),
      limitMinor = num(spend.limit.amount_minor, 0),
      currency = if type(spend.used.currency) == "string"
        then spend.used.currency else "USD",
      exponent = num(spend.used.exponent, 2),
      percent = math.round(num(spend.percent, 0)),
      disabledReason = spend.disabled_reason,
    }
  end

  if type(extra) ~= "table" then return nil end

  local exponent = num(extra.decimal_places, 2)
  local factor = 10 ^ exponent
  return {
    enabled = not not extra.is_enabled,
    everEnabled = not not extra.credits_ever_enabled,
    usedMinor = math.round(num(extra.used_credits, 0) * factor),
    limitMinor = math.round(num(extra.monthly_limit, 0)),
    currency = if type(extra.currency) == "string" then extra.currency else "USD",
    exponent = exponent,
    percent = math.round(num(extra.utilization, 0)),
    disabledReason = extra.disabled_reason,
  }
end

function M.normalizeUsage(payload: {[string]: any}?, source: string,
                          fetchedAtMs: number?): {[string]: any}
  local result = { limits = {}, extraUsage = nil, source = source,
                   fetchedAt = fetchedAtMs }
  if type(payload) ~= "table" then return result end

  local raw = payload.limits
  if type(raw) == "table" and #raw > 0 then
    for _, item in raw do
      local scopeName = scopeNameOf(item)
      table.insert(result.limits, {
        key = limitKey(item.kind, scopeName),
        label = M.limitLabel(item.kind, scopeName),
        percent = math.round(num(item.percent, 0)),
        severity = if type(item.severity) == "string" then item.severity else "normal",
        resetsAt = M.parseIsoMs(item.resets_at),
        scope = scopeName,
        primary = isPrimaryKind(item.kind),
      })
    end
  else
    -- Sin limits[], los objetos sueltos son la única fuente. No traen
    -- severidad, así que el estado de aviso lo decide el umbral local.
    local legacy = {
      { kind = "session", data = payload.five_hour },
      { kind = "weekly_all", data = payload.seven_day },
    }
    for _, entry in legacy do
      if type(entry.data) ~= "table" then continue end
      table.insert(result.limits, {
        key = entry.kind,
        label = M.limitLabel(entry.kind, nil),
        percent = math.round(num(entry.data.utilization, 0)),
        severity = "normal",
        resetsAt = M.parseIsoMs(entry.data.resets_at),
        scope = nil,
        primary = true,
      })
    end
  end

  result.extraUsage = normalizeExtraUsage(payload)
  return result
end
```

- [ ] **Step 4: Ejecutar y confirmar que pasan**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add claude-usage/logic.luau claude-usage/tests/normalize.test.luau
git commit -m "feat: port payload normalisation to luau"
```

---

### Task 3: Orden de criticidad, con el desempate que Luau exige

Aquí está el defecto latente del original: `byCriticality` devuelve 0 en empate total y dependía de que el `sort` fuese estable. **`table.sort` de Luau no lo es**, y además *lanza* `invalid order function for sorting` si el comparador es inconsistente. Sin desempate total, esto no es un parpadeo cosmético: puede reventar.

**Files:**
- Modify: `claude-usage/logic.luau`
- Create: `claude-usage/tests/ordering.test.luau`

**Interfaces:**
- Consumes: `M.severityRank`, `M.PRIMARY_KINDS`, y el tipo `Limit` de Task 2.
- Produces:
  - `M.isWarning(limit: {[string]: any}?, threshold: number) -> boolean`
  - `M.byCriticality(a, b) -> boolean` — **comparador de `table.sort`, devuelve boolean**, no el number de JS
  - `M.pickPrimary(limits: {any}) -> any?`
  - `M.sortForPanel(limits: {any}, primaryKey: string?) -> {any}` — renombrado desde `sortForPopout`, porque en Noctalia es un panel
  - `M.hasHiddenWarning(limits: {any}, primaryKey: string?, threshold: number) -> boolean`

- [ ] **Step 1: Escribir los tests que fallan**

`tests/ordering.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

local function limit(key, percent, severity, primary)
  return { key = key, label = key, percent = percent, severity = severity,
           resetsAt = nil, scope = nil, primary = primary }
end

h.describe("isWarning", function()
  h.test("por severidad, aunque el porcentaje sea bajo", function()
    h.eq(Logic.isWarning(limit("a", 3, "warning", true), 90), true)
  end)
  h.test("por umbral, aunque la severidad sea normal", function()
    h.eq(Logic.isWarning(limit("a", 90, "normal", true), 90), true)
    h.eq(Logic.isWarning(limit("a", 89, "normal", true), 90), false)
  end)
  h.test("nil no es aviso y no lanza", function()
    h.eq(Logic.isWarning(nil, 90), false)
  end)
end)

h.describe("byCriticality", function()
  h.test("la severidad manda sobre el porcentaje", function()
    local a = limit("a", 10, "critical", true)
    local b = limit("b", 99, "normal", true)
    h.eq(Logic.byCriticality(a, b), true)
    h.eq(Logic.byCriticality(b, a), false)
  end)
  h.test("a igual severidad, mayor porcentaje primero", function()
    local a = limit("a", 80, "normal", true)
    local b = limit("b", 20, "normal", true)
    h.eq(Logic.byCriticality(a, b), true)
  end)
  -- EL CASO QUE EL ORIGINAL NO TENÍA
  h.test("empate total desempata por key, de forma determinista", function()
    local a = limit("aaa", 50, "normal", true)
    local b = limit("bbb", 50, "normal", true)
    h.eq(Logic.byCriticality(a, b), true)
    h.eq(Logic.byCriticality(b, a), false)
    -- irreflexivo: table.sort lanza si comp(x, x) es true
    h.eq(Logic.byCriticality(a, a), false)
  end)
  h.test("ordenar una lista con empates totales no lanza y es estable", function()
    local list = {
      limit("ccc", 50, "normal", true), limit("aaa", 50, "normal", true),
      limit("bbb", 50, "normal", true), limit("ddd", 50, "normal", true),
    }
    table.sort(list, Logic.byCriticality)
    h.eq(list[1].key, "aaa")
    h.eq(list[4].key, "ddd")
  end)
end)

h.describe("pickPrimary", function()
  h.test("solo compite entre primarios", function()
    local limits = {
      limit("weekly_scoped:Opus", 99, "critical", false),
      limit("session", 42, "normal", true),
      limit("weekly_all", 88, "warning", true),
    }
    h.eq(Logic.pickPrimary(limits).key, "weekly_all")
  end)
  h.test("sin primarios devuelve nil", function()
    h.nilish(Logic.pickPrimary({ limit("x", 99, "critical", false) }))
  end)
  h.test("lista vacía devuelve nil", function()
    h.nilish(Logic.pickPrimary({}))
  end)
  h.test("no muta el array de entrada", function()
    local limits = { limit("session", 10, "normal", true),
                     limit("weekly_all", 90, "normal", true) }
    Logic.pickPrimary(limits)
    h.eq(limits[1].key, "session")
  end)
end)

h.describe("sortForPanel", function()
  h.test("excluye el primario y ordena el resto", function()
    local limits = {
      limit("session", 42, "normal", true),
      limit("weekly_all", 88, "warning", true),
      limit("weekly_scoped:Opus", 60, "normal", false),
    }
    local rest = Logic.sortForPanel(limits, "weekly_all")
    h.eq(#rest, 2)
    h.eq(rest[1].key, "weekly_scoped:Opus")
    h.eq(rest[2].key, "session")
  end)
  h.test("primaryKey nil devuelve todos", function()
    h.eq(#Logic.sortForPanel({ limit("a", 1, "normal", true) }, nil), 1)
  end)
end)

h.describe("hasHiddenWarning", function()
  h.test("detecta un sublímite en aviso fuera del primario", function()
    local limits = {
      limit("weekly_all", 10, "normal", true),
      limit("weekly_scoped:Opus", 95, "normal", false),
    }
    h.eq(Logic.hasHiddenWarning(limits, "weekly_all", 90), true)
  end)
  h.test("ignora el propio primario", function()
    local limits = { limit("weekly_all", 95, "normal", true) }
    h.eq(Logic.hasHiddenWarning(limits, "weekly_all", 90), false)
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL en todo el bloque nuevo.

- [ ] **Step 3: Implementar**

```lua
-- Definición única de "estar cerca del límite". La usan el color del widget,
-- el glifo indicador, la cadencia de alerta y la notificación.
function M.isWarning(limit: {[string]: any}?, threshold: number): boolean
  if type(limit) ~= "table" then return false end
  return limit.severity ~= "normal" or limit.percent >= threshold
end

-- Comparador de table.sort: devuelve `true` si `a` va ANTES que `b`.
--
-- El tercer criterio (key) no está en el original y es OBLIGATORIO aquí. En
-- JS, dos elementos con la misma severidad y el mismo porcentaje devolvían 0
-- y Array.sort, siendo estable, conservaba su orden. table.sort de Luau NO es
-- estable, y además valida el comparador: uno que diga `true` en ambos
-- sentidos para el mismo par lanza "invalid order function for sorting". Con
-- el desempate por key el orden es total, determinista e irreflexivo.
function M.byCriticality(a: {[string]: any}, b: {[string]: any}): boolean
  local ra, rb = M.severityRank(a.severity), M.severityRank(b.severity)
  if ra ~= rb then return ra > rb end
  if a.percent ~= b.percent then return a.percent > b.percent end
  return a.key < b.key
end

-- El widget solo puede codificar dos glifos, así que solo compite entre los
-- límites primarios. Los sublímites por modelo se señalan con el glifo
-- indicador (ver hasHiddenWarning).
function M.pickPrimary(limits: {any}): any?
  if type(limits) ~= "table" then return nil end
  local primaries = {}
  for _, l in limits do
    if type(l) == "table" and l.primary then table.insert(primaries, l) end
  end
  if #primaries == 0 then return nil end
  table.sort(primaries, M.byCriticality) -- copia local: no muta la entrada
  return primaries[1]
end

function M.sortForPanel(limits: {any}, primaryKey: string?): {any}
  if type(limits) ~= "table" then return {} end
  local rest = {}
  for _, l in limits do
    if type(l) == "table" and l.key ~= primaryKey then table.insert(rest, l) end
  end
  table.sort(rest, M.byCriticality)
  return rest
end

function M.hasHiddenWarning(limits: {any}, primaryKey: string?,
                            threshold: number): boolean
  if type(limits) ~= "table" then return false end
  for _, l in limits do
    if type(l) == "table" and l.key ~= primaryKey and M.isWarning(l, threshold) then
      return true
    end
  end
  return false
end
```

- [ ] **Step 4: Ejecutar y confirmar que pasan**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add claude-usage/logic.luau claude-usage/tests/ordering.test.luau
git commit -m "feat: port criticality ordering with a total tiebreak

table.sort in Luau is neither stable nor tolerant of an inconsistent
comparator, so the deferred Caelestia finding about ties becomes a real
defect here. Adds key as an explicit third criterion."
```

---

### Task 4: Formateadores

**Files:**
- Modify: `claude-usage/logic.luau`
- Create: `claude-usage/tests/format.test.luau`

**Interfaces:**
- Consumes: nada de tareas previas.
- Produces:
  - `M.WEEKDAYS: {string}` — índice 1 = domingo, para casar con `os.date("*t").wday`
  - `M.CURRENCY_SYMBOLS: {[string]: string}`
  - `M.formatRelative(resetsAtMs: number?, nowMs: number) -> string`
  - `M.formatAbsolute(resetsAtMs: number?, nowMs: number) -> string`
  - `M.formatMoney(amountMinor: number?, exponent: number?, currency: string?) -> string`

**Nota de traducción:** `WEEKDAYS` en JS se indexaba con `getDay()` (0 = domingo). En Luau, `os.date("*t").wday` es **1 = domingo**, así que la tabla es 1-based y el acceso es directo, sin `+1`.

- [ ] **Step 1: Escribir los tests que fallan**

`tests/format.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

-- Ancla fija en Europe/Madrid (TZ la pone run.fish): 2026-08-07 09:00 local.
local function ms(y, mo, d, hh, mm)
  return os.time({ year = y, month = mo, day = d, hour = hh, min = mm, sec = 0 }) * 1000
end
local NOW = ms(2026, 8, 7, 9, 0)

h.describe("formatRelative", function()
  h.test("menos de una hora", function()
    h.eq(Logic.formatRelative(NOW + 34 * 60000, NOW), "en 34 min")
  end)
  h.test("menos de un día, con y sin minutos sueltos", function()
    h.eq(Logic.formatRelative(NOW + (10 * 60 + 34) * 60000, NOW), "en 10 h 34 min")
    h.eq(Logic.formatRelative(NOW + 10 * 3600000, NOW), "en 10 h")
  end)
  h.test("más de un día, con y sin horas sueltas", function()
    h.eq(Logic.formatRelative(NOW + (2 * 24 + 4) * 3600000, NOW), "en 2 d 4 h")
    h.eq(Logic.formatRelative(NOW + 2 * 24 * 3600000, NOW), "en 2 d")
  end)
  h.test("ya vencido", function()
    h.eq(Logic.formatRelative(NOW - 1000, NOW), "reiniciando…")
    h.eq(Logic.formatRelative(NOW, NOW), "reiniciando…")
  end)
  h.test("sin fecha devuelve cadena vacía", function()
    h.eq(Logic.formatRelative(nil, NOW), "")
  end)
end)

h.describe("formatAbsolute", function()
  h.test("hoy es solo la hora", function()
    h.eq(Logic.formatAbsolute(ms(2026, 8, 7, 19, 30), NOW), "a las 19:30")
  end)
  h.test("mañana lleva prefijo", function()
    h.eq(Logic.formatAbsolute(ms(2026, 8, 8, 7, 0), NOW), "mañana a las 07:00")
  end)
  h.test("dentro de la semana usa el día", function()
    -- 2026-08-10 es lunes
    h.eq(Logic.formatAbsolute(ms(2026, 8, 10, 7, 0), NOW), "el lunes a las 07:00")
  end)
  h.test("más allá de una semana usa la fecha", function()
    h.eq(Logic.formatAbsolute(ms(2026, 8, 20, 7, 0), NOW), "el 20/8 a las 07:00")
  end)
  h.test("una fecha pasada devuelve cadena vacía", function()
    h.eq(Logic.formatAbsolute(ms(2026, 8, 6, 7, 0), NOW), "")
  end)
  h.test("sin fecha devuelve cadena vacía", function()
    h.eq(Logic.formatAbsolute(nil, NOW), "")
  end)
end)

h.describe("formatMoney", function()
  h.test("formatea con coma decimal y símbolo", function()
    h.eq(Logic.formatMoney(240, 2, "USD"), "2,40 $")
    h.eq(Logic.formatMoney(3000, 2, "EUR"), "30,00 €")
  end)
  h.test("una divisa desconocida usa su propio código", function()
    h.eq(Logic.formatMoney(100, 2, "GBP"), "1,00 GBP")
  end)
  h.test("un exponente inválido cae a 2", function()
    h.eq(Logic.formatMoney(240, nil, "USD"), "2,40 $")
    h.eq(Logic.formatMoney(240, -1, "USD"), "2,40 $")
    h.eq(Logic.formatMoney(240, 2.5, "USD"), "2,40 $") -- blindaje del ledger
  end)
  h.test("importe ausente es cero", function()
    h.eq(Logic.formatMoney(nil, 2, "USD"), "0,00 $")
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL en el bloque nuevo.

- [ ] **Step 3: Implementar**

```lua
-- 1-based para casar con os.date("*t").wday, donde 1 = domingo.
M.WEEKDAYS = { "domingo", "lunes", "martes", "miércoles", "jueves",
               "viernes", "sábado" }
M.CURRENCY_SYMBOLS = { USD = "$", EUR = "€" }

local function pad2(n: number): string
  return if n < 10 then `0{n}` else tostring(n)
end

local function startOfDaySec(sec: number): number
  local t = os.date("*t", sec) :: any
  return os.time({ year = t.year, month = t.month, day = t.day,
                   hour = 0, min = 0, sec = 0 })
end

function M.formatRelative(resetsAtMs: number?, nowMs: number): string
  if type(resetsAtMs) ~= "number" then return "" end

  local delta = resetsAtMs - nowMs
  if delta <= 0 then return "reiniciando…" end

  local minutes = math.floor(delta / 60000)
  if minutes < 60 then return `en {minutes} min` end

  local hours = math.floor(minutes / 60)
  local restMinutes = minutes % 60
  if hours < 24 then
    return if restMinutes > 0 then `en {hours} h {restMinutes} min`
           else `en {hours} h`
  end

  local days = math.floor(hours / 24)
  local restHours = hours % 24
  return if restHours > 0 then `en {days} d {restHours} h` else `en {days} d`
end

function M.formatAbsolute(resetsAtMs: number?, nowMs: number): string
  if type(resetsAtMs) ~= "number" then return "" end

  local sec = math.floor(resetsAtMs / 1000)
  local t = os.date("*t", sec) :: any
  local clock = `a las {pad2(t.hour)}:{pad2(t.min)}`

  local dayDiff = math.round(
    (startOfDaySec(sec) - startOfDaySec(math.floor(nowMs / 1000))) / 86400)

  if dayDiff < 0 then return "" end
  if dayDiff == 0 then return clock end
  if dayDiff == 1 then return `mañana {clock}` end
  if dayDiff < 7 then return `el {M.WEEKDAYS[t.wday]} {clock}` end
  return `el {t.day}/{t.month} {clock}`
end

function M.formatMoney(amountMinor: number?, exponent: number?,
                       currency: string?): string
  -- Un exponente fraccionario pasa las demás guardas y da un importe raro
  -- (blindaje pedido por el ledger de la Task 5 de Caelestia): ISO 4217 es
  -- siempre entero.
  local exp = if type(exponent) == "number" and exponent == exponent
                 and exponent >= 0 and exponent <= 100 and exponent % 1 == 0
              then exponent else 2

  local value = (if type(amountMinor) == "number" then amountMinor else 0) / (10 ^ exp)
  local symbol = (if currency then M.CURRENCY_SYMBOLS[currency] else nil)
                 or currency or "USD"
  local text = string.format(`%.{exp}f`, value)
  return `{(string.gsub(text, "%.", ","))} {symbol}`
end
```

- [ ] **Step 4: Ejecutar y confirmar que pasan**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add claude-usage/logic.luau claude-usage/tests/format.test.luau
git commit -m "feat: port the relative, absolute and money formatters"
```

---

### Task 5: Cadencia y backoff

**Files:**
- Modify: `claude-usage/logic.luau`
- Create: `claude-usage/tests/cadence.test.luau`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `M.MAX_INTERVAL = 1800`, `M.MIN_INTERVAL = 15`
  - `M.DEFAULT_IDLE_INTERVAL = 300`, `M.DEFAULT_ALERT_INTERVAL = 60`
  - `M.nextInterval(state: {warning: boolean, failures: number, idleInterval: number?, alertInterval: number?}) -> number` — **en segundos**
  - `M.toMilliseconds(seconds: number) -> number` — la ÚNICA conversión a la unidad del host

**No se porta `parseRetryAfter`** (constraint global). El campo `state.retryAfter` deja de existir.

- [ ] **Step 1: Escribir los tests que fallan**

`tests/cadence.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

h.describe("nextInterval", function()
  h.test("reposo y alerta usan sus bases", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 0,
      idleInterval = 300, alertInterval = 60 }), 300)
    h.eq(Logic.nextInterval({ warning = true, failures = 0,
      idleInterval = 300, alertInterval = 60 }), 60)
  end)

  h.test("el backoff dobla por fallo hasta el techo", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 1,
      idleInterval = 300, alertInterval = 60 }), 600)
    h.eq(Logic.nextInterval({ warning = false, failures = 2,
      idleInterval = 300, alertInterval = 60 }), 1200)
    h.eq(Logic.nextInterval({ warning = false, failures = 3,
      idleInterval = 300, alertInterval = 60 }), 1800) -- techo
    h.eq(Logic.nextInterval({ warning = false, failures = 9,
      idleInterval = 300, alertInterval = 60 }), 1800)
  end)

  -- La corrección que costó la Task 9b de Caelestia. No reintroducir.
  h.test("un fallo NUNCA sondea más rápido que la base del usuario", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 1,
      idleInterval = 3600, alertInterval = 60 }), 3600)
  end)

  h.test("la base del usuario se respeta aunque supere el techo", function()
    h.eq(Logic.nextInterval({ warning = false, failures = 0,
      idleInterval = 3600, alertInterval = 60 }), 3600)
  end)

  h.test("entrada basura cae al default del spec, no al suelo", function()
    for _, bad in { nil, 0, -5, 0/0, "300" } :: any do
      h.eq(Logic.nextInterval({ warning = false, failures = 0,
        idleInterval = bad, alertInterval = 60 }), 300)
    end
  end)

  h.test("el suelo protege de una base minúscula", function()
    h.eq(Logic.nextInterval({ warning = true, failures = 0,
      idleInterval = 300, alertInterval = 1 }), 15)
  end)
end)

h.describe("toMilliseconds", function()
  h.test("convierte segundos a la unidad del host", function()
    h.eq(Logic.toMilliseconds(300), 300000)
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL en el bloque nuevo.

- [ ] **Step 3: Implementar**

```lua
-- Techo del backoff (dobles por fallo), NO de la base que elige el usuario:
-- idleInterval/alertInterval pueden superarlo (spec §10). El propio backoff
-- nunca sondea por debajo de la base.
M.MAX_INTERVAL = 1800
M.MIN_INTERVAL = 15
M.DEFAULT_IDLE_INTERVAL = 300
M.DEFAULT_ALERT_INTERVAL = 60

-- Un valor solo es utilizable como intervalo si es un number finito y
-- estrictamente positivo. Cualquier otra cosa (nil, NaN, cadenas, 0,
-- negativos) es entrada basura y cae al default del spec, no al suelo: caer
-- al suelo sería el sondeo más agresivo posible por culpa de un ajuste roto.
local function usableInterval(value: any, fallback: number): number
  if type(value) ~= "number" then return fallback end
  if value ~= value then return fallback end          -- NaN
  if value == math.huge or value == -math.huge then return fallback end
  return if value > 0 then value else fallback
end

function M.nextInterval(state: {[string]: any}): number
  local base = if state.warning
    then usableInterval(state.alertInterval, M.DEFAULT_ALERT_INTERVAL)
    else usableInterval(state.idleInterval, M.DEFAULT_IDLE_INTERVAL)

  local failures = if type(state.failures) == "number" then state.failures else 0

  if failures > 0 then
    local doubled = base * (2 ^ failures)
    -- Dobla hasta el techo, pero nunca por debajo de la base: si la base ya
    -- supera el techo (p. ej. idleInterval 3600), un fallo no debe hacer el
    -- sondeo MÁS frecuente que en condiciones normales.
    return math.max(M.MIN_INTERVAL, base, math.min(doubled, M.MAX_INTERVAL))
  end

  return math.max(M.MIN_INTERVAL, base)
end

-- El host trabaja en milisegundos y todo lo de arriba en segundos. Esta es
-- la ÚNICA conversión del proyecto: si aparece otra, es un bug.
function M.toMilliseconds(seconds: number): number
  return seconds * 1000
end
```

- [ ] **Step 4: Ejecutar y confirmar que pasan**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 5: Commit**

```bash
git add claude-usage/logic.luau claude-usage/tests/cadence.test.luau
git commit -m "feat: port adaptive cadence and backoff

Drops parseRetryAfter: Noctalia's HttpResponse exposes no response headers,
so Retry-After is unreadable and a 429 falls to the failures backoff."
```

---

### Task 6: Credenciales y caché

**Files:**
- Modify: `claude-usage/logic.luau`
- Create: `claude-usage/tests/credentials.test.luau`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `M.TOKEN_MARGIN_MS = 60000`
  - `M.validMs(value: any) -> number?`
  - `M.parseCredentials(doc: {[string]: any}?, nowMs: number) -> {status: string, token: string?, expiresAt: number?}` — `status` ∈ `"ok" | "expired" | "invalid"`
  - `M.extractCache(doc: {[string]: any}?) -> {payload: any, fetchedAt: number}?`

**Cambio de firma respecto al original:** ambas reciben **tablas ya decodificadas**, no texto. El `noctalia.json.decode` vive en `service.luau` (constraint global). Un decode fallido llega aquí como `nil` y debe tratarse como inválido.

- [ ] **Step 1: Escribir los tests que fallan**

`tests/credentials.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

local NOW = 1786251600000 -- 2026-08-07T05:00:00Z

h.describe("parseCredentials", function()
  h.test("credenciales sanas", function()
    local r = Logic.parseCredentials(
      { claudeAiOauth = { accessToken = "sk-abc", expiresAt = NOW + 3600000 } }, NOW)
    h.eq(r.status, "ok")
    h.eq(r.token, "sk-abc")
  end)

  h.test("vencidas dentro del margen no entregan token", function()
    local r = Logic.parseCredentials(
      { claudeAiOauth = { accessToken = "sk-abc", expiresAt = NOW + 30000 } }, NOW)
    h.eq(r.status, "expired")
    h.nilish(r.token)
  end)

  h.test("nil (decode fallido) es inválido", function()
    h.eq(Logic.parseCredentials(nil, NOW).status, "invalid")
  end)

  h.test("sin claudeAiOauth es inválido", function()
    h.eq(Logic.parseCredentials({ otra = true }, NOW).status, "invalid")
  end)

  -- Falla CERRADO: los tres hallazgos de seguridad de la Task 7 de Caelestia.
  h.test("expiresAt no numérico NO entrega el token", function()
    for _, bad in { "1786251600000", nil, {}, true, 0/0 } :: any do
      local r = Logic.parseCredentials(
        { claudeAiOauth = { accessToken = "sk-abc", expiresAt = bad } }, NOW)
      h.eq(r.status, "invalid")
      h.nilish(r.token)
    end
  end)

  h.test("accessToken vacío o no cadena es inválido", function()
    for _, bad in { "", 12345, {}, nil } :: any do
      local r = Logic.parseCredentials(
        { claudeAiOauth = { accessToken = bad, expiresAt = NOW + 3600000 } }, NOW)
      h.eq(r.status, "invalid")
      h.nilish(r.token)
    end
  end)
end)

h.describe("extractCache", function()
  h.test("extrae payload y fecha", function()
    local r = Logic.extractCache({ cachedUsageUtilization = {
      utilization = { limits = {} }, fetchedAtMs = NOW } })
    h.eq(r.fetchedAt, NOW)
    h.truthy(r.payload)
  end)

  h.test("nil, sin clave, o fetchedAtMs inválido devuelven nil", function()
    h.nilish(Logic.extractCache(nil))
    h.nilish(Logic.extractCache({}))
    h.nilish(Logic.extractCache({ cachedUsageUtilization = {
      utilization = { limits = {} }, fetchedAtMs = 0 } }))
    h.nilish(Logic.extractCache({ cachedUsageUtilization = {
      utilization = { limits = {} }, fetchedAtMs = "ayer" } }))
    h.nilish(Logic.extractCache({ cachedUsageUtilization = {
      fetchedAtMs = NOW } }))
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL en el bloque nuevo.

- [ ] **Step 3: Implementar**

```lua
-- Margen para no lanzar una petición con un token que caduca a mitad de vuelo.
M.TOKEN_MARGIN_MS = 60000

-- Fallar CERRADO: un fichero de credenciales o de caché corrupto o manipulado
-- no debe interpretarse como válido solo porque una coerción implícita no
-- lance. Estas guardas devuelven nil ante cualquier cosa que no sea el tipo
-- esperado.
function M.validMs(value: any): number?
  if type(value) ~= "number" then return nil end
  if value ~= value then return nil end                       -- NaN
  if value == math.huge or value == -math.huge then return nil end
  return if value > 0 then value else nil
end

local function nonEmptyString(value: any): string?
  return if type(value) == "string" and value ~= "" then value else nil
end

function M.parseCredentials(doc: {[string]: any}?, nowMs: number): {[string]: any}
  local invalid = { status = "invalid", token = nil, expiresAt = nil }

  if type(doc) ~= "table" then return invalid end
  local oauth = doc.claudeAiOauth
  if type(oauth) ~= "table" then return invalid end

  local token = nonEmptyString(oauth.accessToken)
  local expiresAtMs = M.validMs(oauth.expiresAt)
  if not token or not expiresAtMs then return invalid end

  if nowMs > expiresAtMs - M.TOKEN_MARGIN_MS then
    return { status = "expired", token = nil, expiresAt = expiresAtMs }
  end

  return { status = "ok", token = token, expiresAt = expiresAtMs }
end

function M.extractCache(doc: {[string]: any}?): {[string]: any}?
  if type(doc) ~= "table" then return nil end
  local cached = doc.cachedUsageUtilization
  if type(cached) ~= "table" then return nil end

  local fetchedAt = M.validMs(cached.fetchedAtMs)
  if not fetchedAt or type(cached.utilization) ~= "table" then return nil end

  return { payload = cached.utilization, fetchedAt = fetchedAt }
end
```

- [ ] **Step 4: Ejecutar y confirmar que pasan**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 5: Verificar que ningún token real se ha versionado**

```bash
grep -rniE 'sk-ant|accessToken.*[A-Za-z0-9]{20}' claude-usage/ --include=*.json --include=*.luau \
  | grep -v 'sk-abc' || echo "sin tokens reales"
```

Esperado: `sin tokens reales`.

- [ ] **Step 6: Commit**

```bash
git add claude-usage/logic.luau claude-usage/tests/credentials.test.luau
git commit -m "feat: port credential and cache parsing, failing closed

Both now take already-decoded tables: logic.luau may not call the host JSON
API, so decoding lives in the service."
```

---

### Task 7: Notificaciones y antirrebote

**Files:**
- Modify: `claude-usage/logic.luau`
- Create: `claude-usage/tests/notifications.test.luau`

**Interfaces:**
- Consumes: `M.isWarning`, `M.formatAbsolute`, `M.validMs`.
- Produces:
  - `M.DEFAULT_WARN_THRESHOLD = 90`
  - `M.notificationsFor(limits: {any}, threshold: number?, prevState: {[string]: any}?, nowMs: number?) -> {notifications: {{key: string, summary: string, body: string}}, nextState: {[string]: any}}`

**Nota de traducción:** la identidad de ventana era `resetsAt.toISOString()`. Aquí es el propio epoch en ms convertido a string con `tostring`, para que el estado serialice a JSON sin ambigüedad.

- [ ] **Step 1: Escribir los tests que fallan**

`tests/notifications.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

local NOW = os.time({ year = 2026, month = 8, day = 7, hour = 9,
                      min = 0, sec = 0 }) * 1000
local RESET = os.time({ year = 2026, month = 8, day = 8, hour = 7,
                        min = 0, sec = 0 }) * 1000

local function limit(key, percent, severity, resetsAt)
  return { key = key, label = "la ventana semanal", percent = percent,
           severity = severity, resetsAt = resetsAt, scope = nil, primary = true }
end

h.describe("notificationsFor", function()
  h.test("notifica al cruzar el umbral", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 90, "normal", RESET) },
                                     90, {}, NOW)
    h.eq(#r.notifications, 1)
    h.eq(r.notifications[1].summary, "Claude")
    h.eq(r.notifications[1].body,
         "90 % de la ventana semanal consumido · se reinicia mañana a las 07:00")
    h.eq(r.nextState["weekly_all"].notified, true)
  end)

  h.test("no vuelve a notificar dentro de la misma ventana", function()
    local first = Logic.notificationsFor({ limit("weekly_all", 90, "normal", RESET) },
                                         90, {}, NOW)
    local second = Logic.notificationsFor({ limit("weekly_all", 95, "normal", RESET) },
                                          90, first.nextState, NOW)
    h.eq(#second.notifications, 0)
  end)

  h.test("una ventana nueva rearma el aviso", function()
    local first = Logic.notificationsFor({ limit("weekly_all", 90, "normal", RESET) },
                                         90, {}, NOW)
    local newReset = RESET + 7 * 24 * 3600000
    local second = Logic.notificationsFor({ limit("weekly_all", 91, "normal", newReset) },
                                          90, first.nextState, NOW)
    h.eq(#second.notifications, 1)
  end)

  -- Rama dip-and-rise: el ledger de la Task 8 la dejó SIN test. Aquí sí.
  h.test("bajar y volver a subir en la misma ventana no re-notifica", function()
    local a = Logic.notificationsFor({ limit("weekly_all", 91, "normal", RESET) },
                                     90, {}, NOW)
    local b = Logic.notificationsFor({ limit("weekly_all", 85, "normal", RESET) },
                                     90, a.nextState, NOW)
    local c = Logic.notificationsFor({ limit("weekly_all", 92, "normal", RESET) },
                                     90, b.nextState, NOW)
    h.eq(#c.notifications, 0)
  end)

  h.test("por debajo del umbral no notifica pero conserva la ventana", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 10, "normal", RESET) },
                                     90, {}, NOW)
    h.eq(#r.notifications, 0)
    h.eq(r.nextState["weekly_all"].notified, false)
  end)

  h.test("un threshold inválido cae al default, no a cero", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 50, "normal", RESET) },
                                     nil, {}, NOW)
    h.eq(#r.notifications, 0) -- 50 < 90; con threshold 0 habría notificado
  end)

  h.test("sin resetsAt válido omite la cláusula entera", function()
    local r = Logic.notificationsFor({ limit("weekly_all", 95, "normal", nil) },
                                     90, {}, NOW)
    h.eq(r.notifications[1].body, "95 % de la ventana semanal consumido")
  end)

  h.test("limits que no es tabla devuelve vacío sin lanzar", function()
    local r = Logic.notificationsFor(nil :: any, 90, {}, NOW)
    h.eq(#r.notifications, 0)
  end)

  h.test("una entrada nil en la lista se salta sin lanzar", function()
    local r = Logic.notificationsFor({ nil, limit("weekly_all", 95, "normal", RESET) } :: any,
                                     90, {}, NOW)
    h.eq(#r.notifications, 1)
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL en el bloque nuevo.

- [ ] **Step 3: Implementar**

```lua
-- Umbral de aviso por defecto del spec. Un threshold no numérico no debe
-- interpretarse como "avisar de todo" (equivalente a caer a 0): cae aquí.
M.DEFAULT_WARN_THRESHOLD = 90

-- Antirrebote: una notificación por ventana. La identidad de la ventana es su
-- resetsAt, así que reiniciar el shell no vuelve a avisar, y cuando la ventana
-- se renueva el aviso se rearma solo.
function M.notificationsFor(limits: {any}, threshold: number?,
                            prevState: {[string]: any}?,
                            nowMs: number?): {[string]: any}
  local notifications = {}
  local nextState = {}

  if type(limits) ~= "table" then
    return { notifications = notifications, nextState = nextState }
  end

  local effectiveThreshold = if type(threshold) == "number" and threshold == threshold
                             then threshold else M.DEFAULT_WARN_THRESHOLD
  local previous = if type(prevState) == "table" then prevState else {}
  local effectiveNow = M.validMs(nowMs)

  for _, limit in limits do
    if type(limit) ~= "table" then continue end

    local resetsAt = M.validMs(limit.resetsAt)
    local stamp = if resetsAt then tostring(resetsAt) else nil
    local before = previous[limit.key]
    local sameWindow = type(before) == "table" and before.resetsAt == stamp

    if not M.isWarning(limit, effectiveThreshold) then
      -- Se conserva el registro de la ventana en curso: si vuelve a subir por
      -- encima del umbral, no se notifica dos veces.
      nextState[limit.key] = if sameWindow then before
                             else { resetsAt = stamp, notified = false }
      continue
    end

    if sameWindow and before.notified then
      nextState[limit.key] = before
      continue
    end

    -- Sin resetsAt válido o sin un `now` válido no hay forma fiable de
    -- calcular la cláusula "se reinicia …"; se omite entera en vez de dejar
    -- un texto colgando.
    local resetClause = ""
    if resetsAt and effectiveNow then
      local absolute = M.formatAbsolute(resetsAt, effectiveNow)
      if absolute ~= "" then resetClause = ` · se reinicia {absolute}` end
    end

    table.insert(notifications, {
      key = limit.key,
      summary = "Claude",
      body = `{limit.percent} % de {limit.label} consumido{resetClause}`,
    })
    nextState[limit.key] = { resetsAt = stamp, notified = true }
  end

  return { notifications = notifications, nextState = nextState }
end
```

- [ ] **Step 4: Ejecutar y confirmar que pasan**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`. La suite completa debería rondar los 60-70 casos.

- [ ] **Step 5: Commit**

```bash
git add claude-usage/logic.luau claude-usage/tests/notifications.test.luau
git commit -m "feat: port notifications with per-window debounce

Adds the dip-and-rise test the Caelestia ledger flagged as missing."
```

---

### Task 8: Manifiesto y traducciones

**Files:**
- Create: `claude-usage/plugin.toml`
- Create: `claude-usage/translations/es.json`
- Create: `claude-usage/translations/en.json`
- Create: `claude-usage/tests/manifest.test.luau`

**Interfaces:**
- Consumes: `M.DEFAULT_WARN_THRESHOLD`, `M.DEFAULT_IDLE_INTERVAL`, `M.DEFAULT_ALERT_INTERVAL` de Tasks 5 y 7.
- Produces: las claves de ajuste `warn_threshold`, `idle_interval`, `alert_interval`, `show_scoped_limits`, `show_extra_usage`, `show_remaining`, que `service.luau`, `widget.luau` y `panel.luau` leen con `noctalia.getConfig`.

- [ ] **Step 1: Escribir el test de coherencia, que debe fallar**

El spec §10 avisa de que los valores por defecto viven en dos sitios y no pueden divergir. `tests/manifest.test.luau`:

```lua
local h = require("./harness")
local Logic = require("../logic")

-- El manifiesto es TOML y Luau no lo parsea. No hace falta: basta con leerlo
-- como texto y comprobar que los defaults que declara son los mismos que los
-- de logic.luau. Es la duplicación que el spec §10 acepta a regañadientes,
-- y este test es el precio de aceptarla.
local function readFile(path: string): string
  local f = assert(io.open(path, "r"))
  local contents = f:read("*a")
  f:close()
  return contents
end

h.describe("plugin.toml", function()
  local toml = readFile("claude-usage/plugin.toml")

  h.test("declara plugin_api 3", function()
    h.truthy(string.find(toml, "plugin_api = 3", 1, true))
  end)

  h.test("las tres entradas están declaradas", function()
    h.truthy(string.find(toml, "[[service]]", 1, true), "falta [[service]]")
    h.truthy(string.find(toml, "[[widget]]", 1, true), "falta [[widget]]")
    h.truthy(string.find(toml, "[[panel]]", 1, true), "falta [[panel]]")
  end)

  h.test("los defaults coinciden con los de logic.luau", function()
    local function defaultFor(key: string): number?
      local block = string.match(toml, `key = "{key}".-default = (%-?%d+)`)
      return tonumber(block)
    end
    h.eq(defaultFor("warn_threshold"), Logic.DEFAULT_WARN_THRESHOLD)
    h.eq(defaultFor("idle_interval"), Logic.DEFAULT_IDLE_INTERVAL)
    h.eq(defaultFor("alert_interval"), Logic.DEFAULT_ALERT_INTERVAL)
  end)

  h.test("los seis ajustes del spec existen", function()
    for _, key in { "warn_threshold", "idle_interval", "alert_interval",
                    "show_scoped_limits", "show_extra_usage", "show_remaining" } do
      h.truthy(string.find(toml, `key = "{key}"`, 1, true), `falta {key}`)
    end
  end)
end)

os.exit(if h.report() then 0 else 1)
```

- [ ] **Step 2: Ejecutar y confirmar que falla**

Run: `fish claude-usage/tests/run.fish`
Expected: FAIL — el `assert(io.open(...))` lanza porque `plugin.toml` no existe.

- [ ] **Step 3: Escribir el manifiesto**

`claude-usage/plugin.toml`:

```toml
# claude-usage — consumo de la suscripción de Claude en la barra de Noctalia.
# Diseño: docs/superpowers/specs/2026-08-07-claude-usage-noctalia-design.md
# Sucede al plugin homónimo de Caelestia, bloqueado por un sistema de plugins
# que nunca se mergeó.

id = "daf3r/claude-usage"
name = "Claude Usage"
version = "0.1.0"
# 3 es el nivel más antiguo que cubre [[widget]], [[panel]], los controles ui.*
# y barWidget.render. La entrada [[service]] necesita además una build que
# incluya ese tipo de entrada (Noctalia 5 beta, rev da014f72 o posterior).
plugin_api = 3
author = "daf3r"
license = "MIT"
icon = "gauge"
description = "Consumo de la suscripción de Claude: ventana de 5 h y semanal, con avisos."
dependencies = []
tags = ["ai", "productivity", "bar", "panel"]

# ── Ajustes (spec §10) ────────────────────────────────────────────────────────
# Los defaults se repiten en logic.luau (DEFAULT_*). El parser del manifiesto
# no puede leer Luau, así que la duplicación es inevitable; tests/manifest.test.luau
# comprueba que no divergen.

[[setting]]
key = "warn_threshold"
type = "int"
label_key = "settings.warn_threshold.label"
description_key = "settings.warn_threshold.description"
default = 90
min = 50
max = 99

[[setting]]
key = "idle_interval"
type = "int"
label_key = "settings.idle_interval.label"
description_key = "settings.idle_interval.description"
default = 300
min = 60
max = 3600

[[setting]]
key = "alert_interval"
type = "int"
label_key = "settings.alert_interval.label"
description_key = "settings.alert_interval.description"
default = 60
min = 15
max = 600

[[setting]]
key = "show_scoped_limits"
type = "bool"
label_key = "settings.show_scoped_limits.label"
default = true

[[setting]]
key = "show_extra_usage"
type = "bool"
label_key = "settings.show_extra_usage.label"
default = true

[[setting]]
key = "show_remaining"
type = "bool"
label_key = "settings.show_remaining.label"
description_key = "settings.show_remaining.description"
default = false

# ── Entradas ──────────────────────────────────────────────────────────────────
# El servicio es el único dueño de la red, los ficheros y el temporizador.
# Es headless a propósito: quitar el widget de la barra no debe apagar los
# avisos.
[[service]]
id = "poller"
entry = "service.luau"

[[widget]]
id = "meter"
entry = "widget.luau"

[[panel]]
id = "detail"
entry = "panel.luau"
width = 340
height = 420
placement = "floating"
position = "center"
```

- [ ] **Step 4: Escribir las traducciones**

`translations/es.json`:

```json
{
  "title": "Claude",
  "settings.warn_threshold.label": "Umbral de aviso",
  "settings.warn_threshold.description": "Porcentaje a partir del cual una ventana se considera en aviso.",
  "settings.idle_interval.label": "Intervalo en reposo (s)",
  "settings.idle_interval.description": "Cada cuánto se consulta el uso cuando nada está en aviso.",
  "settings.alert_interval.label": "Intervalo en alerta (s)",
  "settings.alert_interval.description": "Cada cuánto se consulta cuando alguna ventana está en aviso.",
  "settings.show_scoped_limits.label": "Mostrar sublímites por modelo",
  "settings.show_extra_usage.label": "Mostrar créditos extra",
  "settings.show_remaining.label": "Mostrar restante en vez de consumido",
  "settings.show_remaining.description": "El widget muestra lo que queda en lugar de lo gastado.",
  "state.loading": "Cargando…",
  "state.offline": "Sin conexión",
  "state.expired": "Sesión caducada. Abre Claude Code para renovarla.",
  "state.cache": "Caché local",
  "panel.refresh": "Refrescar",
  "panel.extraCredits": "Créditos extra",
  "panel.updatedAgo": "hace {age}"
}
```

`translations/en.json`: las mismas claves, en inglés. `"state.offline": "Offline"`, `"panel.refresh": "Refresh"`, `"state.expired": "Session expired. Open Claude Code to renew it."`, etc.

- [ ] **Step 5: Ejecutar y confirmar que pasa**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 6: Commit**

```bash
git add claude-usage/plugin.toml claude-usage/translations claude-usage/tests/manifest.test.luau
git commit -m "feat: add the manifest, settings and translations"
```

---

### Task 9: El servicio

Primera tarea con E/S real. **No es TDD:** `logic.luau` ya está probado y `service.luau` es pegamento contra APIs del host que no se pueden simular sin el shell. Se verifica ejecutando el shell.

**Files:**
- Create: `claude-usage/service.luau`

**Interfaces:**
- Consumes: todo `logic.luau`.
- Produces: la clave `usage` de `noctalia.state`, con la forma del spec §4.2. `widget.luau` y `panel.luau` la leen con `noctalia.state.get("usage")` y `noctalia.state.watch("usage", fn)`. También el evento IPC `refresh`.

- [ ] **Step 1: Escribir el servicio**

`claude-usage/service.luau`:

```lua
--!nonstrict
-- [[service]] headless: el único que toca red, ficheros, temporizador y
-- notificaciones. Publica un objeto YA CALCULADO en noctalia.state; el widget
-- y el panel solo pintan. Spec §4.
--
-- Es headless a propósito: quitar el widget de la barra no debe apagar los
-- avisos.

local Logic = require("./logic")

local ENDPOINT = "https://api.anthropic.com/api/oauth/usage"
local CREDENTIALS = "~/.claude/.credentials.json"
local CACHE = "~/.claude.json"

local failures = 0
local inFlight = false
local notifyState = {}
local lastModel = nil

-- ── Estado persistido del antirrebote ────────────────────────────────────────
local function stateFilePath(): string?
  local dir = noctalia.pluginDataDir()
  if not dir then return nil end
  noctalia.mkdirAll(dir)
  return `{dir}/state.json`
end

local function loadNotifyState()
  local path = stateFilePath()
  if not path then return end
  local text = noctalia.readFile(path)
  if not text then return end
  local ok, decoded = pcall(noctalia.json.decode, text)
  if ok and type(decoded) == "table" then notifyState = decoded end
end

local function saveNotifyState(next)
  local path = stateFilePath()
  if not path then return end
  -- Solo se escribe si el contenido cambia: el ledger de la Task 10 de
  -- Caelestia observó una reescritura por sondeo aunque nada cambiara.
  local encoded = noctalia.json.encode(next)
  if encoded == noctalia.json.encode(notifyState) then return end
  noctalia.writeFile(path, encoded)
end

-- ── Publicación ──────────────────────────────────────────────────────────────
local function publish(status: string, model, source: string?, fetchedAt: number?)
  local threshold = noctalia.getConfig("warn_threshold") or Logic.DEFAULT_WARN_THRESHOLD
  local showRemaining = noctalia.getConfig("show_remaining") == true

  if not model then
    noctalia.state.set("usage", { status = status, primary = nil, others = {} })
    return
  end

  local primary = Logic.pickPrimary(model.limits)
  local nowMs = noctalia.nowMs()

  local function decorate(l)
    if not l then return nil end
    local shown = if showRemaining then 100 - l.percent else l.percent
    return {
      key = l.key, label = l.label, percent = shown,
      warning = Logic.isWarning(l, threshold),
      glyph = if l.key == "session" then "hourglass" else "calendar",
      resetsRel = Logic.formatRelative(l.resetsAt, nowMs),
      resetsAbs = Logic.formatAbsolute(l.resetsAt, nowMs),
    }
  end

  local others = {}
  for _, l in Logic.sortForPanel(model.limits, primary and primary.key or nil) do
    table.insert(others, decorate(l))
  end

  noctalia.state.set("usage", {
    status = status,
    source = source,
    primary = decorate(primary),
    others = others,
    hiddenWarning = Logic.hasHiddenWarning(
      model.limits, primary and primary.key or nil, threshold),
    extraUsage = model.extraUsage,
    fetchedAtLabel = if fetchedAt
      then Logic.formatRelative(fetchedAt, nowMs) else nil,
  })
end

-- ── Cadencia ─────────────────────────────────────────────────────────────────
local function applyCadence(warning: boolean)
  local seconds = Logic.nextInterval({
    warning = warning,
    failures = failures,
    idleInterval = noctalia.getConfig("idle_interval"),
    alertInterval = noctalia.getConfig("alert_interval"),
  })
  noctalia.setUpdateInterval(Logic.toMilliseconds(seconds))
end

-- ── Respaldo por caché ───────────────────────────────────────────────────────
-- Solo se lee y parsea cuando la API falla (spec §3.2). Nunca notifica: el
-- ledger de la Task 10 observó un aviso disparado por un dato de una hora
-- antes.
local function fallbackToCache()
  local text = noctalia.readFile(CACHE)
  if not text then
    -- Sin caché: si hay último valor bueno en memoria se muestra atenuado, y
    -- si no, publish() con model nil hace que la UI diga "Sin conexión".
    publish("stale", lastModel)
    return
  end
  local ok, doc = pcall(noctalia.json.decode, text)
  local cached = if ok then Logic.extractCache(doc) else nil
  if not cached then
    publish("stale", lastModel)
    return
  end
  local model = Logic.normalizeUsage(cached.payload, "cache", cached.fetchedAt)
  lastModel = model
  publish("stale", model, "cache", cached.fetchedAt)
end

-- ── Sondeo ───────────────────────────────────────────────────────────────────
local function poll()
  if inFlight then return end

  local credText = noctalia.readFile(CREDENTIALS)
  if not credText then
    publish("missing", nil)
    return
  end

  local ok, doc = pcall(noctalia.json.decode, credText)
  local creds = Logic.parseCredentials(if ok then doc else nil, noctalia.nowMs())

  if creds.status == "expired" then
    publish("expired", lastModel)
    return
  end
  if creds.status ~= "ok" then
    publish("missing", nil)
    return
  end

  inFlight = true
  -- El token viaja SOLO aquí. Nunca a noctalia.log, ni a la UI, ni a un
  -- mensaje de error (spec §12).
  local started = noctalia.http({
    url = ENDPOINT,
    headers = {
      `Authorization: Bearer {creds.token}`,
      "anthropic-beta: oauth-2025-04-20",
    },
  }, function(res)
    inFlight = false

    if not res.ok or res.status >= 500 or res.status == 429 then
      -- Noctalia no expone cabeceras de respuesta, así que Retry-After es
      -- ilegible incluso en un 429: se usa el backoff propio (spec §8).
      failures += 1
      fallbackToCache()
      applyCadence(false)
      return
    end

    if res.status == 401 or res.status == 403 then
      publish("expired", lastModel)
      applyCadence(false)
      return
    end

    local parsedOk, payload = pcall(noctalia.json.decode, res.body)
    if not parsedOk or type(payload) ~= "table" then
      failures += 1
      fallbackToCache()
      applyCadence(false)
      return
    end

    failures = 0
    local nowMs = noctalia.nowMs()
    local model = Logic.normalizeUsage(payload, "api", nowMs)
    lastModel = model
    publish("ok", model, "api", nowMs)

    local threshold = noctalia.getConfig("warn_threshold") or Logic.DEFAULT_WARN_THRESHOLD
    local primary = Logic.pickPrimary(model.limits)
    local warning = Logic.isWarning(primary, threshold)
       or Logic.hasHiddenWarning(model.limits, nil, threshold)

    local result = Logic.notificationsFor(model.limits, threshold, notifyState, nowMs)
    for _, n in result.notifications do
      noctalia.notify(n.summary, n.body)
    end
    saveNotifyState(result.nextState)
    notifyState = result.nextState

    applyCadence(warning)
  end)

  if not started then
    inFlight = false
    failures += 1
    fallbackToCache()
    applyCadence(false)
  end
end

-- ── Arranque e IPC ───────────────────────────────────────────────────────────
loadNotifyState()
noctalia.state.set("usage", { status = "loading", primary = nil, others = {} })
applyCadence(false)

function update()
  poll()
end

-- Refresco bajo demanda desde el widget o el panel. El ledger de la Task 10
-- avisó de que dos refrescos seguidos colapsaban en uno: la guarda inFlight
-- hace que el segundo sea un no-op explícito, no un silencio.
function onIpc(event: string, _payload: string?)
  if event == "refresh" then poll() end
end
```

- [ ] **Step 2: Instalar el plugin para desarrollo**

```bash
ln -sfn ~/Projects/noctalia-plugins/claude-usage \
        ~/.local/state/noctalia/plugins/materialized/daf3r-claude-usage
```

Añadir `"daf3r/claude-usage"` al array `enabled` de `[plugins]`. **Ojo:** `~/.config/noctalia/config.toml` es un symlink de solo lectura al store de home-manager; el fichero mutable es `~/.local/state/noctalia/settings.toml` (ver la memoria `noctalia-settings-precedence`). Editar ese.

- [ ] **Step 3: Reiniciar el shell y comprobar que el servicio publica**

```bash
noctalia msg plugin daf3r/claude-usage:poller refresh
journalctl --user -u noctalia -n 40 --no-pager | grep -i claude-usage
```

Esperado: sin errores de carga. El estado debe pasar de `loading` a `ok`.

- [ ] **Step 4: Verificar que el token no se filtra a los logs**

```bash
journalctl --user -n 500 --no-pager | grep -ciE 'sk-ant|Bearer [A-Za-z0-9]' || echo "sin fugas"
```

Esperado: `sin fugas`. **Si esto falla, es un defecto de seguridad y bloquea la tarea.**

- [ ] **Step 5: Commit**

```bash
git add claude-usage/service.luau
git commit -m "feat: add the headless polling service"
```

---

### Task 10: El widget de barra

**Files:**
- Create: `claude-usage/widget.luau`

**Interfaces:**
- Consumes: `noctalia.state.get("usage")` / `watch`, publicado por Task 9.
- Produces: nada que consuman otras tareas.

- [ ] **Step 1: Escribir el widget**

```lua
--!nonstrict
-- [[widget]]: la píldora de barra. Solo pinta lo que el servicio ya decidió
-- (spec §5). Sin lógica de severidad, sin formateo de fechas.
--
-- El anillo del diseño de Caelestia NO es portable: ui.* no tiene arco ni
-- canvas. La ventana se codifica por GLIFO y la severidad por color, que
-- mantiene la propiedad que el anillo protegía — los dos canales separados,
-- así que ambas ventanas siguen distinguiéndose cuando las dos están en rojo.

local usage = noctalia.state.get("usage")

local function render()
  local u = usage
  if not u or u.status == "missing" then
    barWidget.render(nil) -- se oculta por completo (spec §9)
    return
  end

  if u.status == "loading" then
    barWidget.setGlyph("gauge")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("state.loading"))
    return
  end

  if u.status == "expired" then
    barWidget.setGlyph("key-off")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("state.expired"))
    return
  end

  -- stale con primary nulo = sin conexión y sin dato. Se dice, no se pinta un
  -- cero (carry-forward de las Tasks 11-13 de Caelestia).
  if not u.primary then
    barWidget.setGlyph("cloud-off")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("state.offline"))
    return
  end

  local p = u.primary
  local role = if p.warning then "error" else "secondary"
  local container = if barWidget.isVertical() then ui.column else ui.row

  local children = {
    ui.glyph({ name = p.glyph, size = 14, color = role }),
    ui.label({ text = tostring(p.percent), color = role, fontWeight = "bold" }),
  }

  -- El equivalente al punto de 4 px del original: la única forma de que un
  -- sublímite por modelo al 95 % no pase desapercibido, dado que el glifo
  -- solo puede representar dos ventanas.
  if u.hiddenWarning then
    table.insert(children, ui.glyph({ name = "alert-circle", size = 9, color = "error" }))
  end

  barWidget.render(container({
    gap = 4,
    align = "center",
    fill = if p.warning then "error/0.25" else nil,
    radius = 8,
    paddingH = 6,
  }, children))

  barWidget.setTooltip(`{p.label} · {p.percent} % · {p.resetsRel}`)
end

noctalia.state.watch("usage", function(value)
  usage = value
  render()
end)

-- Un clic alterna el panel. El refresco NO se dispara aquí: lo pide el propio
-- panel al montarse (spec §5), así que abrir refresca y cerrar no, sin que el
-- widget tenga que saber en qué estado quedó el panel.
function onClick()
  noctalia.togglePanel("daf3r/claude-usage:detail")
end

function update()
  render()
end
```

- [ ] **Step 2: Recargar y comprobar en pantalla**

Añadir el widget a la barra desde Ajustes → Bar → Widgets. Comprobar:
- Con datos frescos: glifo + número, sin tinte.
- Forzando `warn_threshold` a 1 desde ajustes: la píldora se tiñe y el número se pone en rol `error`.

- [ ] **Step 3: Commit**

```bash
git add claude-usage/widget.luau
git commit -m "feat: add the bar widget

Encodes the window by glyph and severity by colour: ui.* has no arc, so the
original shape-encoded ring is not portable."
```

---

### Task 11: El panel

**Files:**
- Create: `claude-usage/panel.luau`

**Interfaces:**
- Consumes: `noctalia.state.get("usage")` / `watch`; el evento IPC `refresh` del servicio (Task 9).
- Produces: nada.

- [ ] **Step 1: Escribir el panel**

```lua
--!nonstrict
-- [[panel]]: el desglose. Layout P2 del spec §6 — la ventana crítica manda,
-- el resto en lista fina. Todo el texto llega ya formateado del servicio.

local Logic = require("./logic")
local usage = noctalia.state.get("usage")

-- El refresco se pide al servicio por IPC: el panel no toca la red.
local function requestRefresh()
  noctalia.runAsync({ "noctalia", "msg", "plugin",
                      "daf3r/claude-usage:poller", "refresh" }, function() end)
end

local function render()
  local u = usage

  if not u or u.status == "loading" then
    panel.render(ui.column({ gap = 8, padding = 16 }, {
      ui.label({ text = noctalia.tr("state.loading") }),
    }))
    return
  end

  if u.status == "expired" then
    panel.render(ui.column({ gap = 8, padding = 16 }, {
      ui.glyph({ name = "key-off", size = 24, color = "error" }),
      ui.label({ text = noctalia.tr("state.expired") }),
    }))
    return
  end

  if not u.primary then
    panel.render(ui.column({ gap = 8, padding = 16 }, {
      ui.label({ text = noctalia.tr("state.offline") }),
      ui.button({ label = noctalia.tr("panel.refresh"), onClick = requestRefresh }),
    }))
    return
  end

  local rows = {}

  -- 1. Tarjeta destacada.
  local p = u.primary
  table.insert(rows, ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = p.glyph, size = 16,
               color = if p.warning then "error" else "primary" }),
    ui.label({ text = p.label, fontWeight = "bold" }),
    ui.spacer({}),
    ui.label({ text = `{p.percent} %`, fontWeight = "bold",
               color = if p.warning then "error" else nil }),
  }))
  table.insert(rows, ui.progress({
    value = p.percent / 100,
    color = if p.warning then "error" else "primary",
  }))
  if p.resetsAbs ~= "" then
    table.insert(rows, ui.label({
      text = `{p.resetsAbs} · {p.resetsRel}`, color = "onSurfaceVariant" }))
  else
    table.insert(rows, ui.label({ text = p.resetsRel, color = "onSurfaceVariant" }))
  end

  -- 2. Resto de límites.
  if noctalia.getConfig("show_scoped_limits") ~= false and #u.others > 0 then
    table.insert(rows, ui.separator({}))
    for _, o in u.others do
      table.insert(rows, ui.row({ gap = 8 }, {
        ui.label({ text = o.label }),
        ui.spacer({}),
        ui.label({ text = `{o.percent} %`,
                   color = if o.warning then "error" else nil }),
      }))
    end
  end

  -- 3. Créditos extra.
  local extra = u.extraUsage
  if noctalia.getConfig("show_extra_usage") ~= false and extra
     and (extra.enabled or extra.everEnabled) then
    table.insert(rows, ui.separator({}))
    table.insert(rows, ui.row({ gap = 8 }, {
      ui.label({ text = noctalia.tr("panel.extraCredits") }),
      ui.spacer({}),
      ui.label({ text = `{Logic.formatMoney(extra.usedMinor, extra.exponent, extra.currency)} / {Logic.formatMoney(extra.limitMinor, extra.exponent, extra.currency)}` }),
    }))
  end

  -- 4. Pie.
  table.insert(rows, ui.separator({}))
  table.insert(rows, ui.row({ gap = 8, align = "center" }, {
    ui.label({
      text = if u.source == "cache"
        then `{noctalia.tr("state.cache")} · {u.fetchedAtLabel or ""}`
        else (u.fetchedAtLabel or ""),
      color = "onSurfaceVariant",
    }),
    ui.spacer({}),
    ui.button({ label = noctalia.tr("panel.refresh"), glyph = "refresh",
                variant = "ghost", onClick = requestRefresh }),
  }))

  panel.render(ui.scroll({}, { ui.column({ gap = 8, padding = 16 }, rows) }))
end

noctalia.state.watch("usage", function(value)
  usage = value
  render()
end)

-- Refresco inmediato al abrir (spec §7).
requestRefresh()
render()
```

- [ ] **Step 2: Abrir y comprobar**

```bash
noctalia msg panel-toggle daf3r/claude-usage:detail
```

Comprobar que la barra de progreso, las filas y el pie se pintan, y que el botón de refrescar actualiza la etiqueta de antigüedad.

- [ ] **Step 3: Commit**

```bash
git add claude-usage/panel.luau
git commit -m "feat: add the detail panel"
```

---

### Task 12: Validación de los siete estados

Los estados de error solo se prueban forzándolos. El spec §9 los define; esta tarea comprueba los siete en el shell real.

**Files:**
- Create: `claude-usage/tests/MANUAL.md`

- [ ] **Step 1: Ejercitar cada estado y anotar el resultado**

Crear `tests/MANUAL.md` con una tabla de los siete casos, y para cada uno el procedimiento y lo observado:

| # | Estado | Cómo forzarlo | Esperado |
|---|---|---|---|
| 1 | Dato fresco | Normal | Píldora con número; pie "hace N s" |
| 2 | Sin conexión, con dato | `nmcli networking off` tras un sondeo bueno | Píldora atenuada; "Sin conexión · dato de hace N min" |
| 3 | Sin conexión, sin dato | Red apagada + reiniciar shell, con `~/.claude.json` presente | "Caché local · hace N" |
| 4 | Token vencido | Copiar `.credentials.json` a un temporal y poner `expiresAt` en el pasado | Glifo de llave; "Sesión caducada" |
| 5 | Sin credenciales | Renombrar `.credentials.json` temporalmente | **Widget oculto** |
| 6 | Arranque | Reiniciar el shell y mirar el primer segundo | "Cargando…" |
| 7 | JSON corrupto | Fichero de credenciales con `{{{` | Igual que "sin conexión", sin traza en el log |

**Restaurar `.credentials.json` al terminar cada caso.** Trabajar sobre una copia y no sobre el original.

- [ ] **Step 2: Comprobar que la suite sigue verde**

Run: `fish claude-usage/tests/run.fish`
Expected: `# fail 0`.

- [ ] **Step 3: Commit**

```bash
git add claude-usage/tests/MANUAL.md
git commit -m "test: record the manual validation of the seven error states"
```

---

## Auto-revisión del plan

**Cobertura del spec:**

| Sección del spec | Tarea |
|---|---|
| §3 Fuente de datos (API + caché) | 9 |
| §4 Arquitectura y contrato de estado | 9 |
| §4.2 Desempate de criticidad | 3 |
| §5 Widget de barra | 10 |
| §6 Panel | 11 |
| §7 Cadencia y backoff | 5, 9 |
| §8 Renuncia a `Retry-After` | 5, 9 |
| §9 Estados y errores | 9, 10, 12 |
| §10 Ajustes | 8 |
| §11 Notificaciones y antirrebote | 7, 9 |
| §12 Seguridad | 6 (paso 5), 9 (paso 4) |
| §13 Pruebas y entorno | 1 |

Sin huecos.

**Riesgos conocidos que el implementador debe vigilar:**

1. **`parseIsoMs` (Task 2) es lo más frágil del port.** Luau no parsea ISO 8601 y `os.time` trabaja en hora local. Si el test de esa función falla, no seguir adelante: todo el formateo de fechas depende de ella.
2. **`ui.progress`, `ui.separator` y `ui.spacer` están declarados en `noctalia.d.luau` pero el plugin `example` no los ejercita.** Si alguno no acepta las props que usa la Task 11, sustituir por `ui.box` con `fill` y anotarlo en el ledger — no rediseñar el panel entero.
3. **`noctalia.togglePanel` en `widget.luau` (Task 10) y el refresco por IPC en `panel.luau` (Task 11) están escritos sin haberse ejecutado.** Son los dos puntos donde más probable es que la firma real difiera. Verificar contra `noctalia.d.luau` antes de escribirlos.
