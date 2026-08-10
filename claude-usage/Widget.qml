// Traducción de widget.luau. Superficie `widget` del plugin composite: las dos
// píldoras de barra.
//
// Solo PINTA (spec heredada §5). No evalúa severidad, no ordena, no formatea
// fechas y no traduce: todo eso viene ya resuelto dentro de la variable global
// `usage` que publica Daemon.qml, que es quien tiene el catálogo delante.
//
// NINGUNA PETICIÓN SALE DE AQUÍ. Este componente se instancia una vez POR
// PANTALLA —esta máquina tiene dos— y el spike de la tarea 1 se autoinfligió un
// 429 justamente por hacer E/S en la píldora. El daemon corre una sola vez y es
// el único dueño de la red, los ficheros y el temporizador.
//
// ── Las ataduras de widget.luau, y en qué quedó cada una ─────────────────────
//
//   noctalia.state.get("usage")  -> PluginGlobalVar { varName: "usage" }, leída
//   noctalia.state.watch("usage")   por `usageState.value`. Las dos ataduras
//                                   colapsan en una: `value` es un binding
//                                   sobre PluginService.globalVars, así que
//                                   leer ya es observar y no hay callback.
//   barWidget.isVertical()       -> las dos píldoras son componentes distintos
//                                   (horizontalBarPill / verticalBarPill) y
//                                   DMS instancia la que toca; `container()`
//                                   desaparece. `root.isVertical` existe si
//                                   hiciera falta.
//   barWidget.render(árbol)      -> los dos Component de abajo. En DMS no se
//                                   repinta a mano: son bindings.
//   barWidget.setVisible(false)  -> setVisibilityOverride(false). Es la vía de
//                                   DMS y anima el ancho a 0; ocultar con
//                                   `visible: false` dejaría el hueco.
//   barWidget.setTooltip(texto)  -> NO se traduce en esta tarea. Ver la nota
//                                   sobre el tooltip más abajo.
//   ui.row / ui.column           -> Row / Column de QtQuick.
//   ui.glyph                     -> DankIcon (Material Symbols).
//   ui.label                     -> StyledText.
//   noctalia.tr(clave)           -> desaparece del widget: los textos ya vienen
//                                   traducidos en el estado (`statusLabel`,
//                                   `footerLabel`, `strings`). Cargar el
//                                   catálogo aquí significaría releer los dos
//                                   JSON una vez por pantalla.
//   noctalia.togglePanel(...)    -> el popout de PluginComponent, declarado al
//                                   final de este fichero: con `popoutContent`
//                                   no nulo, BasePill abre el popout al hacer
//                                   clic sin que haya que engancharse a nada.
//   globals onClick() / update() -> nada, ninguno de los dos. El primero porque
//                                   el clic ya lo lleva el popout —`pillClickAction`
//                                   se queda nulo a propósito, es la vía para
//                                   SUSTITUIR ese comportamiento— y el segundo
//                                   porque no hay repintado manual que provocar.
//
// ── Lo que la traducción cambia de forma, y por qué ──────────────────────────
//
// **DOS ventanas, no una.** El original enseñaba solo la más crítica, y en la
// barra de daf3r eso significó ver la sesión al 44 % mientras la semanal iba al
// 84 %: el número que decide si podrá trabajar el resto de la semana no
// aparecía por ningún lado. `hiddenWarning` no lo tapaba, porque solo salta al
// CRUZAR el umbral de aviso (90 por defecto), así que entre 0 y 90 la semanal
// era invisible. Se pintan las dos, cada una con su glifo y su porcentaje:
//
//     ⏳ 44  ·  📅 84
//
// La segunda va atenuada para que la jerarquía siga leyéndose de un vistazo.
// Sigue sin haber cálculo aquí: las dos ranuras son los dos límites primarios
// (`Logic.PRIMARY_KINDS` = `["session", "weekly_all"]`) y el daemon publica cada
// uno en su campo, `primary` y `weekly`.
//
// `hiddenWarning` NO se retira: los sublímites por modelo siguen sin caber en
// la barra y son justo lo que ese glifo pequeño existe para delatar.
//
// **Los glifos.** Noctalia traía su propio juego de iconos; DMS usa Material
// Symbols, donde `gauge`, `key-off`, `cloud-off` y `alert-circle` no existen con
// ese nombre. Se comprobaron uno a uno contra el fichero .codepoints de la
// fuente que DMS carga: `key_off`, `cloud_off` y `error` sí están, `gauge` no
// (se usa `monitoring`, que además es el icono del manifiesto).
//
// **El tooltip no se traduce todavía.** `widget.luau` metía en el tooltip el
// único sitio donde se decía en palabras qué pasa con los estados sin número
// («Cargando…», «Sesión caducada…») y el detalle del límite. DMS no da tooltip
// en las píldoras de plugin: los widgets propios que lo hacen (DiskUsage) se
// montan un DankTooltip con coordenadas de pantalla a mano, y el idioma del
// shell para el detalle de una píldora es el POPOUT. El spec §9 asigna la
// explicación al panel, no al widget, así que el texto de `statusLabel` /
// `footerLabel` se pinta en el popout de la tarea 10 y aquí no se pierde nada
// que el spec exigiera. Queda anotado por si daf3r quiere el tooltip igual.
//
// **El ancho del número es fijo.** `StyledTextMetrics` con "100" de referencia,
// copiado de CpuMonitor: sin eso la barra entera se desplaza cada vez que el
// porcentaje pasa de una cifra a dos. Con dos ventanas importa el doble.

