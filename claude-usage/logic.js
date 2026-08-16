// Lógica pura del plugin claude-usage. Traducción de logic.luau.
//
// REGLA: este fichero no llama a NINGUNA API host. Ni QML, ni Quickshell, ni
// DMS. Lo que necesite del entorno se le pasa por parámetro. Es lo que permite
// correr la suite con `node --test` sin levantar el shell.
//
// Se carga desde dos entornos: el motor JavaScript de QML (via
// `import "logic.js" as Logic`) y node (en las pruebas). Por eso:
//   - Nada de QML aquí dentro. Ni un import, ni un tipo, ni Qt.*
//   - ES5 estricto: sin ?., sin ??, sin arrow functions, sin template literals.
//   - El guardián de module.exports al final sirve a los dos.
//
// Nombrado: TODO lo público se declara como `var`/`function` de nivel
// superior, nunca colgado de un objeto contenedor interno. Un fichero
// importado con `import "logic.js" as Logic` NO expone `module.exports`:
// expone las declaraciones de nivel superior del propio script. Con un
// `var Logic = {}` interno, el QML que lo importara "as Logic" tendría que
// escribir `Logic.Logic.foo(...)` — comprobado en vivo en Caelestia.
//
// Las fechas viajan como epoch en MILISEGUNDOS, igual que en logic.luau
// (allí porque Luau no trae Date; aquí porque es el contrato ya fijado y
// porque un número cruza la frontera QML/JS sin sorpresas).
//
// AUSENCIA = null. El original devuelve `nil` en los retornos opcionales;
// aquí es siempre `null` y nunca `undefined`, para que el valor "no hay
// nada" sea uno solo y se pueda comparar de forma estricta. `undefined`
// queda reservado a "esta propiedad no existe".
//
// TRADUCCIÓN: este fichero cubre los helpers puros de formato (tarea 3 del
// plan), la normalización del payload más el orden del panel (tarea 4) y la
// cadencia, las credenciales y las notificaciones (tarea 5). Con eso está
// traducido logic.luau entero; el .luau sigue siendo la fuente de contraste y
// no se borra hasta la última tarea.
//
// La ÚNICA pieza que no viene de logic.luau es parseRetryAfter (más
// clampInterval y la rama de retryAfter de nextInterval, que existen para
// aplicarla). Viaja al revés: el port a Noctalia la eliminó porque su API HTTP
// no exponía cabeceras de respuesta, y en DMS sí se leen
// (XMLHttpRequest.getResponseHeader). Se recupera del árbol de Caelestia.

// ---------------------------------------------------------------------------
// Guardas de tipo
// ---------------------------------------------------------------------------

// `v == v` descarta NaN, que en Luau y en JS es el único number que no es
// igual a sí mismo.
function num(v, fallback) {
    return (typeof v === "number" && v === v) ? v : fallback;
}

// Fallar CERRADO: un fichero de credenciales o de caché corrupto o manipulado
// no debe interpretarse como válido solo porque una coerción implícita no
// lance. Devuelve null ante cualquier cosa que no sea un epoch en ms
// utilizable.
function validMs(value) {
    if (typeof value !== "number") return null;
    if (value !== value) return null;                    // NaN
    if (value === Infinity || value === -Infinity) return null;
    return value > 0 ? value : null;
}

// El host trabaja en milisegundos y los intervalos en segundos. Esta es la
// ÚNICA conversión del proyecto: si aparece otra, es un bug.
function toMilliseconds(seconds) {
    return seconds * 1000;
}

// ---------------------------------------------------------------------------
// Fechas
// ---------------------------------------------------------------------------

// Segundos que hay que sumarle al epoch que produce la recomposición de una
// hora "desnuda" (sin zona) para obtener el instante UTC de esos campos.
//
// Es la misma fórmula de logic.luau y da, igual que allí, 0: el equivalente
// en JS del `os.time` de Luau —que interpreta su tabla en UTC (timegm) y no
// en hora local (mktime)— es Date.UTC, así que la ida y la vuelta se
// cancelan. Se conserva porque la fórmula da el desfase correcto sea cual
// sea la semántica de la recomposición, y así parseIsoMs no depende de cuál
// esté vigente.
function localUtcOffsetSeconds() {
    var t = Date.UTC(2000, 0, 1, 0, 0, 0) / 1000;
    var d = new Date(t * 1000);
    var utc = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(),
                       d.getUTCHours(), d.getUTCMinutes(), d.getUTCSeconds()) / 1000;
    return t - utc;
}

var ISO_PATTERN = /^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)/;
var ISO_OFFSET_PATTERN = /([+\-])(\d\d):?(\d\d)$/;

// La API entrega "2026-08-07T05:00:00+00:00" o "...Z". No se usa
// `new Date(value)` a propósito: el parseo de cadenas de Date es laxo y
// dependiente del motor (QML y node no tienen por qué coincidir en las
// variantes fuera de la gramática de ES), y este parseo tiene que dar el
// mismo número en los dos entornos.
//
// Los índices del array que devuelve exec() empiezan en 0 y el 0 es la
// coincidencia entera: las capturas van de 1 en adelante. En Luau,
// string.match devuelve las capturas sueltas y sin la coincidencia entera.
function parseIsoMs(value) {
    if (typeof value !== "string" || value === "") return null;
    var m = ISO_PATTERN.exec(value);
    if (!m) return null;

    var base = Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]),
                        Number(m[4]), Number(m[5]), Number(m[6])) / 1000;
    if (base !== base) return null;
    base += localUtcOffsetSeconds();

    // Offset explícito de la cadena: Z (0) o ±HH:MM. Un "+02:00" significa que
    // la hora leída va dos horas por delante de UTC, así que se resta.
    var off = ISO_OFFSET_PATTERN.exec(value);
    if (off) {
        var delta = Number(off[2]) * 3600 + Number(off[3]) * 60;
        base += off[1] === "+" ? -delta : delta;
    }

    return base * 1000;
}

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

