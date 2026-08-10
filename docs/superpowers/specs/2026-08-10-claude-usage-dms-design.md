# Diseño — plugin `claude-usage` para DankMaterialShell

Fecha: 2026-08-10 · Estado: aprobado, pendiente de plan de implementación

Muestra en la barra de DMS el consumo de la suscripción de Claude, y desglosa las
ventanas de límite en un popout.

## 1. Por qué existe este documento

Es el **tercer destino** del mismo plugin. El diseño no cambia; cambia el shell debajo.

- **2026-08-03** — spec aprobada para Caelestia. Implementación al 85 %, 69 tests en
  verde, rama `feat/claude-usage` (`c47b2f1`). Bloqueada por causa ajena: el sistema de
  plugins de Caelestia ([PR #1703](https://github.com/caelestia-dots/shell/pull/1703))
  sigue sin mergear.
- **2026-08-07** — spec aprobada para Noctalia v5, sin implementar. Exigía traducir todo
  a Luau.
- **2026-08-10** — daf3r migra a DMS (ver `~/nixos-config`, rama `dms`). Este documento.

**Este documento no repite la spec de Noctalia.** Todo lo que no dependía del shell se
hereda literal de `2026-08-07-claude-usage-noctalia-design.md`, que se conserva en este
mismo directorio: fuente de datos (§3), cadencia (§7), estados y errores (§9), ajustes
(§10), notificaciones (§11), seguridad (§12) y fuera de alcance (§14). Aquí solo está lo
que **cambia** al pasar a DMS.

## 2. El puerto a DMS es barato, y por qué

Los plugins de Noctalia se escriben en **Luau**. Los de DMS, en **QML + JavaScript** —
los mismos dos lenguajes que Caelestia. La traducción función por función que dominaba
el presupuesto del port a Noctalia **desaparece**.

| Fichero | Origen | Trabajo en DMS |
| --- | --- | --- |
| `logic.js` (506 líneas) | Caelestia | **ninguno**, se copia tal cual |
| `tests/logic.test.js` + 4 fixtures + `run.fish` | Caelestia | **ninguno**, se copian |
| `plugin.json` | `manifest.json` | traducir al esquema de DMS |
| `Daemon.qml` | `UsageService.qml` | adaptar a `PluginComponent` sin UI |
| `Widget.qml` | `widget` + `panel` de Noctalia | fusionar en uno (ver §4) |
| `Settings.qml` | `Settings.qml` | adaptar a los componentes de ajustes de DMS |
| `components/UsageRing.qml` | Caelestia | retematizar a los tokens de DMS |

El 85 % vuelve a ser 85 % real, no un 85 % que había que reescribir.

## 3. Tres cosas que este port recupera y el de Noctalia perdía

Son deudas que la spec de Noctalia documentaba como inevitables. En DMS no lo son.

### 3.1 `parseRetryAfter` vuelve

Noctalia expone `HttpResponse = { ok, status, body }` — **sin cabeceras**. La §8 de aquella
spec eliminaba `parseRetryAfter` y dejaba el 429 en backoff por duplicación, y lo llamaba
"la única regla de la spec heredada que no se cumple al pie de la letra".

En QML las cabeceras son legibles por los dos caminos de §5. La regla original de la
spec de Caelestia (§6) **se cumple entera**.

### 3.2 El `UsageRing` vuelve

El vocabulario `ui.*` de Noctalia no tiene arco ni canvas, así que el anillo con la
ventana codificada por forma (commit `1609cad`) no se podía dibujar. `Canvas` es QtQuick
de base: el componente se recupera del árbol de Caelestia.

### 3.3 El desempate explícito sobra

La §4.2 de Noctalia anotaba que `table.sort` de Luau **no es estable**, y que sin un
tercer criterio por índice en `PRIMARY_KINDS` el glifo de la barra alternaría entre
sesión y semana entre refrescos con el mismo dato.

`Array.prototype.sort` de JavaScript **es estable por norma desde ES2019**. La asunción
original de `logic.js` vuelve a ser correcta y el parche no se escribe.

## 4. Arquitectura: `composite`, no `widget`

La spec de Noctalia (§4) exige una propiedad explícita:

> quitar el widget de la barra no apaga el sondeo ni las notificaciones

En DMS un plugin de tipo `widget` se instancia **cuando se coloca en una sección de la
barra**, y deja de correr al quitarlo. Un `widget` puro perdería esa propiedad, y con ella
las notificaciones de límite de §11 — que son el mecanismo que existe para no llegar al
tope sin verlo venir.

El tipo fiel es `composite`, con dos superficies:

```
plugin.json  (type: "composite")
   │
   ├── Daemon.qml    ← service.luau: HTTP, temporizador, estado, notify
   │                    headless, arranca con el shell, sobrevive a quitar la píldora
   │
   └── Widget.qml    ← píldora en la barra + popout
                        en DMS el popout es parte del tipo widget, así que las dos
                        entradas separadas de Noctalia (widget + panel) se funden
   │
   ├── logic.js      ← lógica pura, cero API del host
   └── tests/        ← 69 casos, corren sin levantar el shell
```

El contrato de estado de §4.2 de Noctalia se mantiene: **un solo objeto ya calculado y
preformateado**, publicado por el daemon y leído por el widget. La UI no evalúa
severidad, no ordena y no formatea fechas.

## 5. Camino HTTP — a decidir con un spike

**`Quickshell.Networking` NO sirve para esto.** La doc de plugins de DMS
(`.agents/skills/dms-plugin-dev/references/advanced-patterns.md`) muestra un tipo
`NetworkRequest` con `url`, `method` y `onResponseReceived`. En el Quickshell 0.3.0 que
corre esta máquina, `Quickshell.Networking` es **NetworkManager** — `address`,
`autoconnect`, `connectWithPsk`, `connectivity`. No existe ningún `NetworkRequest` HTTP.

Verificado el 2026-08-10 sobre
`/nix/store/w3s69yqqgy1c4s82czlv3ygrc2j1jwwh-quickshell-0.3.0`. Seguir esa doc al pie de
la letra cuesta una tarde.

Quedan dos candidatos, ambos capaces de leer cabeceras:

| Camino | Cabeceras | Riesgo |
| --- | --- | --- |
| `XMLHttpRequest` de QtQml | `getResponseHeader()` | que Quickshell lo restrinja en el contexto del plugin |
| `Quickshell.Io` + `Process` → `curl -D -` | sí | un proceso externo por sondeo |

**Tarea 1 de la implementación es un spike** que prueba exactamente dos cosas: una
píldora que pinta en la barra, y un GET autenticado que lee `Retry-After`. Se tira
después. Va primero porque si el camino bueno es `Process`, eso cambia la forma de
`Daemon.qml` — el fichero que el port reescribe — y descubrirlo después es el orden caro.

No se intentó cerrar el spike durante el diseño: el `qml` del store no resuelve sus
imports fuera de una sesión de Quickshell, y forzarlo no habría probado el caso real.

## 6. Empaquetado y distribución

**Repo:** `Daf3r/noctalia-plugins` → renombrar a **`Daf3r/dms-plugins`**, y actualizar la
descripción, que hoy dice "Plugins propios para Noctalia 5". Ya es público. GitHub
mantiene la redirección del nombre viejo.

Se renombra en lugar de crear repo nuevo porque la spec de Noctalia es el 90 % del diseño
heredado —fuente de datos, modelo normalizado, criticidad, cadencia, estados de error,
ajustes, antirrebote, casos de prueba— y rehacerla en un repo limpio es trabajo por nada.
El nombre "noctalia" en los commits antiguos es un coste cosmético; un commit de
renombrado lo documenta.

**Durante el desarrollo:** symlink a `~/.config/DankMaterialShell/plugins/claude-usage`.
Sin Nix, para tener recarga en vivo sin un rebuild por cambio.

**Cuando esté estable:** se declara en `~/nixos-config/dms.nix`, que ya reserva el hueco:

```nix
plugins.claude-usage = {
  enable = true;
  src = /home/daf3r/Projects/dms-plugins/claude-usage;
};
```

`src` acepta ruta local, así que no hace falta publicar nada para que Nix lo instale.

**Registro:** **no** se publica en `plugins.danklinux.com` de momento. El endpoint de §3
de la spec heredada no está documentado y puede desaparecer sin aviso; publicar en el
registro algo que se rompe solo genera mantenimiento ajeno. Repo público sí, registro no.
Revisable cuando lleve tiempo estable.

## 7. Pruebas

`logic.js` no importa nada del host. Es lo que permite correr los 69 casos con
`node --test` **sin levantar el shell**, y es la propiedad que sobrevive intacta a los
tres cambios de destino. La suite se copia sin tocar y debe estar en verde antes y
después del port.

`tests/run.fish` se copia igual y ya trae dos cosas que no hay que redescubrir: fija
`TZ=Europe/Madrid`, sin lo cual los formatos de hora no son deterministas, y pasa el glob
de ficheros en vez del directorio, porque `node --test <dir>` falla con `MODULE_NOT_FOUND`
en node v26.4.0.

Lo que la suite no cubre —render QML, integración con la barra, popout— se verifica a
mano, con la misma pasada de los siete estados que `docs/superpowers/notes/` registra
para Caelestia.

## 8. Fuera de alcance en la v1

Lo de §14 de la spec heredada, sin cambios. Y además:

- **Registro público de DMS.** Ver §6.
- **Superficies extra de `composite`.** DMS permite también widget de escritorio y
  entradas de launcher. No entran en la v1: el mismo `logic.js` las alimentaría el día
  que se quieran, sin rehacer nada.
- **Greeter.** No aplica.
