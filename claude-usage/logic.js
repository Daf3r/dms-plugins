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
// plan). El resto de logic.luau — normalizeUsage, pickPrimary, nextInterval,
// parseCredentials, notificationsFor… — llega en tareas posteriores. Hasta
// entonces logic.luau sigue siendo la fuente y no se borra.

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
    CURRENCY_SYMBOLS: CURRENCY_SYMBOLS
};

if (typeof module !== "undefined")
    module.exports = publicApi;