// Las fechas se leen en hora LOCAL (getFullYear/getMonth/getDate) y se vuelven
// a componer en UTC (Date.UTC). La asimetría es la misma del original y no
// importa aquí porque las dos medianoches se transforman igual y solo se usa
// su diferencia; componer en UTC además hace que esa diferencia sea siempre
// un múltiplo exacto de 86400, también sobre un cambio de horario.
function startOfDaySec(sec) {
    var d = new Date(sec * 1000);
    return Date.UTC(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0) / 1000;
}

// ---------------------------------------------------------------------------
// Formato
// ---------------------------------------------------------------------------

// Cantidad desnuda: "45 min", "2 h 5 min", "1 d 5 h".
//
// Las unidades NO pasan por el catálogo a propósito: s/min/h/d se abrevian
// igual en las dos lenguas, y meterlas en él obligaría a plural y concordancia
// sin ganar nada. Lo que sí se traduce es el envoltorio ("en …", "hace …"),
// que es donde está la gramática.
function durationText(deltaMs, withSeconds) {
    if (withSeconds && deltaMs < 60000)
        return Math.floor(deltaMs / 1000) + " s";

    var minutes = Math.floor(deltaMs / 60000);
    if (minutes < 60) return minutes + " min";

    var hours = Math.floor(minutes / 60);
    var restMinutes = minutes % 60;
    if (hours < 24)
        return restMinutes > 0 ? hours + " h " + restMinutes + " min" : hours + " h";

    var days = Math.floor(hours / 24);
    var restHours = hours % 24;
    return restHours > 0 ? days + " d " + restHours + " h" : days + " d";
}

// Antigüedad de un instante PASADO, sin prefijo: "3 s", "12 min", "2 h 5 min".
//
// describeRelative no sirve para esto y usarla es un error silencioso: mira
// hacia adelante, y con un delta <= 0 devuelve el descriptor "reiniciando…".
// Como fetchedAt está siempre en el pasado, el pie del panel diría
// "reiniciando…" el 100 % de las veces. El texto envolvente ("hace …") lo pone
// el catálogo con la clave panel.updatedAgo, para que sea traducible.
function formatAge(pastMs, nowMs) {
    if (typeof pastMs !== "number") return "";

    // Un reloj que va hacia atrás (NTP, suspensión) no debe pintar negativos.
    return durationText(Math.max(0, nowMs - pastMs), true);
}

// ---------------------------------------------------------------------------
// Descriptores
// ---------------------------------------------------------------------------
//
// Un DESCRIPTOR, no una cadena: `{ key, params }` para lo traducible,
// `{ text }` para lo que no lo es, y `weekday` (un número 1-7) para el día de
// la semana, que i18n.render resuelve como la clave `weekday.<N>`. Este
// fichero NO importa i18n.js ni traduce nada: devuelve el descriptor y quien
// tiene catálogo delante (Daemon.qml, Widget.qml) lo renderiza.

function describeRelative(resetsAtMs, nowMs) {
    if (typeof resetsAtMs !== "number") return null;

    var delta = resetsAtMs - nowMs;
    if (delta <= 0) return { key: "state.resetting" };
    return { key: "time.in", params: { duration: durationText(delta, false) } };
}

// El día y el mes viajan SUELTOS, no como "20/8" ya montado: el orden es cosa
// de la lengua (en_US pone el mes delante) y solo el patrón de traducción puede
// decidirlo. Lo mismo con el día de la semana, que va como índice para que
// weekday.N lo nombre.
function describeAbsolute(resetsAtMs, nowMs) {
    if (typeof resetsAtMs !== "number") return null;

    var sec = Math.floor(resetsAtMs / 1000);
    var t = new Date(sec * 1000);
    var clock = pad2(t.getHours()) + ":" + pad2(t.getMinutes());

    var dayDiff = Math.round(
        (startOfDaySec(sec) - startOfDaySec(Math.floor(nowMs / 1000))) / 86400);

    if (dayDiff < 0) return null;
    if (dayDiff === 0) return { key: "reset.today", params: { clock: clock } };
    if (dayDiff === 1) return { key: "reset.tomorrow", params: { clock: clock } };
    // Las claves weekday.N son 1-based (1 = domingo), como el `wday` de
    // os.date en Luau; getDay() es 0-based, de ahí el +1.
    if (dayDiff < 7) {
        return { key: "reset.weekday", params: { clock: clock }, weekday: t.getDay() + 1 };
    }
    // getMonth() es 0-based y la fecha que se pinta no: +1.
    return {
        key: "reset.date",
        params: { clock: clock, day: t.getDate(), month: t.getMonth() + 1 }
    };
}

// ---------------------------------------------------------------------------
// Dinero
// ---------------------------------------------------------------------------

var CURRENCY_SYMBOLS = { USD: "$", EUR: "€" };

