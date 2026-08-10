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
//   noctalia.togglePanel(...)    -> el popout de PluginComponent, que se abre
//                                   solo al hacer clic si `popoutContent` no es
//                                   nulo. Llega en la tarea 10.
//   globals onClick() / update() -> `pillClickAction` (tarea 10) y, el segundo,
//                                   nada: no hay repintado manual que provocar.
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

    // El popout (panel.luau) es la tarea 10. Mientras `popoutContent` sea nulo,
    // `hasPopout` es falso y el clic sobre la píldora no hace nada: no se
    // declara un popout vacío porque abrir una ventana en blanco es peor que no
    // abrir ninguna, y el plugin carga igual sin él.
}
