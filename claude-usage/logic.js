// Lógica pura del plugin claude-usage.
//
// Este fichero se carga desde dos entornos: el motor JavaScript de QML
// (via `import "logic.js" as Logic`) y node (en las pruebas). Por eso:
//   - Nada de QML aquí dentro. Ni un import, ni un tipo, ni Qt.*
//   - ES5 estricto: sin ?., sin ??, sin arrow functions, sin template literals.
//   - El guardián de module.exports al final sirve a los dos.
//
// Nombrado: TODO lo público se declara como `var`/`function` de nivel
// superior (nunca colgado de un objeto contenedor interno). Un fichero
// importado en QML con `import "logic.js" as Logic` NO expone
// `module.exports` — expone las declaraciones de nivel superior del propio
// script bajo el nombre con el que se declararon. Si aquí hubiera un
// `var Logic = {}` y `Logic.foo = ...`, cualquier QML que importe este
// fichero "as Logic" (la convención de todo este proyecto) tendría que
// escribir `Logic.Logic.foo(...)`: el alias de QML y el nombre interno
// coinciden y anidan uno dentro del otro. Comprobado en vivo con `qs`
// (Task 10): con esa forma, `Object.keys(Logic)` desde QML solo devolvía
// las funciones auxiliares privadas más una propiedad `Logic` — todo lo
// público quedaba en `Logic.Logic.*`, invisible para cualquier binding que
// escribiera `Logic.parseCredentials(...)`. Declarar cada función y
// constante pública directamente en el ámbito superior del fichero evita el
// problema para cualquier alias que elija quien importe.

var SEVERITY_RANK = { normal: 0, warning: 1, critical: 2 };

// Una severidad que no conocemos se trata como la más grave: si Anthropic
// añade un estado nuevo, preferimos un falso rojo a un silencio.
function severityRank(severity) {
    var rank = SEVERITY_RANK[severity];
    return rank === undefined ? 2 : rank;
}

function limitLabel(kind, scopeName) {
    if (kind === "session")
        return "Sesión 5 h";
    if (kind === "weekly_all")
        return "Semana";
    if (kind === "weekly_scoped")
        return scopeName ? scopeName + " · semanal" : "Sublímite semanal";
    return kind;
}

var PRIMARY_KINDS = ["session", "weekly_all"];

function parseDate(value) {
    if (!value)
        return null;
    var d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
}

function scopeNameOf(limit) {
    if (!limit || !limit.scope || !limit.scope.model)
        return null;
    return limit.scope.model.display_name || null;
}

function limitKey(kind, scopeName) {
    return scopeName ? kind + ":" + scopeName : kind;
}

function normalizeExtraUsage(payload) {
    var extra = payload.extra_usage;
    var spend = payload.spend;

    if (!extra && !spend)
        return null;

    // `spend` es la fuente preferida: trae importes en unidades menores y
    // exponente explícito. `extra_usage` da los créditos en decimal y hay
    // que convertirlos.
    if (spend && spend.used && spend.limit) {
        return {
            enabled: !!spend.enabled,
            everEnabled: extra ? !!extra.credits_ever_enabled : true,
            usedMinor: spend.used.amount_minor || 0,
            limitMinor: spend.limit.amount_minor || 0,
            currency: spend.used.currency || "USD",
            exponent: spend.used.exponent === undefined ? 2 : spend.used.exponent,
            percent: Math.round(spend.percent || 0),
            disabledReason: spend.disabled_reason || null
        };
    }

    if (!extra)
        return null;

    var exponent = extra.decimal_places === undefined ? 2 : extra.decimal_places;
    var factor = Math.pow(10, exponent);
    return {
        enabled: !!extra.is_enabled,
        everEnabled: !!extra.credits_ever_enabled,
        usedMinor: Math.round((extra.used_credits || 0) * factor),
        limitMinor: Math.round(extra.monthly_limit || 0),
        currency: extra.currency || "USD",
        exponent: exponent,
        percent: Math.round(extra.utilization || 0),
        disabledReason: extra.disabled_reason || null
    };
}