var MONEY_PATTERN = /^(-?\d+)\.(\d+)$/;

// Devuelve las piezas, no el importe montado: el separador decimal y el lado
// del símbolo cambian con la lengua ("30,00 $" frente a "$30.00"), así que los
// pone el catálogo (format.decimal y format.money). La parte entera y los
// céntimos salen ya partidos para que quien traduce no tenga que tocar el
// número. Con exponente 0 no hay céntimos y `cents` es null.
function describeMoney(amountMinor, exponent, currency) {
    // Un exponente fraccionario pasa las demás guardas y da un importe raro
    // (blindaje pedido por el ledger de la Task 5 de Caelestia): ISO 4217 es
    // siempre entero. El techo de 100 coincide además con el máximo que
    // acepta toFixed, que lanza RangeError por encima.
    var exp = (typeof exponent === "number" && exponent === exponent
               && exponent >= 0 && exponent <= 100 && exponent % 1 === 0)
        ? exponent : 2;

    var value = (typeof amountMinor === "number" ? amountMinor : 0) / Math.pow(10, exp);

    // typeof y no truthiness: en Lua la cadena vacía es truthy, así que el
    // original con currency = "" acaba devolviendo "" como símbolo. Con un
    // `currency || "USD"` en JS ese caso caería a "USD" y el port dejaría de
    // ser fiel; la comprobación explícita conserva la semántica.
    var symbol = typeof currency === "string" ? CURRENCY_SYMBOLS[currency] : null;
    if (symbol === undefined || symbol === null)
        symbol = typeof currency === "string" ? currency : "USD";

    var text = value.toFixed(exp);
    var m = MONEY_PATTERN.exec(text);
    // Con exponente 0 no hay punto que partir y el importe es entero.
    if (!m) return { whole: text, cents: null, symbol: symbol };
    return { whole: m[1], cents: m[2], symbol: symbol };
}

// ---------------------------------------------------------------------------
// Semántica de Lua que no se traduce sola
// ---------------------------------------------------------------------------

// En Lua SOLO `nil` y `false` son falsy: el 0 y la cadena vacía son
// verdaderos. `not not v` del original NO es `!!v` aquí — con `is_enabled: 0`
// el original diría `true` y `!!0` diría `false`. Este helper conserva la
// semántica exacta del `not not`.
function luaTruthy(v) {
    return v !== false && v !== null && v !== undefined;
}

// `math.round` de Luau redondea el 0.5 ALEJÁNDOSE del cero; `Math.round` de
// JavaScript lo redondea siempre hacia +∞ (Math.round(-0.5) es -0, y
// math.round(-0.5) es -1). Con porcentajes y créditos, que no son negativos,
// no hay diferencia observable — pero el port no depende de esa suposición.
function round(v) {
    return v < 0 ? -Math.round(-v) : Math.round(v);
}

// `type(x) == "table"` del original. En JS hay que descartar null a mano
// (typeof null es "object") y los arrays cuentan como tabla, igual que en Lua.
function isTable(v) {
    return v !== null && typeof v === "object";
}

// ---------------------------------------------------------------------------
// Severidad y etiquetas
// ---------------------------------------------------------------------------

// Una severidad que no conocemos se trata como la más grave: si Anthropic
// añade un estado nuevo, preferimos un falso rojo a un silencio.
var SEVERITY_RANK = { normal: 0, warning: 1, critical: 2 };

// El rango de "normal" es 0, que es FALSY en JS: un `rank || 2` convertiría
// todo lo normal en crítico. La comprobación es por tipo, y de paso descarta
// lo que herede el objeto ("constructor", "toString"…), que en Lua no existe
// porque la tabla no tiene metatabla.
function severityRank(severity) {
    var rank = typeof severity === "string" ? SEVERITY_RANK[severity] : undefined;
    return typeof rank === "number" ? rank : 2;
}

// Un DESCRIPTOR, no una cadena (ver la sección de descriptores): `{ key,
// params }` para lo traducible y `{ text }` para lo que no lo es.
function labelDescriptor(kind, scopeName) {
    if (kind === "session") return { key: "limit.session" };
    if (kind === "weekly_all") return { key: "limit.weeklyAll" };
    if (kind === "weekly_scoped") {
        // `if scopeName then` en Lua acepta la cadena vacía; un `if (scopeName)`
        // aquí la rechazaría y el port dejaría de ser equivalente.
        return typeof scopeName === "string"
            ? { key: "limit.weeklyScoped", params: { model: scopeName } }
            : { key: "limit.weeklyScopedGeneric" };
    }
    // Una clase que no conocemos se pinta cruda antes que traducida a medias: si
    // Anthropic añade un `kind`, el usuario ve su nombre y no una clave rota.
    return { text: kind };
}

var PRIMARY_KINDS = ["session", "weekly_all"];

