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
- **2026-08-07** — spec aprobada para Noctalia v5 **e implementada entera**: `logic.luau`
  (548 líneas), `service.luau`, `widget.luau`, `panel.luau`, catálogo i18n en dos idiomas
  y once ficheros de test, en quince commits.

> **Corrección del 2026-08-10.** La primera versión de este documento afirmaba que la
> implementación de Noctalia no existía, y sobre esa premisa construía una §2 titulada
> "el puerto a DMS es barato" que daba por hecho copiar el `logic.js` de Caelestia. Era
> falso: bastaba listar `claude-usage/` en este repo para verlo. El error se detectó al
> ejecutar la tarea 2 del plan, cuando el subagente encontró la implementación en Luau y
> preguntó qué hacer con ella. Las secciones 2 y 3 están reescritas; lo que sigue vigente
> se marca como tal.
- **2026-08-10** — daf3r migra a DMS (ver `~/nixos-config`, rama `dms`). Este documento.

**Este documento no repite la spec de Noctalia.** Todo lo que no dependía del shell se
hereda literal de `2026-08-07-claude-usage-noctalia-design.md`, que se conserva en este
mismo directorio: fuente de datos (§3), cadencia (§7), estados y errores (§9), ajustes
(§10), notificaciones (§11), seguridad (§12) y fuera de alcance (§14). Aquí solo está lo
que **cambia** al pasar a DMS.

## 2. De qué versión se parte

Hay **dos implementaciones terminadas** del mismo plugin, y la pregunta no es Luau contra
JavaScript: es cuál de los dos diseños se conserva.

|  | Caelestia (2026-08-03) | Noctalia (2026-08-07) |
| --- | --- | --- |
| Lenguaje | QML + JavaScript | Luau |
| Lógica | `logic.js`, 506 líneas | `logic.luau`, **548 líneas** |
| Funciones | 28 | **30** |
| Formato de textos | devuelve cadenas ya formateadas | devuelve **descriptores** |
| i18n | no | **catálogo `en` + `es`** |
| Tests | 1 fichero, 69 casos | **11 ficheros** + `MANUAL.md` |

**Se parte de la de Noctalia**, que es posterior y mejor. Su refactor no es cosmético:
`formatRelative` devolvía `"en 10 h 34 min"`, mientras `describeRelative` devuelve
`{ key = "time.in", params = { duration = "10 h 34 min" } }` y deja que un catálogo
resuelva la clave. Eso es lo que hizo posible el español, y es la diferencia entre un
plugin traducible y uno que no lo es.

Elegir Caelestia por estar ya en JavaScript habría sido optimizar el coste de la
traducción a costa del producto.

### Lo que cuesta

`logic.luau` tiene 548 líneas y **solo 4 referencias** a la API del host: es lógica pura
de verdad. Y su antepasado directo son las 506 líneas de `logic.js`, en el mismo lenguaje
al que hay que volver. No es traducir desde cero, es aplicar el refactor de descriptores
sobre una base que ya existe en JavaScript.

Lo caro son las **94 ataduras al host** repartidas en el resto:

| Fichero | Líneas | Referencias `noctalia.*` / `ui.*` | Destino en DMS |
| --- | --- | --- | --- |
| `logic.luau` | 548 | 4 | `logic.js` |
| `service.luau` | 281 | 34 | `Daemon.qml` |
| `panel.luau` | 165 | 47 | `popoutContent` de `Widget.qml` |
| `widget.luau` | 127 | 13 | píldoras de `Widget.qml` |
| `translations/*.json` | 46 + 46 | — | **se reutilizan tal cual** |

Los 11 ficheros de test en Luau son el mapa del port y se traducen a `node --test`. El
`logic.js` y los 69 casos de Caelestia quedan como referencia de consulta, no como base.

## 2 bis. i18n: el catálogo y su renderizador

`logic.js` no formatea texto de cara al usuario. Devuelve **descriptores**:

```js
{ key: "time.in", params: { duration: "10 h 34 min" } }
```

`translations/en.json` y `es.json` mapean la clave a una plantilla con marcadores
`{param}` — 46 líneas cada uno, y **se reutilizan sin tocar**: son JSON y no saben nada de
Luau ni de Noctalia.

Lo que falta es el renderizador. Noctalia resolvía las claves por su cuenta; **DMS no
tiene i18n para plugins**, así que se escribe uno: un `i18n.js` que carga el catálogo del
idioma, resuelve `key` e interpola `params`, con respaldo a `en` cuando falta una clave y
a la propia clave cuando falta en ambos. Es pequeño y es lógica pura, así que se prueba
con `node --test` como el resto.

`tests/translations.test.luau` ya cubre que cada clave usada por la lógica existe en los
dos catálogos. Ese test se porta y sigue siendo la red que impide que un descriptor nuevo
salga a producción sin traducir.

## 3. Tres cosas que este port recupera y el de Noctalia perdía

Son deudas que la spec de Noctalia documentaba como inevitables. En DMS no lo son.

### 3.1 `parseRetryAfter` vuelve, y hay que traerla a mano

Noctalia expone `HttpResponse = { ok, status, body }` — **sin cabeceras**. La §8 de aquella
spec eliminaba `parseRetryAfter`, y `logic.luau` en efecto **no la contiene**: `grep` da
cero.

El spike del 2026-08-10 (tarea 1) confirmó que `XMLHttpRequest` sí lee cabeceras dentro
de un plugin de DMS: la píldora de prueba devolvió `status=429 date=SI`. Así que la
función vuelve — pero **no sale de `logic.luau`, hay que recuperarla de `logic.js` de
Caelestia**, junto con los casos de test que la cubrían. Es la única pieza que viaja en
sentido contrario al resto del port.

El 429 del spike, además, no fue casual: el endpoint limita de verdad, así que respetar
`Retry-After` no es un adorno.

### 3.2 El `UsageRing` vuelve

El vocabulario `ui.*` de Noctalia no tiene arco ni canvas, así que el anillo con la
ventana codificada por forma (commit `1609cad`) no se podía dibujar. `Canvas` es QtQuick
de base: el componente se recupera del árbol de Caelestia.

### 3.3 El desempate explícito se conserva, aunque JavaScript no lo exija

La §4.2 de Noctalia anotaba que `table.sort` de Luau **no es estable**, y que sin un
tercer criterio el glifo de la barra alternaría entre sesión y semana entre refrescos con
el mismo dato. `logic.luau` lo resolvió desempatando por `key`:

```lua
if ra ~= rb then return ra > rb end
if a.percent ~= b.percent then return a.percent > b.percent end
return a.key < b.key
```

Su comentario añade una segunda razón, que no es de Luau: sin desempate, un comparador
que devuelve el mismo sentido para el par `(a,b)` y `(b,a)` **lanza "invalid order
function for sorting"**.

`Array.prototype.sort` de JavaScript es estable por norma desde ES2019, así que el port
podría prescindir de la tercera línea. **No lo hace.** Un orden total, determinista e
irreflexivo es correcto por sí mismo, no por lo que garantice el motor de turno, y
quitarlo cambiaría el resultado de los tests de ordenación heredados sin ganar nada.

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

`logic.js` no importa nada del host. Es lo que permite correr la suite con
`node --test` **sin levantar el shell**, y es la propiedad que sobrevive intacta a los
tres cambios de destino. La suite ya NO se copia sin tocar: los 11 ficheros de test en
Luau se traducen a `node --test`, y son ellos —no los 69 casos de Caelestia— la red que
verifica el port. Cada fichero portado debe estar en verde antes de pasar al siguiente.

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