function normalizeUsage(payload, source, fetchedAt) {
    var result = { limits: [], extraUsage: null, source: source, fetchedAt: fetchedAt };
    if (!payload)
        return result;

    var raw = payload.limits;
    if (raw && raw.length) {
        for (var i = 0; i < raw.length; i++) {
            var item = raw[i];
            var scopeName = scopeNameOf(item);
            result.limits.push({
                key: limitKey(item.kind, scopeName),
                label: limitLabel(item.kind, scopeName),
                percent: Math.round(item.percent || 0),
                severity: item.severity || "normal",
                resetsAt: parseDate(item.resets_at),
                scope: scopeName,
                primary: PRIMARY_KINDS.indexOf(item.kind) !== -1
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
            if (!entry.data)
                continue;
            result.limits.push({
                key: entry.kind,
                label: limitLabel(entry.kind, null),
                percent: Math.round(entry.data.utilization || 0),
                severity: "normal",
                resetsAt: parseDate(entry.data.resets_at),
                scope: null,
                primary: true
            });
        }
    }

    result.extraUsage = normalizeExtraUsage(payload);

    return result;
}

// Definición única de "estar cerca del límite". La usan el color de la
// barra, el punto indicador, la cadencia de alerta y la notificación.
function isWarning(limit, threshold) {
    if (!limit)
        return false;
    return limit.severity !== "normal" || limit.percent >= threshold;
}

function byCriticality(a, b) {
    var rankDiff = severityRank(b.severity) - severityRank(a.severity);
    if (rankDiff !== 0)
        return rankDiff;
    return b.percent - a.percent;
}

// El anillo de la barra solo puede codificar dos formas, así que solo
// compite entre los límites primarios. Los sublímites por modelo se
// señalan con el punto indicador (ver hasHiddenWarning).
function pickPrimary(limits) {
    var primaries = [];
    for (var i = 0; i < limits.length; i++) {
        if (limits[i].primary)
            primaries.push(limits[i]);
    }
    if (!primaries.length)
        return null;
    primaries.sort(byCriticality);
    return primaries[0];
}

function sortForPopout(limits, primaryKey) {
    var rest = [];
    for (var i = 0; i < limits.length; i++) {
        if (limits[i].key !== primaryKey)
            rest.push(limits[i]);
    }
    rest.sort(byCriticality);
    return rest;
}

function hasHiddenWarning(limits, primaryKey, threshold) {
    for (var i = 0; i < limits.length; i++) {
        if (limits[i].key !== primaryKey && isWarning(limits[i], threshold))
            return true;
    }
    return false;
}

var WEEKDAYS = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];
var CURRENCY_SYMBOLS = { USD: "$", EUR: "€" };

function pad2(n) {
    return n < 10 ? "0" + n : "" + n;
}

function startOfDay(d) {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

function formatRelative(resetsAt, now) {
    if (!resetsAt)
        return "";

    var ms = resetsAt.getTime() - now.getTime();
    if (ms <= 0)
        return "reiniciando…";

    var minutes = Math.floor(ms / 60000);
    if (minutes < 60)
        return "en " + minutes + " min";

    var hours = Math.floor(minutes / 60);
    var restMinutes = minutes % 60;
    if (hours < 24)
        return restMinutes > 0 ? "en " + hours + " h " + restMinutes + " min" : "en " + hours + " h";

    var days = Math.floor(hours / 24);
    var restHours = hours % 24;
    return restHours > 0 ? "en " + days + " d " + restHours + " h" : "en " + days + " d";
}

function formatAbsolute(resetsAt, now) {
    if (!resetsAt)
        return "";

    var clock = "a las " + pad2(resetsAt.getHours()) + ":" + pad2(resetsAt.getMinutes());
    var dayDiff = Math.round((startOfDay(resetsAt) - startOfDay(now)) / 86400000);

    if (dayDiff < 0)
        return "";
    if (dayDiff === 0)
        return clock;
    if (dayDiff === 1)
        return "mañana " + clock;
    if (dayDiff < 7)
        return "el " + WEEKDAYS[resetsAt.getDay()] + " " + clock;
    return "el " + resetsAt.getDate() + "/" + (resetsAt.getMonth() + 1) + " " + clock;
}

function formatMoney(amountMinor, exponent, currency) {
    var exp = (typeof exponent === "number" && isFinite(exponent) && exponent >= 0 && exponent <= 100) ? exponent : 2;
    var value = (amountMinor || 0) / Math.pow(10, exp);
    var symbol = CURRENCY_SYMBOLS[currency] || currency;
    return value.toFixed(exp).replace(".", ",") + " " + symbol;
}

// Techo del backoff (dobles por fallo) y de Retry-After, no de la base que
// elige el usuario: idleInterval/alertInterval pueden superarlo (spec §8).
// El propio backoff nunca sondea por debajo de la base (ver nextInterval).
var MAX_INTERVAL = 1800;
var MIN_INTERVAL = 15;

// Fallbacks de nextInterval cuando idleInterval/alertInterval no son
// utilizables. Spec §6.
var DEFAULT_IDLE_INTERVAL = 300;
var DEFAULT_ALERT_INTERVAL = 60;

function clampInterval(seconds) {
    return Math.max(MIN_INTERVAL, Math.min(MAX_INTERVAL, seconds));
}

// Un valor solo es utilizable como intervalo si es un number finito y
// estrictamente positivo. Cualquier otra cosa (null, undefined, NaN,
// cadenas, 0, negativos) es entrada basura: no debe colarse en el clamp,
// porque `clampInterval(NaN)` da NaN (el temporizador de QML deja de
// disparar) y `clampInterval(0 o negativo)` da el suelo (15 s, el sondeo
// más agresivo posible). Ante entrada basura caemos al valor por defecto
// del spec, no al suelo.
function usableInterval(value, fallback) {
    return (typeof value === "number" && isFinite(value) && value > 0) ? value : fallback;
}

function nextInterval(state) {
    // Retry-After manda: si el servidor pide esperar, se espera. Pero un
    // Retry-After no numérico o no finito no cuenta como tal: se sigue el
    // camino normal (reposo/alerta + backoff) en vez de tratarlo como 0.
    if (typeof state.retryAfter === "number" && isFinite(state.retryAfter) && state.retryAfter > 0)
        return clampInterval(state.retryAfter);

    var base = state.warning
        ? usableInterval(state.alertInterval, DEFAULT_ALERT_INTERVAL)
        : usableInterval(state.idleInterval, DEFAULT_IDLE_INTERVAL);

    if (state.failures > 0) {
        var doubled = base * Math.pow(2, state.failures);
        // El backoff dobla el intervalo hasta el techo (MAX_INTERVAL), pero
        // nunca por debajo de la base: si la base ya supera el techo (p. ej.
        // un idleInterval de 3600 s), un fallo no debe hacer el sondeo MÁS
        // frecuente que en condiciones normales, así que nos quedamos en la
        // base en vez de recortar hacia abajo.
        return Math.max(MIN_INTERVAL, Math.max(base, Math.min(doubled, MAX_INTERVAL)));
    }

    // Sin fallos, la base del usuario se respeta integra; solo el suelo
    // (MIN_INTERVAL) puede recortarla, nunca el techo de backoff.
    return Math.max(MIN_INTERVAL, base);
}

// RFC 7231 §7.1.3 permite dos formas para Retry-After: delta-seconds
// ("120") y fecha HTTP ("Wed, 21 Oct 2015 07:28:00 GMT"). `parseInt(header,
// 10) || 0` solo entiende la primera: ante la forma de fecha da NaN y el
// `|| 0` lo convierte en "reintenta ya", justo lo contrario de lo que pide
// un 429. Aquí se prueban ambas formas; si ninguna parsea, o el resultado
// es negativo o no finito, se devuelve 0 para que el backoff propio del
// plugin (que corre por `failures`, ver nextInterval) tome el mando en vez
// de un reintento inmediato.
function parseRetryAfter(header, now) {
    if (typeof header !== "string" || header.length === 0)
        return 0;
    if (!(now instanceof Date) || isNaN(now.getTime()))
        return 0;

    var trimmed = header.trim();

    // Delta-seconds: RFC 7231 lo define como 1*DIGIT, sin signo ni decimales.
    if (/^[0-9]+$/.test(trimmed)) {
        var seconds = parseInt(trimmed, 10);
        return (isFinite(seconds) && seconds >= 0) ? seconds : 0;
    }

    // Forma de fecha HTTP: la diferencia con "now" son los segundos a esperar.
    var whenMs = Date.parse(trimmed);
    if (!isFinite(whenMs))
        return 0;

    var diffSeconds = Math.round((whenMs - now.getTime()) / 1000);
    return (isFinite(diffSeconds) && diffSeconds > 0) ? diffSeconds : 0;
}

// Margen para no lanzar una petición con un token que caduca a mitad de vuelo.
var TOKEN_MARGIN_MS = 60000;

function safeParse(text) {
    if (!text)
        return null;
    try {
        return JSON.parse(text);
    } catch (e) {
        return null;
    }
}

// Ante un valor que no es el tipo esperado, estas dos guardas devuelven
// null en vez de dejar pasar la entrada basura. Fallar cerrado: un fichero
// de credenciales o de caché corrupto o manipulado no debe interpretarse
// como válido solo porque la coerción numérica implícita de JS no lanza.
function finiteNumber(value) {
    return (typeof value === "number" && isFinite(value)) ? value : null;
}

function nonEmptyString(value) {
    return (typeof value === "string" && value.length > 0) ? value : null;
}

function parseCredentials(text, now) {
    var invalid = { status: "invalid", token: null, expiresAt: null };

    var doc = safeParse(text);
    if (!doc || !doc.claudeAiOauth)
        return invalid;

    var oauth = doc.claudeAiOauth;
    var token = nonEmptyString(oauth.accessToken);
    var expiresAtMs = finiteNumber(oauth.expiresAt);
    if (!token || !expiresAtMs)
        return invalid;

    var expiresAt = new Date(expiresAtMs);
    if (now.getTime() > expiresAtMs - TOKEN_MARGIN_MS)
        return { status: "expired", token: null, expiresAt: expiresAt };

    return { status: "ok", token: token, expiresAt: expiresAt };
}

function extractCache(text) {
    var doc = safeParse(text);
    if (!doc || !doc.cachedUsageUtilization)
        return null;

    var cached = doc.cachedUsageUtilization;
    var fetchedAtMs = finiteNumber(cached.fetchedAtMs);
    if (!cached.utilization || !fetchedAtMs || fetchedAtMs <= 0)
        return null;

    return { payload: cached.utilization, fetchedAt: new Date(fetchedAtMs) };
}

// Ante una fecha que no es un Date válido (ausente, cadena corrupta,
// `new Date("basura")`), esta guarda devuelve null igual que finiteNumber y
// nonEmptyString: fallar cerrado en vez de dejar pasar un "Invalid Date" que
// luego se cuele en un .toISOString() (lanza) o en un formato de texto.
function validDate(value) {
    return (value instanceof Date && !isNaN(value.getTime())) ? value : null;
}

// Umbral de aviso por defecto del spec. Un threshold no numérico no debe
// interpretarse como "avisar de todo" (equivalente a caer al suelo del
// rango, p. ej. 0): cae aquí, no al mínimo.
var DEFAULT_WARN_THRESHOLD = 90;

// Antirrebote: una notificación por ventana. La identidad de la ventana es
// su resets_at, así que reiniciar el shell no vuelve a avisar, y cuando la
// ventana se renueva el aviso se rearma solo.
function notificationsFor(limits, threshold, prevState, now) {
    var notifications = [];
    var nextState = {};

    if (!Array.isArray(limits))
        return { notifications: notifications, nextState: nextState };

    var effectiveThreshold = finiteNumber(threshold);
    if (effectiveThreshold === null)
        effectiveThreshold = DEFAULT_WARN_THRESHOLD;

    var previous = (prevState && typeof prevState === "object") ? prevState : {};
    var effectiveNow = validDate(now);

    for (var i = 0; i < limits.length; i++) {
        var limit = limits[i];
        if (!limit)
            continue;

        var resetsAt = validDate(limit.resetsAt);
        var stamp = resetsAt ? resetsAt.toISOString() : null;
        var before = previous[limit.key];
        var sameWindow = before && before.resetsAt === stamp;

        if (!isWarning(limit, effectiveThreshold)) {
            // Se conserva el registro de la ventana en curso: si vuelve a
            // subir por encima del umbral, no se notifica dos veces.
            nextState[limit.key] = sameWindow ? before : { resetsAt: stamp, notified: false };
            continue;
        }

        if (sameWindow && before.notified) {
            nextState[limit.key] = before;
            continue;
        }

        // Sin resetsAt válido o sin un `now` válido no hay forma fiable de
        // calcular la cláusula "se reinicia …"; se omite entera en vez de
        // dejar un "Invalid Date" o un " se reinicia " colgando (igual que
        // cuando formatAbsolute ya vuelve vacío por un reset pasado).
        var resetClause = "";
        if (resetsAt && effectiveNow) {
            var absolute = formatAbsolute(resetsAt, effectiveNow);
            if (absolute)
                resetClause = " · se reinicia " + absolute;
        }

        notifications.push({
            key: limit.key,
            summary: "Claude",
            body: limit.percent + " % de " + limit.label + " consumido" + resetClause
        });
        nextState[limit.key] = { resetsAt: stamp, notified: true };
    }

    return { notifications: notifications, nextState: nextState };
}

// Superficie pública. Node (`require("../logic.js")`) consume exactamente
// este objeto vía module.exports, igual que antes; QML no lo ve nunca — ve
// las declaraciones de nivel superior de arriba directamente a través de
// `import "logic.js" as <lo que sea>` (ver la nota de cabecera).
var publicApi = {
    SEVERITY_RANK: SEVERITY_RANK,
    severityRank: severityRank,
    limitLabel: limitLabel,
    PRIMARY_KINDS: PRIMARY_KINDS,
    normalizeUsage: normalizeUsage,
    isWarning: isWarning,
    byCriticality: byCriticality,
    pickPrimary: pickPrimary,
    sortForPopout: sortForPopout,
    hasHiddenWarning: hasHiddenWarning,
    WEEKDAYS: WEEKDAYS,
    CURRENCY_SYMBOLS: CURRENCY_SYMBOLS,
    formatRelative: formatRelative,
    formatAbsolute: formatAbsolute,
    formatMoney: formatMoney,
    MAX_INTERVAL: MAX_INTERVAL,
    MIN_INTERVAL: MIN_INTERVAL,
    DEFAULT_IDLE_INTERVAL: DEFAULT_IDLE_INTERVAL,
    DEFAULT_ALERT_INTERVAL: DEFAULT_ALERT_INTERVAL,
    nextInterval: nextInterval,
    parseRetryAfter: parseRetryAfter,
    TOKEN_MARGIN_MS: TOKEN_MARGIN_MS,
    parseCredentials: parseCredentials,
    extractCache: extractCache,
    DEFAULT_WARN_THRESHOLD: DEFAULT_WARN_THRESHOLD,
    notificationsFor: notificationsFor
};

if (typeof module !== "undefined")
    module.exports = publicApi;