function isPrimaryKind(kind) {
    for (var i = 0; i < PRIMARY_KINDS.length; i++) {
        if (PRIMARY_KINDS[i] === kind) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Normalización del payload
// ---------------------------------------------------------------------------

function scopeNameOf(limit) {
    if (!isTable(limit)) return null;
    var scope = limit.scope;
    if (!isTable(scope)) return null;
    var model = scope.model;
    if (!isTable(model)) return null;
    var name = model.display_name;
    return (typeof name === "string" && name !== "") ? name : null;
}

// Misma trampa que en labelDescriptor: la cadena vacía es un scope válido para
// el original y produce la clave "kind:".
function limitKey(kind, scopeName) {
    return typeof scopeName === "string" ? kind + ":" + scopeName : kind;
}

// `spend` es la fuente preferida: trae importes en unidades menores y
// exponente explícito. `extra_usage` da los créditos en decimal y hay que
// convertirlos.
function normalizeExtraUsage(payload) {
    var extra = payload.extra_usage;
    var spend = payload.spend;
    if (!isTable(extra) && !isTable(spend)) return null;

    if (isTable(spend) && isTable(spend.used) && isTable(spend.limit)) {
        return {
            enabled: luaTruthy(spend.enabled),
            everEnabled: isTable(extra) ? luaTruthy(extra.credits_ever_enabled) : true,
            usedMinor: num(spend.used.amount_minor, 0),
            limitMinor: num(spend.limit.amount_minor, 0),
            currency: typeof spend.used.currency === "string"
                ? spend.used.currency : "USD",
            exponent: num(spend.used.exponent, 2),
            percent: round(num(spend.percent, 0)),
            // Una clave ausente es `undefined`; la ausencia de este módulo es
            // null (ver la cabecera).
            disabledReason: spend.disabled_reason === undefined
                ? null : spend.disabled_reason
        };
    }

    if (!isTable(extra)) return null;

    var exponent = num(extra.decimal_places, 2);
    var factor = Math.pow(10, exponent);
    return {
        enabled: luaTruthy(extra.is_enabled),
        everEnabled: luaTruthy(extra.credits_ever_enabled),
        usedMinor: round(num(extra.used_credits, 0) * factor),
        limitMinor: round(num(extra.monthly_limit, 0)),
        currency: typeof extra.currency === "string" ? extra.currency : "USD",
        exponent: exponent,
        percent: round(num(extra.utilization, 0)),
        disabledReason: extra.disabled_reason === undefined
            ? null : extra.disabled_reason
    };
}

function normalizeUsage(payload, source, fetchedAtMs) {
    var result = {
        limits: [],
        source: source,
        fetchedAt: fetchedAtMs === undefined ? null : fetchedAtMs,
        // Presente desde el principio y con valor null: quien reciba la forma
        // vacía tiene que poder comparar `extraUsage === null` sin distinguir
        // entre "no hay" y "la propiedad no existe".
        extraUsage: null
    };
    if (!isTable(payload)) return result;

    var raw = payload.limits;
    // `#raw > 0` del original. Un objeto que no sea lista da longitud 0 en Luau
    // y cae al legado igual que aquí.
    if (Array.isArray(raw) && raw.length > 0) {
        for (var i = 0; i < raw.length; i++) {
            var item = raw[i];
            var scopeName = scopeNameOf(item);
            result.limits.push({
                key: limitKey(item.kind, scopeName),
                label: labelDescriptor(item.kind, scopeName),
                percent: round(num(item.percent, 0)),
                severity: typeof item.severity === "string" ? item.severity : "normal",
                resetsAt: parseIsoMs(item.resets_at),
                scope: scopeName,
                primary: isPrimaryKind(item.kind)
            });
        }
    } else {
        // Sin limits[], los objetos sueltos son la única fuente. No traen
        // severidad, así que el estado de aviso lo decide el umbral local.
        var legacy = [
            { kind: "session", data: payload.five_hour },
            { kind: "weekly_all", data: payload.seven_day }
        ];
        for (var j = 0; j < legacy.length; j++) {
            var entry = legacy[j];
            if (!isTable(entry.data)) continue;
            result.limits.push({
                key: entry.kind,
                label: labelDescriptor(entry.kind, null),
                percent: round(num(entry.data.utilization, 0)),
                severity: "normal",
                resetsAt: parseIsoMs(entry.data.resets_at),
                scope: null,
                primary: true
            });
        }
    }

    result.extraUsage = normalizeExtraUsage(payload);
    return result;
}

// ---------------------------------------------------------------------------
// Aviso y orden
// ---------------------------------------------------------------------------

// Definición única de "estar cerca del límite". La usan el color del widget,
// el glifo indicador, la cadencia de alerta y la notificación.
function isWarning(limit, threshold) {
    if (!isTable(limit)) return false;
    return limit.severity !== "normal" || limit.percent >= threshold;
}

// COMPARADOR de Array.prototype.sort: negativo si `a` va ANTES que `b`, cero
// si empatan, positivo si va después.
//
// El original en Luau devuelve un PREDICADO (`true` = "a va antes que b"),
// porque eso es lo que espera table.sort. Traducir el cuerpo literalmente
// —devolviendo booleanos— daría un orden mal: `true` se coerce a 1, o sea "a
// va DESPUÉS", justo lo contrario. Lo que se traduce es la intención.
//
// El tercer criterio (key) no está en el original de Caelestia y se conserva
// aquí aunque Array.prototype.sort sea estable desde ES2019. La razón no es de
// Luau: un comparador sin desempate devuelve el mismo sentido para (a,b) y
// (b,a), que es exactamente lo que table.sort rechaza con "invalid order
// function for sorting". Un orden total, determinista e irreflexivo es
// correcto por sí mismo, y además hace que el panel no dependa de la
// estabilidad del motor que le toque.
function byCriticality(a, b) {
    var ra = severityRank(a.severity);
    var rb = severityRank(b.severity);
    if (ra !== rb) return rb - ra;                       // más grave primero
    if (a.percent !== b.percent) return b.percent - a.percent; // más alto primero
    if (a.key < b.key) return -1;
    if (a.key > b.key) return 1;
    return 0;                                            // irreflexivo
}

// El widget solo puede codificar dos glifos, así que solo compite entre los
// límites primarios. Los sublímites por modelo se señalan con el glifo
// indicador (ver hasHiddenWarning).
// La ventana de 5 h manda SIEMPRE, aunque la semanal vaya más alta y más grave.
// Antes ganaba la de mayor porcentaje, y en la práctica eso era casi siempre la
// semanal: la de sesión —la única que se recupera esperando un rato— solo
// asomaba por la barra cuando ya iba por delante, que es justo cuando ya no
// hacía falta mirarla.
//
// Esto carga de trabajo al punto de aviso: con la sesión fija en la barra, una
// semanal al 95 % ya no puede ser la píldora, y hasHiddenWarning es la ÚNICA
// señal que queda de ella sin abrir el panel. No quitarlo.
//
// Si la API no manda ventana de sesión, se cae al primario más grave, que es lo
// que hacía antes para todos.
function pickPrimary(limits) {
    if (!isTable(limits)) return null;
    var primaries = [];
    var i;
    for (i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && limits[i].primary) primaries.push(limits[i]);
    }
    if (primaries.length === 0) return null;

    for (i = 0; i < primaries.length; i++) {
        if (primaries[i].key === "session") return primaries[i];
    }

    primaries.sort(byCriticality); // copia local: no muta la entrada
    return primaries[0];
}

function sortForPanel(limits, primaryKey) {
    if (!isTable(limits)) return [];
    var rest = [];
    for (var i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && limits[i].key !== primaryKey) rest.push(limits[i]);
    }
    rest.sort(byCriticality);
    return rest;
}