import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginComponent {
    id: root

    // ── El estado publicado por el daemon ────────────────────────────────────
    // Mismo `varName` que el PluginGlobalVar de Daemon.qml: es el canal. Tiene
    // que ser hijo directo del PluginComponent porque `value` y `set()` sacan
    // el pluginId de `parent`.
    //
    // El `defaultValue` repite el del daemon a propósito. La variable global
    // no existe hasta que el daemon publica por primera vez, y ese hueco NO es
    // «sin credenciales»: el spec §9 pide píldora de carga al arrancar y
    // ocultarse solo cuando faltan las credenciales. Sin este default el
    // arranque se vería igual que el caso oculto, que es justo la confusión que
    // el spec separa en dos filas distintas.
    PluginGlobalVar {
        id: usageState
        varName: "usage"
        defaultValue: ({
                status: "loading"
            })
    }

    readonly property var usage: usageState.value
    readonly property string usageStatus: (usage && usage.status) ? usage.status : ""

    // `primary` nulo con status "stale" significa sin conexión y sin dato: se
    // dice con un glifo, no se pinta un cero (spec §9, carry-forward de las
    // tareas 11-13 de Caelestia).
    readonly property var primary: usage ? usage.primary : null

    // La segunda ventana: la semanal, y la semanal SIEMPRE. Es un campo propio
    // que publica el daemon, no `others[0]`.
    //
    // La diferencia importa: `others` va ordenado por criticidad, así que
    // `others[0]` es «la más crítica de las demás». Hoy eso es la semanal, pero
    // en cuanto un sublímite por modelo entrase en aviso con la semanal
    // tranquila, la barra pasaría de «📅 84» a «🧩 61» en el mismo sitio y con
    // el mismo aspecto, y el número que motivó enseñar dos ventanas se iría sin
    // avisar. Las dos ranuras son los dos límites primarios
    // (`Logic.PRIMARY_KINDS`) y nada más; los sublímites por modelo se delatan
    // con `hiddenWarning` y se detallan en el popout.
    //
    // Si el daemon lo publica null —no hay semanal, o la semanal ya está en la
    // primera ranura— la píldora enseña solo la sesión. NO se cae a
    // `others[0]`: ese respaldo es justo la ambigüedad que se está quitando.
    readonly property var secondary: usage ? usage.weekly : null

    readonly property bool hasNumber: !!primary
    readonly property bool hasSecondary: hasNumber && !!secondary
    readonly property bool warning: !!(primary && primary.warning) || !!(secondary && secondary.warning)
    readonly property bool hiddenWarning: !!(usage && usage.hiddenWarning)

    // "Píldora atenuada" del spec §9: el dato no viene de un sondeo bueno.
    readonly property bool dimmed: usageStatus === "stale"

    // El glifo de los estados sin número. El de cada ventana lo trae el daemon
    // dentro de `glyph` (hourglass_empty / calendar_month), que es lo que
    // codifica QUÉ ventana se está enseñando.
    readonly property string stateGlyph: {
        if (usageStatus === "expired")
            return "key_off";
        if (usageStatus === "loading")
            return "monitoring";
        return "cloud_off";
    }

    // ── Color ────────────────────────────────────────────────────────────────
    // Severidad e identidad de ventana viajan por canales distintos —color y
    // glifo—, que es la propiedad que protegía el anillo del diseño original.
    //
    // Atenuar es SUFIJO ALFA sobre el mismo rol, nunca cambiar de rol: bajo un
    // esquema monocromo varios roles Material colapsan en el mismo gris
    // (on_surface_variant y secondary dan los dos #C6C6C6 en m3-monochrome) y
    // cambiar de rol no pintaría absolutamente nada. Con el alfa, el hue queda
    // libre para la severidad y las dos señales siguen siendo ortogonales:
    // la segunda ventana en aviso sale roja Y atenuada.
    //
    // 0.7 y no menos: sobre el fondo de la barra da ~5:1, que pasa AA. 0.55 se
    // queda en 3.6:1, ilegible de reojo para un número pequeño.
    //
    // Los dos motivos de atenuación —dato viejo y segunda ventana— usan el
    // MISMO 0.7 y no se acumulan. Encadenarlos daría 0.49, por debajo del
    // umbral legible; el precio es que con el dato viejo las dos ventanas se
    // ven igual de atenuadas y esa jerarquía se pierde mientras dure.
    readonly property real attenuatedAlpha: 0.7

    function alphaFor(muted) {
        return (root.dimmed || muted) ? root.attenuatedAlpha : 1.0;
    }

    function attenuate(c) {
        return root.dimmed ? Theme.withAlpha(c, root.attenuatedAlpha) : c;
    }

    // `limit` es una ventana ya decorada por el daemon; `muted` marca la
    // segunda. El color base del icono y el del texto NO son el mismo rol: en
    // el modo "colorful" de DMS el texto va en `primary` y el icono en
    // `surfaceText`.
    function windowIconColor(limit, muted) {
        const base = (limit && limit.warning) ? Theme.error : Theme.widgetIconColor;
        const a = root.alphaFor(muted);
        return a < 1.0 ? Theme.withAlpha(base, a) : base;
    }

    function windowTextColor(limit, muted) {
        const base = (limit && limit.warning) ? Theme.error : Theme.widgetTextColor;
        const a = root.alphaFor(muted);
        return a < 1.0 ? Theme.withAlpha(base, a) : base;
    }

    readonly property int pillIconSize: Theme.barIconSize(barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
    readonly property int pillTextSize: Theme.barTextSize(barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)

    // ── Visibilidad ──────────────────────────────────────────────────────────
    // Sin credenciales el widget se oculta POR COMPLETO (spec §9). Es el ÚNICO
    // caso que oculta: cualquier otro estado tiene algo que decir, aunque sea
    // un glifo.
    //
    // `setVisibilityOverride` es la vía de PluginComponent: `effectiveVisible`
    // pasa a false y BasePill anima el ancho a 0, así que no queda un hueco en
    // la barra. Es lo que hacía `barWidget.setVisible(false)`, incluido el ser
    // pegajoso: hay que volver a ponerlo a true en todos los demás caminos, y
    // por eso el handler pasa el valor en vez de llamar solo cuando se oculta.
    readonly property bool pillHidden: !usage || usageStatus === "missing"
    onPillHiddenChanged: root.setVisibilityOverride(!root.pillHidden)
    Component.onCompleted: root.setVisibilityOverride(!root.pillHidden)

    // ── El grupo «una ventana» ───────────────────────────────────────────────
    // Glifo + porcentaje, que es la unidad que se repite dos veces y en las dos
    // orientaciones. Como componente en línea y no copiado cuatro veces: si las
    // dos ventanas no reciben EXACTAMENTE el mismo trato, la comparación de un
    // vistazo —que es para lo que existe la píldora— deja de ser honesta.
    //
    // El ancho del número se fija con "100" de referencia para que la barra no
    // baile al pasar de una cifra a dos.
    // Nada de leer `root` desde dentro: un componente en línea NO ve los ids
    // del documento que lo contiene. Todo lo que necesita entra por
    // propiedades, y quien las rellena es el sitio de uso, que sí ve `root`.
    component WindowChunk: Row {
        id: chunk

        required property var limit
        required property color iconColor
        required property color textColor
        required property int iconSize
        required property int textSize

        spacing: Theme.spacingXS
        visible: !!limit

        DankIcon {
            name: chunk.limit ? chunk.limit.glyph : ""
            size: chunk.iconSize
            color: chunk.iconColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Item {
            width: Math.max(baseline.width, number.implicitWidth)
            height: number.implicitHeight
            anchors.verticalCenter: parent.verticalCenter

            StyledTextMetrics {
                id: baseline
                font.pixelSize: chunk.textSize
                font.weight: Font.Bold
                text: "100"
            }

            StyledText {
                id: number
                anchors.centerIn: parent
                text: chunk.limit ? String(chunk.limit.percent) : ""
                color: chunk.textColor
                font.pixelSize: chunk.textSize
                font.weight: Font.Bold
            }
        }
    }

    // La versión apilada, para la barra vertical. Mismo contenido y mismos
    // colores; solo cambia el eje.
    component WindowChunkStacked: Column {
        id: stack

        required property var limit
        required property color iconColor
        required property color textColor
        required property int iconSize
        required property int textSize

        spacing: 1
        visible: !!limit

        DankIcon {
            name: stack.limit ? stack.limit.glyph : ""
            size: stack.iconSize
            color: stack.iconColor
            anchors.horizontalCenter: parent.horizontalCenter
        }

        StyledText {
            text: stack.limit ? String(stack.limit.percent) : ""
            color: stack.textColor
            font.pixelSize: stack.textSize
            font.weight: Font.Bold
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // ── Píldora horizontal ───────────────────────────────────────────────────
    // BasePill ya pinta el fondo, el borde y el ripple de la píldora, y coloca
    // el contenido centrado con su propio padding: aquí solo se declaran los
    // tamaños implícitos, que son los que BasePill mide.
    horizontalBarPill: Component {
        Item {
            implicitWidth: hRow.implicitWidth
            implicitHeight: hRow.implicitHeight

            // El equivalente del `fill = "error/0.25"` del original. Se dibuja
            // más grande que el contenido para que el tinte no quede pegado a
            // las letras; desborda hacia el padding de BasePill a propósito.
            Rectangle {
                anchors.centerIn: parent
                width: parent.implicitWidth + Theme.spacingS * 2
                height: parent.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.error, 0.25)
                visible: root.warning
            }

            Row {
                id: hRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                // Los estados sin número (cargando, caducado, sin conexión) son
                // un glifo y nada más, igual que en el original.
                DankIcon {
                    visible: !root.hasNumber
                    name: root.stateGlyph
                    size: root.pillIconSize
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }

                WindowChunk {
                    limit: root.hasNumber ? root.primary : null
                    iconColor: root.windowIconColor(root.primary, false)
                    textColor: root.windowTextColor(root.primary, false)
                    iconSize: root.pillIconSize
                    textSize: root.pillTextSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Puntuación, no una frase: separa los dos pares para que
                // «⏳ 44 📅 84» no se lea como un solo número partido. Se va
                // entero con la segunda ventana, sin dejar un separador
                // colgando.
                StyledText {
                    visible: root.hasSecondary
                    text: "·"
                    color: Theme.withAlpha(Theme.surfaceVariantText, root.attenuatedAlpha)
                    font.pixelSize: root.pillTextSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                WindowChunk {
                    limit: root.hasSecondary ? root.secondary : null
                    iconColor: root.windowIconColor(root.secondary, true)
                    textColor: root.windowTextColor(root.secondary, true)
                    iconSize: root.pillIconSize
                    textSize: root.pillTextSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                // El equivalente del punto de 4 px del original: la única forma
                // de que un sublímite por modelo al 95 % no pase desapercibido,
                // dado que en la píldora solo caben dos ventanas.
                DankIcon {
                    visible: root.hiddenWarning && root.hasNumber
                    name: "error"
                    size: Math.round(root.pillIconSize * 0.65)
                    color: root.attenuate(Theme.error)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Píldora vertical ─────────────────────────────────────────────────────
    // Misma información apilada. En vertical BasePill fija el ancho al grosor
    // del widget y solo mide el alto implícito, así que lo que hay que vigilar
    // aquí es el ALTO: dos ventanas ocupan el doble que una.
    verticalBarPill: Component {
        Item {
            implicitWidth: vColumn.implicitWidth
            implicitHeight: vColumn.implicitHeight

            Rectangle {
                anchors.centerIn: parent
                width: parent.implicitWidth + Theme.spacingXS * 2
                height: parent.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.error, 0.25)
                visible: root.warning
            }

            Column {
                id: vColumn
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    visible: !root.hasNumber
                    name: root.stateGlyph
                    size: root.pillIconSize
                    color: Theme.surfaceVariantText
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                WindowChunkStacked {
                    limit: root.hasNumber ? root.primary : null
                    iconColor: root.windowIconColor(root.primary, false)
                    textColor: root.windowTextColor(root.primary, false)
                    iconSize: root.pillIconSize
                    textSize: root.pillTextSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                // En vertical el separador es una línea, no un punto: un «·»
                // entre dos bloques apilados se lee como suciedad, y una regla
                // fina dice «hasta aquí una ventana» sin gastar altura.
                Rectangle {
                    visible: root.hasSecondary
                    width: Math.round(root.pillIconSize * 0.8)
                    height: 1
                    color: Theme.withAlpha(Theme.surfaceVariantText, root.attenuatedAlpha)
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                WindowChunkStacked {
                    limit: root.hasSecondary ? root.secondary : null
                    iconColor: root.windowIconColor(root.secondary, true)
                    textColor: root.windowTextColor(root.secondary, true)
                    iconSize: root.pillIconSize
                    textSize: root.pillTextSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                DankIcon {
                    visible: root.hiddenWarning && root.hasNumber
                    name: "error"
                    size: Math.round(root.pillIconSize * 0.65)
                    color: root.attenuate(Theme.error)
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    // EL POPOUT — traducción de panel.luau
    // ═════════════════════════════════════════════════════════════════════════
    //
    // El desglose. Layout P2 del spec §6: la ventana crítica manda y el resto va
    // en lista fina. Igual que la píldora, SOLO PINTA: todo el texto llega ya
    // formateado y ya traducido dentro de la variable global `usage`.
    //
    // **Este fichero NO importa i18n.js ni lee translations/.** DMS no tiene i18n
    // para plugins y el único que ve el catálogo es el daemon, que corre una vez;
    // Widget.qml se instancia una vez POR PANTALLA y cargar los dos JSON aquí los
    // releería por cada una. Las tres claves `panel.*` del catálogo se usan desde
    // aquí, pero resueltas en el daemon: `panel.updatedAgo` viaja dentro de
    // `fetchedAtLabel` (y por tanto de `footerLabel`), y `panel.refresh` /
    // `panel.extraCredits` dentro de `strings`.
    //
    // ── Las ataduras de panel.luau, y en qué quedó cada una ──────────────────
    //
    //   require("./logic.luau")      -> DESAPARECE. El panel solo llamaba a
    //                                   Logic.describeMoney, y ese formateo bajó
    //                                   al daemon (`moneyLabel`) porque el
    //                                   separador decimal y el lado del símbolo
    //                                   salen del catálogo. Aquí llegan
    //                                   `usedLabel` y `limitLabel` ya montados.
    //   noctalia.state.get("usage")  -> `usageState.value`, el mismo
    //   noctalia.state.watch("usage")   PluginGlobalVar que usa la píldora. Las
    //                                   dos colapsan en una: `value` es un
    //                                   binding, leer ya es observar, y no hay
    //                                   `render()` que volver a llamar.
    //   noctalia.runAsync("noctalia msg plugin … refresh")
    //                                -> `refreshRequest.set(Date.now())`. NO se
    //                                   lanza un proceso: en DMS el canal entre
    //                                   el widget y el daemon es otra variable
    //                                   global del plugin, que el daemon vigila
    //                                   con un Connections sobre
    //                                   `onGlobalVarChanged`. Se manda la marca
    //                                   de tiempo porque lo que importa es que
    //                                   el valor CAMBIE.
    //   noctalia.getConfig(clave)    -> `root.pluginData[clave]`, que
    //                                   PluginComponent carga de SettingsData.
    //   noctalia.tr(clave)           -> desaparece: ver arriba.
    //   panel.render(árbol)          -> `popoutContent`, un Component. En DMS no
    //                                   se repinta a mano; son bindings, así que
    //                                   las cuatro llamadas (los tres estados
    //                                   sin dato y el normal) pasan a ser cuatro
    //                                   `visible:`.
    //   ui.column / ui.row           -> Column / Row de QtQuick.
    //   ui.scroll                    -> DankFlickable, pero con un matiz: aquí el
    //                                   popout CRECE con el contenido (ver
    //                                   `maxContentHeight` abajo), así que la
    //                                   barra solo aparece si se pasa del techo.
    //   ui.label                     -> StyledText.
    //   ui.glyph                     -> DankIcon (Material Symbols).
    //   ui.button                    -> DankButton (`text`, no `label`; esa
    //                                   trampa era de ui.button y no se hereda).
    //   ui.separator                 -> Rectangle de 1 px (`PanelDivider`), que
    //                                   es como los pinta DMS.
    //   ui.spacer                    -> DESAPARECE: en QML el empujón a la
    //                                   derecha se hace anclando, no metiendo un
    //                                   hijo elástico. Es `DetailRow`.
    //   ui.box con flexGrow          -> `UsageBar`. Ver la nota de abajo.
    //
    // ── La barra de progreso se sigue pintando a mano, y ahora por otra razón ─
    //
    // El original la pintaba a mano porque el `ui.progress` de Noctalia estaba
    // roto (commit f6fcfcc: cinco variantes pintadas a la vez salieron idénticas,
    // llenas y blancas). Aquí el motivo es más simple: **DMS 1.5.3 no tiene
    // ningún componente de barra lineal**. `M3WaveProgress` es un shader de
    // seek de audio con onda y `phase` animada, no un indicador de porcentaje.
    // Lo que DMS hace en su propia interfaz es exactamente esto — pista + relleno
    // con dos Rectangle (`Modules/BuiltinDesktopPlugins/SystemMonitorWidget.qml`,
    // barras de CPU/mem/disco) —, así que pintar a mano no es una excepción del
    // plugin: es la casa.
    //
    // Cambia la FORMA, no el resultado: el original ponía dos cajas en una fila
    // repartiéndose el ancho con `flexGrow` porque el DSL de Lua no tenía forma de
    // superponer nada. En QML el relleno es un hijo de la pista y su ancho es
    // `pista.width * pct`, que tampoco necesita saber cuánto mide el panel.
    //
    // ── Decir POR QUÉ el dato es viejo (spec §9) ─────────────────────────────
    //
    // El pie lleva las dos mitades, «Sin conexión · dato de hace 8 min» frente a
    // «Caché local · hace 4 días», y las monta el daemon en `footerLabel`. Aquí
    // se refuerzan con dos señales que no son texto, porque el texto del pie es
    // lo primero que la vista se salta:
    //
    //   · **el bloque con los números se atenúa** al 0.7 —el mismo alfa de la
    //     píldora, para que las dos superficies digan lo mismo— y el pie NO,
    //     así que con dato viejo lo más brillante del popout es la explicación;
    //   · **un glifo delante del pie**: `cloud_off` si el dato es el último valor
    //     bueno en memoria y `history` si sale de la caché de disco, en
    //     `Theme.warning`. Naranja y no rojo a propósito: el rojo ya significa
    //     «cerca del límite» y son dos cosas ortogonales.
    //
    // Y el pie está en TODOS los estados, no solo en el normal. En panel.luau los
    // tres estados sin número volvían antes de llegar al pie, así que con la
    // sesión caducada no había ni procedencia ni botón de refrescar. Es el mismo
    // fallo que daf3r vio en vivo hoy —un 44 congelado sin forma de saberlo— pero
    // en el estado donde más falta hace.

    // El canal de refresco hacia el daemon. Tiene que ser hijo directo del
    // PluginComponent: `set()` saca el pluginId de `parent`.
    PluginGlobalVar {
        id: refreshRequest
        varName: "refreshRequest"
        defaultValue: 0
    }

    function requestRefresh() {
        refreshRequest.set(Date.now());
    }

    // El equivalente de noctalia.getConfig, con el mismo cuidado que en el
    // daemon: la ausencia es `undefined`, y no se resuelve el default con `||`
    // porque un `false` o un `0` legítimos se perderían.
    function configOr(key, fallback) {
        const data = root.pluginData;
        if (!data)
            return fallback;
        const value = data[key];
        return (value === undefined || value === null) ? fallback : value;
    }

    // `~= false` en el original: el ajuste sin poner cuenta como activado.
    readonly property bool showScopedLimits: root.configOr("show_scoped_limits", true) !== false
    readonly property bool showExtraUsage: root.configOr("show_extra_usage", true) !== false

    // `others` viene ya ordenada por criticidad y COMPLETA: aquí sí entran los
    // sublímites por modelo, que la píldora deja fuera a propósito.
    readonly property var others: (usage && usage.others) ? usage.others : []
    readonly property var extraUsage: usage ? usage.extraUsage : null
    readonly property bool hasExtraUsage: !!(extraUsage && (extraUsage.enabled || extraUsage.everEnabled))

    readonly property string statusLabel: (usage && usage.statusLabel) ? usage.statusLabel : ""
    readonly property string footerLabel: (usage && usage.footerLabel) ? usage.footerLabel : ""
    readonly property string refreshLabel: (usage && usage.strings && usage.strings.refresh) ? usage.strings.refresh : ""
    readonly property string extraCreditsLabel: (usage && usage.strings && usage.strings.extraCredits) ? usage.strings.extraCredits : ""

    // El spec §7 no deja que un refresco a mano se trague en silencio.
    readonly property bool inFlight: !!(usage && usage.inFlight)

    // De dónde sale el dato viejo. Vacío cuando el dato es fresco.
    readonly property string provenanceGlyph: {
        if (!root.dimmed)
            return "";
        return (usage && usage.source === "cache") ? "history" : "cloud_off";
    }

    readonly property string primaryResets: {
        const p = root.primary;
        if (!p)
            return "";
        const abs = p.resetsAbs || "";
        const rel = p.resetsRel || "";
        return abs !== "" ? abs + " · " + rel : rel;
    }

    // ── Piezas repetidas ─────────────────────────────────────────────────────
    // Como componentes en línea por el mismo motivo que WindowChunk: dos filas
    // que se pintan distinto dejan de ser comparables de un vistazo. Nada de
    // leer `root` desde dentro; todo entra por propiedades.

    component PanelDivider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.outlineLight
    }

    // Pista + relleno. El `percent` ya viene decidido por el daemon (incluido el
    // `show_remaining`, que lo invierte): aquí no se calcula nada.
    component UsageBar: Rectangle {
        id: track

        required property int percent
        required property color fillColor

        height: 6
        radius: 3
        color: Theme.withAlpha(Theme.outline, 0.2)

        Rectangle {
            width: track.width * Math.max(0, Math.min(100, track.percent)) / 100
            height: track.height
            radius: track.radius
            color: track.fillColor

            Behavior on width {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }
        }
    }

    // La fila «etiqueta … valor» del original (ui.label + ui.spacer + ui.label).
    // El valor se ancla a la derecha y la etiqueta ocupa lo que queda: sin
    // spacer, y la etiqueta larga se recorta en vez de empujar al valor fuera.
    component DetailRow: Item {
        id: row

        required property string label
        required property string value
        property color labelColor: Theme.surfaceText
        property color valueColor: Theme.surfaceText
        property int fontSize: Theme.fontSizeSmall
        property int fontWeight: Font.Normal

        width: parent ? parent.width : 0
        height: Math.max(rowLabel.implicitHeight, rowValue.implicitHeight)

        StyledText {
            id: rowValue

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: row.value
            color: row.valueColor
            font.pixelSize: row.fontSize
            font.weight: row.fontWeight
        }

        StyledText {
            id: rowLabel

            anchors.left: parent.left
            anchors.right: rowValue.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: row.labelColor
            font.pixelSize: row.fontSize
            font.weight: row.fontWeight
            elide: Text.ElideRight
        }
    }

    // ── Geometría ────────────────────────────────────────────────────────────
    //
    // 6eca0d0 dejó el panel de Noctalia en 360 de alto tras medirlo: allí la
    // altura era un número FIJO del manifiesto, quedarse corto cortaba el pie sin
    // barra de scroll y sin una línea en el log, y `height = "auto"` se aceptaba
    // y se ignoraba. **En DMS ese problema no existe**: PluginPopout, en cuanto
    // carga el contenido, rebindea su altura a `item.implicitHeight`
    // (`Modules/Plugins/PluginPopout.qml`, en `Loader.onLoaded`), así que el
    // popout crece con lo que haya dentro y no se puede cortar nada.
    //
    // `popoutHeight` solo se usa en los fotogramas anteriores a esa carga: es una
    // estimación de arranque, no un techo. 220 sale de medir el popout real
    // dentro del shell con los datos de hoy —tarjeta + barra + reinicio + dos
    // límites + créditos + pie miden **201**, y PluginPopout les suma su propio
    // padding hasta 217—, así que el primer fotograma ya sale del tamaño bueno y
    // no se ve un salto al abrir.
    //
    // El techo de verdad es `maxContentHeight`, y ahí sí hay barra de scroll —
    // que es lo que traduce el `ui.scroll` del original. 420 con 12 sublímites
    // por modelo el contenido mide 451 y empieza a hacer scroll; con los 1-2 que
    // la API devuelve hoy sobran 219. Es el criterio de 6eca0d0 (aguantar
    // modelos nuevos sin tocar el número) sin su riesgo: pasarse ya no corta el
    // pie en silencio, saca barra.
    //
    // El ancho es el de PluginComponent, 400, menos el padding que le mete
    // PluginPopout: el contenido queda en 384. La línea más larga con diferencia
    // es la del pie («Caché local · hace 8 h 11 min» más el botón), y cabe.
    popoutWidth: 400
    popoutHeight: 220

    popoutContent: Component {
        Item {
            id: panel

            // PluginPopout rellena las dos si el item las declara. `closePopout`
            // no se usa —no hay botón de cerrar, igual que en el original: se
            // sale con Escape o pinchando fuera— pero `parentPopout` sí, para
            // saber cuándo se ABRE.
            property var closePopout: null
            property var parentPopout: null

            // No `readonly`: el banco de pruebas lo sube para medir el contenido
            // sin techo y así saber cuánto falta para tocarlo.
            property int maxContentHeight: 420

            implicitHeight: Math.min(body.implicitHeight, panel.maxContentHeight)

            // Refresco inmediato al abrir (spec §7). No vale
            // `Component.onCompleted`: DankPopout deja el árbol CALIENTE entre
            // aperturas (`_contentWarm`), así que el item se crea una vez y las
            // aperturas siguientes no lo volverían a crear. Se cuelga de que el
            // popout pase a visible, y las dos vías están guardadas por
            // `shouldBeVisible` para que un árbol precargado en frío no sondee.
            //
            // Un refresco de más no gasta cuota: `poll()` sale por la guarda
            // `inFlight` si ya hay uno en vuelo.
            function refreshOnOpen() {
                if (panel.parentPopout && panel.parentPopout.shouldBeVisible)
                    root.requestRefresh();
            }

            onParentPopoutChanged: panel.refreshOnOpen()

            Connections {
                target: panel.parentPopout
                ignoreUnknownSignals: true

                function onShouldBeVisibleChanged() {
                    panel.refreshOnOpen();
                }
            }

            // El ancho de la columna se toma del Flickable por su id y no con
            // `parent.width`: dentro de un Flickable `parent` es el contentItem,
            // cuyo tamaño sale de contentWidth/contentHeight, y encadenarlo con
            // un contentHeight que depende de la columna es pedir un ciclo.
            DankFlickable {
                id: scroller

                anchors.fill: parent
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true

                Column {
                    id: body

                    width: scroller.width
                    spacing: Theme.spacingS

                    // ── 1. Los estados sin dato ──────────────────────────────
                    // Cargando, sesión caducada y sin conexión sin dato. El texto
                    // lo trae `statusLabel`, ya traducido; el glifo es el mismo
                    // que enseña la píldora, para que las dos superficies no
                    // cuenten historias distintas.
                    Item {
                        width: parent.width
                        height: Math.max(stateIcon.implicitHeight, stateText.implicitHeight)
                        visible: !root.hasNumber

                        DankIcon {
                            id: stateIcon

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            name: root.stateGlyph
                            size: Theme.iconSize - 4
                            color: root.usageStatus === "expired" ? Theme.error : Theme.surfaceVariantText
                        }

                        StyledText {
                            id: stateText

                            anchors.left: stateIcon.right
                            anchors.leftMargin: Theme.spacingS
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.statusLabel
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ── 2..4. El desglose ────────────────────────────────────
                    // Atenuado entero cuando el dato es viejo, con el mismo 0.7
                    // de la píldora. El pie queda fuera de este bloque a
                    // propósito: es lo único que explica la atenuación.
                    Column {
                        width: parent.width
                        spacing: Theme.spacingS
                        visible: root.hasNumber
                        opacity: root.dimmed ? root.attenuatedAlpha : 1.0

                        // Tarjeta destacada: la ventana crítica.
                        //
                        // AQUÍ VA `UsageRing` (tarea 11). El anillo sustituye al
                        // par glifo+porcentaje de esta fila, no a la barra: la
                        // barra la conservan las demás filas.
                        Item {
                            width: parent.width
                            height: Math.max(primaryIcon.implicitHeight, primaryLabel.implicitHeight, primaryPercent.implicitHeight)

                            DankIcon {
                                id: primaryIcon

                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                name: root.primary ? root.primary.glyph : ""
                                size: Theme.iconSize - 4
                                color: (root.primary && root.primary.warning) ? Theme.error : Theme.primary
                            }

                            StyledText {
                                id: primaryPercent

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.primary ? root.primary.percent + " %" : ""
                                color: (root.primary && root.primary.warning) ? Theme.error : Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                            }

                            StyledText {
                                id: primaryLabel

                                anchors.left: primaryIcon.right
                                anchors.leftMargin: Theme.spacingS
                                anchors.right: primaryPercent.left
                                anchors.rightMargin: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.primary ? root.primary.label : ""
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                        }

                        UsageBar {
                            width: parent.width
                            percent: root.primary ? root.primary.percent : 0
                            fillColor: (root.primary && root.primary.warning) ? Theme.error : Theme.primary
                        }

                        // Cuándo se reinicia: absoluta y relativa, o solo la
                        // relativa si no hay absoluta. Las dos llegan resueltas.
                        StyledText {
                            width: parent.width
                            text: root.primaryResets
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                            visible: text !== ""
                        }

                        // El resto de límites, ya ordenados por criticidad.
                        PanelDivider {
                            visible: root.showScopedLimits && root.others.length > 0
                        }

                        Repeater {
                            model: root.showScopedLimits ? root.others : []

                            delegate: DetailRow {
                                required property var modelData

                                label: modelData ? modelData.label : ""
                                value: modelData ? modelData.percent + " %" : ""
                                valueColor: (modelData && modelData.warning) ? Theme.error : Theme.surfaceText
                            }
                        }

                        // Créditos extra. Los dos importes vienen montados del
                        // daemon (`usedLabel` / `limitLabel`), que es donde está
                        // el catálogo que decide el separador decimal y el lado
                        // del símbolo.
                        PanelDivider {
                            visible: root.showExtraUsage && root.hasExtraUsage
                        }

                        DetailRow {
                            visible: root.showExtraUsage && root.hasExtraUsage
                            label: root.extraCreditsLabel
                            value: root.extraUsage ? (root.extraUsage.usedLabel + " / " + root.extraUsage.limitLabel) : ""
                        }
                    }

                    // ── 5. El pie: procedencia Y antigüedad ──────────────────
                    PanelDivider {}

                    Item {
                        width: parent.width
                        height: Math.max(footerInfo.implicitHeight, refreshButton.height)

                        Row {
                            id: footerInfo

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - refreshButton.width - Theme.spacingS
                            spacing: Theme.spacingXS

                            DankIcon {
                                id: provenanceIcon

                                visible: root.provenanceGlyph !== ""
                                name: root.provenanceGlyph
                                size: Theme.fontSizeSmall + 4
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                width: footerInfo.width - (provenanceIcon.visible ? provenanceIcon.width + footerInfo.spacing : 0)
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.footerLabel
                                color: root.dimmed ? Theme.warning : Theme.surfaceVariantText
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }
                        }

                        // Con una petición en vuelo el botón se apaga: es lo que
                        // impide que un segundo clic parezca que no hizo nada
                        // (spec §7). `inFlight` lo publica el daemon.
                        DankButton {
                            id: refreshButton

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.refreshLabel
                            iconName: "refresh"
                            buttonHeight: 32
                            horizontalPadding: Theme.spacingM
                            backgroundColor: "transparent"
                            textColor: Theme.primary
                            enabled: !root.inFlight
                            onClicked: root.requestRefresh()
                        }
                    }
                }
            }
        }
    }
}