function hasHiddenWarning(limits, primaryKey, threshold) {
    if (!isTable(limits)) return false;
    for (var i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && limits[i].key !== primaryKey
            && isWarning(limits[i], threshold)) {
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Cadencia de sondeo
// ---------------------------------------------------------------------------

// Techo del backoff (dobles por fallo) y de Retry-After, NO de la base que
// elige el usuario: idleInterval/alertInterval pueden superarlo (spec §10). El
// propio backoff nunca sondea por debajo de la base.
var MAX_INTERVAL = 1800;
var MIN_INTERVAL = 15;
var DEFAULT_IDLE_INTERVAL = 300;
var DEFAULT_ALERT_INTERVAL = 60;

// Solo se aplica a un valor YA validado (ver usableInterval y la guarda de
// retryAfter en nextInterval): `clampInterval(NaN)` daría NaN y el
// temporizador de QML dejaría de disparar, y `clampInterval(0)` daría el
// suelo, que es el sondeo más agresivo posible.
function clampInterval(seconds) {
    return Math.max(MIN_INTERVAL, Math.min(MAX_INTERVAL, seconds));
}

// Un valor solo es utilizable como intervalo si es un number finito y
// estrictamente positivo. Cualquier otra cosa (ausente, NaN, cadenas, 0,
// negativos) es entrada basura y cae al default del spec, no al suelo: caer al
// suelo sería el sondeo más agresivo posible por culpa de un ajuste roto.
function usableInterval(value, fallback) {
    if (typeof value !== "number") return fallback;
    if (value !== value) return fallback;                // NaN
    if (value === Infinity || value === -Infinity) return fallback;
    return value > 0 ? value : fallback;
}

function nextInterval(state) {
    // Retry-After manda: si el servidor pide esperar, se espera. Un
    // Retry-After no numérico, no finito o no positivo no cuenta como tal y se
    // sigue el camino normal (reposo/alerta + backoff) en vez de tratarlo como
    // 0. Esta rama no está en logic.luau: vuelve con parseRetryAfter.
    if (typeof state.retryAfter === "number" && state.retryAfter === state.retryAfter
        && state.retryAfter !== Infinity && state.retryAfter > 0) {
        return clampInterval(state.retryAfter);
    }

    // `if state.warning then` del original. En Lua el 0 y la cadena vacía son
    // TRUTHY, así que un `state.warning ? …` aquí no sería el mismo programa;
    // luaTruthy conserva la semántica exacta (ver su comentario).
    var base = luaTruthy(state.warning)
        ? usableInterval(state.alertInterval, DEFAULT_ALERT_INTERVAL)
        : usableInterval(state.idleInterval, DEFAULT_IDLE_INTERVAL);

    var failures = typeof state.failures === "number" ? state.failures : 0;

    if (failures > 0) {
        var doubled = base * Math.pow(2, failures);
        // Dobla hasta el techo, pero nunca por debajo de la base: si la base ya
        // supera el techo (p. ej. idleInterval 3600), un fallo no debe hacer el
        // sondeo MÁS frecuente que en condiciones normales.
        return Math.max(MIN_INTERVAL, Math.max(base, Math.min(doubled, MAX_INTERVAL)));
    }

    // Sin fallos, la base del usuario se respeta íntegra; solo el suelo puede
    // recortarla, nunca el techo del backoff.
    return Math.max(MIN_INTERVAL, base);
}

var DELTA_SECONDS_PATTERN = /^[0-9]+$/;

// RFC 7231 §7.1.3 permite dos formas para Retry-After: delta-seconds ("120") y
// fecha HTTP ("Wed, 21 Oct 2015 07:28:00 GMT"). `parseInt(header, 10) || 0`
// solo entiende la primera: ante la forma de fecha da NaN y el `|| 0` lo
// convierte en "reintenta ya", justo lo contrario de lo que pide un 429. Aquí
// se prueban las dos; si ninguna parsea, o el resultado es negativo o no
// finito, se devuelve 0 para que tome el mando el backoff propio del plugin
// (el que corre por `failures`, ver nextInterval) en vez de un reintento
// inmediato.
//
// `now` es un epoch en MILISEGUNDOS, no un Date: es el contrato de fechas de
// todo el módulo. En Caelestia era un Date, y esa es la única adaptación.
//
// La forma de fecha se resuelve con Date.parse y no con una expresión regular
// propia. Es la excepción a la regla de parseIsoMs (que evita el parseo de
// cadenas de Date por ser dependiente del motor) y se admite porque
// IMF-fixdate es una gramática fija que V4 y V8 reconocen igual, y porque un
// motor que NO la reconociera devolvería NaN y con él un 0: el plugin se
// quedaría con su propio backoff, que es exactamente el modo degradado
// correcto.
function parseRetryAfter(header, nowMs) {
    if (typeof header !== "string" || header.length === 0) return 0;
    if (validMs(nowMs) === null) return 0;

    var trimmed = header.trim();

    // Delta-seconds: RFC 7231 lo define como 1*DIGIT, sin signo ni decimales.
    if (DELTA_SECONDS_PATTERN.test(trimmed)) {
        var seconds = parseInt(trimmed, 10);
        return (seconds === seconds && seconds !== Infinity && seconds >= 0) ? seconds : 0;
    }

    // Forma de fecha HTTP: la diferencia con `now` son los segundos a esperar.
    var whenMs = Date.parse(trimmed);
    if (whenMs !== whenMs || whenMs === Infinity || whenMs === -Infinity) return 0;

    var diffSeconds = round((whenMs - nowMs) / 1000);
    return diffSeconds > 0 ? diffSeconds : 0;
}

// ---------------------------------------------------------------------------
// Credenciales y caché
// ---------------------------------------------------------------------------

// Margen para no lanzar una petición con un token que caduca a mitad de vuelo.
var TOKEN_MARGIN_MS = 60000;

function nonEmptyString(value) {
    return (typeof value === "string" && value !== "") ? value : null;
}

// El decode que en logic.luau hacía el servicio (allí parseCredentials recibía
// la tabla ya decodificada, de ahí su caso "nil = decode fallido"). Devolver
// null en vez de lanzar es lo que convierte un fichero corrupto en ese caso.
//
// Solo acepta cadenas: `JSON.parse(true)` devolvería `true` sin lanzar, y
// dejar pasar eso contradiría el fallar-cerrado del resto del módulo.
function safeParse(text) {
    if (typeof text !== "string" || text === "") return null;
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

// El token NO viaja en la forma inválida ni en la caducada: `token` es null,
// no la cadena. Falla CERRADO — los tres hallazgos de seguridad de la Task 7
// de Caelestia.
function parseCredentials(doc, nowMs) {
    var invalid = { status: "invalid", token: null, expiresAt: null };

    if (!isTable(doc)) return invalid;
    var oauth = doc.claudeAiOauth;
    if (!isTable(oauth)) return invalid;

    var token = nonEmptyString(oauth.accessToken);
    var expiresAtMs = validMs(oauth.expiresAt);
    if (token === null || expiresAtMs === null) return invalid;

    if (nowMs > expiresAtMs - TOKEN_MARGIN_MS)
        return { status: "expired", token: null, expiresAt: expiresAtMs };

    return { status: "ok", token: token, expiresAt: expiresAtMs };
}

function extractCache(doc) {
    if (!isTable(doc)) return null;
    var cached = doc.cachedUsageUtilization;
    if (!isTable(cached)) return null;

    var fetchedAt = validMs(cached.fetchedAtMs);
    if (fetchedAt === null || !isTable(cached.utilization)) return null;

    return { payload: cached.utilization, fetchedAt: fetchedAt };
}

// ---------------------------------------------------------------------------
// Codex: credenciales y normalización
// ---------------------------------------------------------------------------

// Codex CLI guarda la sesión ChatGPT en ~/.codex/auth.json. La forma de API key
// no trae tokens.access_token y, por diseño, no se intenta convertirla en una
// consulta de uso: este endpoint pertenece a la sesión ChatGPT, no al consumo
// de la API de OpenAI.
function parseCodexCredentials(doc) {
    var invalid = { status: "invalid", token: null, accountId: null };
    if (!isTable(doc)) return invalid;
    if (!isTable(doc.tokens)) return invalid;

    var token = nonEmptyString(doc.tokens.access_token);
    if (token === null) return invalid;

    return {
        status: "ok",
        token: token,
        accountId: nonEmptyString(doc.tokens.account_id)
    };
}

// El backend de Codex entrega los resets como epoch en segundos, a diferencia
// del contrato interno del plugin. Toda conversión sigue pasando por
// toMilliseconds; no se multiplica a mano en otra función.
function codexResetMs(value) {
    var seconds = num(value, null);
    if (seconds === null || seconds <= 0 || seconds === Infinity)
        return null;
    return validMs(toMilliseconds(seconds));
}

function codexWindowDuration(value) {
    var seconds = num(value, null);
    if (seconds === null || seconds <= 0 || seconds === Infinity)
        return null;
    return durationText(toMilliseconds(seconds), false);
}

function codexLabelDescriptor(name, windowSeconds) {
    var duration = codexWindowDuration(windowSeconds);
    var named = nonEmptyString(name);
    if (duration === null)
        return named === null
            ? { key: "limit.codex" }
            : { key: "limit.codexNamed", params: { name: named } };
    return named === null
        ? { key: "limit.codexWindow", params: { duration: duration } }
        : { key: "limit.codexNamedWindow", params: { name: named, duration: duration } };
}

function codexPercent(value) {
    var percent = num(value, null);
    if (percent === null) return null;
    return Math.max(0, Math.min(100, round(percent)));
}

function appendCodexWindow(limits, key, name, window, role, reached) {
    if (!isTable(window)) return;
    var percent = codexPercent(window.used_percent);
    if (percent === null) return;

    limits.push({
        key: key,
        label: codexLabelDescriptor(name, window.limit_window_seconds),
        percent: percent,
        severity: reached ? "critical" : "normal",
        resetsAt: codexResetMs(window.reset_at),
        scope: nonEmptyString(name),
        primary: role === "primary",
        codexPrimary: role === "primary",
        codexSecondary: role === "secondary",
        glyph: "code"
    });
}

function codexLimitReached(rateLimit) {
    if (!isTable(rateLimit)) return false;
    return rateLimit.limit_reached === true || rateLimit.allowed === false;
}

function normalizeCodexCredits(value) {
    if (!isTable(value)) return null;
    return {
        hasCredits: value.has_credits === true,
        unlimited: value.unlimited === true,
        balance: nonEmptyString(value.balance)
    };
}

function normalizeCodexUsage(payload, source, fetchedAtMs) {
    var result = {
        limits: [],
        source: source,
        fetchedAt: fetchedAtMs === undefined ? null : fetchedAtMs,
        planType: null,
        credits: null
    };
    if (!isTable(payload)) return result;

    var rate = payload.rate_limit;
    if (isTable(rate)) {
        appendCodexWindow(result.limits, "codex:primary", null,
                          rate.primary_window, "primary", codexLimitReached(rate));
        appendCodexWindow(result.limits, "codex:secondary", null,
                          rate.secondary_window, "secondary", codexLimitReached(rate));
    }

    var additional = payload.additional_rate_limits;
    if (Array.isArray(additional)) {
        for (var i = 0; i < additional.length; i++) {
            var item = additional[i];
            if (!isTable(item) || !isTable(item.rate_limit)) continue;
            var name = nonEmptyString(item.limit_name);
            if (name === null) name = nonEmptyString(item.metered_feature);
            var prefix = "codex:additional:" + i;
            var reached = codexLimitReached(item.rate_limit);
            appendCodexWindow(result.limits, prefix + ":primary", name,
                              item.rate_limit.primary_window, "additional", reached);
            appendCodexWindow(result.limits, prefix + ":secondary", name,
                              item.rate_limit.secondary_window, "additional", reached);
        }
    }

    result.planType = nonEmptyString(payload.plan_type);
    result.credits = normalizeCodexCredits(payload.credits);
    return result;
}

function pickCodexPrimary(limits) {
    if (!isTable(limits)) return null;
    for (var i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && limits[i].codexPrimary) return limits[i];
    }
    return null;
}

function pickCodexSecondary(limits) {
    if (!isTable(limits)) return null;
    for (var i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && limits[i].codexSecondary) return limits[i];
    }
    return null;
}

function sortCodexForPanel(limits, primaryKey, secondaryKey) {
    if (!isTable(limits)) return [];
    var rest = [];
    for (var i = 0; i < limits.length; i++) {
        if (!isTable(limits[i])) continue;
        if (limits[i].key === primaryKey || limits[i].key === secondaryKey) continue;
        rest.push(limits[i]);
    }
    rest.sort(byCriticality);
    return rest;
}

function hasCodexHiddenWarning(limits, primaryKey, secondaryKey, threshold) {
    if (!isTable(limits)) return false;
    for (var i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && limits[i].key !== primaryKey
            && limits[i].key !== secondaryKey && isWarning(limits[i], threshold))
            return true;
    }
    return false;
}

function hasCodexWarning(limits, threshold) {
    if (!isTable(limits)) return false;
    for (var i = 0; i < limits.length; i++) {
        if (isTable(limits[i]) && isWarning(limits[i], threshold)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Notificaciones
// ---------------------------------------------------------------------------

// Umbral de aviso por defecto del spec. Un threshold no numérico no debe
// interpretarse como "avisar de todo" (equivalente a caer a 0): cae aquí.
var DEFAULT_WARN_THRESHOLD = 90;

// Antirrebote: una notificación por ventana. La identidad de la ventana es su
// resetsAt, así que reiniciar el shell no vuelve a avisar, y cuando la ventana
// se renueva el aviso se rearma solo.
//
// Esto es lógica PURA y vive solo aquí: no se replica en Daemon.qml ni se
// simplifica. El estado entra por `prevState` y sale por `nextState`.
function notificationsFor(limits, threshold, prevState, nowMs) {
    var notifications = [];
    var nextState = {};

    if (!isTable(limits)) return { notifications: notifications, nextState: nextState };

    // `threshold == threshold` descarta NaN y nada más: un 0 explícito es un
    // umbral válido y NO debe caer al default (un `threshold || DEFAULT` sí lo
    // haría).
    var effectiveThreshold = (typeof threshold === "number" && threshold === threshold)
        ? threshold : DEFAULT_WARN_THRESHOLD;
    var previous = isTable(prevState) ? prevState : {};
    var effectiveNow = validMs(nowMs);

    // El original recorre con `for _, limit in limits`, la iteración
    // generalizada de una tabla-lista. Aquí el contrato es un array y el
    // recorrido es por índice desde 0 (en Luau empieza en 1).
    for (var i = 0; i < limits.length; i++) {
        var limit = limits[i];
        if (!isTable(limit)) continue;

        var resetsAt = validMs(limit.resetsAt);
        // La marca de ventana es texto para que la comparación no dependa de
        // la aritmética en coma flotante, igual que el tostring del original.
        var stamp = resetsAt === null ? null : String(resetsAt);
        var before = previous[limit.key];
        var sameWindow = isTable(before) && before.resetsAt === stamp;

        if (!isWarning(limit, effectiveThreshold)) {
            // Se conserva el registro de la ventana en curso: si vuelve a
            // subir por encima del umbral, no se notifica dos veces.
            nextState[limit.key] = sameWindow ? before
                : { resetsAt: stamp, notified: false };
            continue;
        }

        if (sameWindow && before.notified) {
            nextState[limit.key] = before;
            continue;
        }

        // Sin resetsAt válido o sin un `now` válido no hay forma fiable de
        // calcular la cláusula "se reinicia …"; se omite entera en vez de
        // dejar un texto colgando. Ausencia = null, nunca propiedad ausente.
        var reset = null;
        if (resetsAt !== null && effectiveNow !== null)
            reset = describeAbsolute(resetsAt, effectiveNow);

        // Las piezas, no el cuerpo montado: quien tiene el catálogo delante es
        // el servicio.
        notifications.push({
            key: limit.key,
            percent: limit.percent,
            label: limit.label,
            reset: reset
        });
        nextState[limit.key] = { resetsAt: stamp, notified: true };
    }

    return { notifications: notifications, nextState: nextState };
}

var publicApi = {
    num: num,
    validMs: validMs,
    toMilliseconds: toMilliseconds,
    localUtcOffsetSeconds: localUtcOffsetSeconds,
    parseIsoMs: parseIsoMs,
    startOfDaySec: startOfDaySec,
    durationText: durationText,
    formatAge: formatAge,
    describeRelative: describeRelative,
    describeAbsolute: describeAbsolute,
    describeMoney: describeMoney,
    CURRENCY_SYMBOLS: CURRENCY_SYMBOLS,

    // Varias de estas son `local` en logic.luau (scopeNameOf, limitKey,
    // normalizeExtraUsage, isPrimaryKind). Se exportan igualmente porque un
    // `import "logic.js" as Logic` en QML expone TODAS las declaraciones de
    // nivel superior del script: dejarlas fuera de publicApi solo haría que
    // node viese menos superficie que QML, y la suite dejaría de cubrir lo que
    // el host puede llamar. Mismo criterio que ya se aplicó en la tarea 3 con
    // durationText y startOfDaySec.
    SEVERITY_RANK: SEVERITY_RANK,
    severityRank: severityRank,
    labelDescriptor: labelDescriptor,
    PRIMARY_KINDS: PRIMARY_KINDS,
    isPrimaryKind: isPrimaryKind,
    scopeNameOf: scopeNameOf,
    limitKey: limitKey,
    normalizeExtraUsage: normalizeExtraUsage,
    normalizeUsage: normalizeUsage,
    isWarning: isWarning,
    byCriticality: byCriticality,
    pickPrimary: pickPrimary,
    sortForPanel: sortForPanel,
    hasHiddenWarning: hasHiddenWarning,

    // Constantes de cadencia y umbral. Exportadas a propósito: el panel de
    // ajustes se ata a ellas en vez de repetir los números.
    MAX_INTERVAL: MAX_INTERVAL,
    MIN_INTERVAL: MIN_INTERVAL,
    DEFAULT_IDLE_INTERVAL: DEFAULT_IDLE_INTERVAL,
    DEFAULT_ALERT_INTERVAL: DEFAULT_ALERT_INTERVAL,
    DEFAULT_WARN_THRESHOLD: DEFAULT_WARN_THRESHOLD,
    TOKEN_MARGIN_MS: TOKEN_MARGIN_MS,

    clampInterval: clampInterval,
    usableInterval: usableInterval,
    nextInterval: nextInterval,
    parseRetryAfter: parseRetryAfter,
    nonEmptyString: nonEmptyString,
    safeParse: safeParse,
    parseCredentials: parseCredentials,
    extractCache: extractCache,
    parseCodexCredentials: parseCodexCredentials,
    codexResetMs: codexResetMs,
    codexWindowDuration: codexWindowDuration,
    codexLabelDescriptor: codexLabelDescriptor,
    normalizeCodexCredits: normalizeCodexCredits,
    normalizeCodexUsage: normalizeCodexUsage,
    pickCodexPrimary: pickCodexPrimary,
    pickCodexSecondary: pickCodexSecondary,
    sortCodexForPanel: sortCodexForPanel,
    hasCodexHiddenWarning: hasCodexHiddenWarning,
    hasCodexWarning: hasCodexWarning,
    notificationsFor: notificationsFor
};

if (typeof module !== "undefined")
    module.exports = publicApi;
