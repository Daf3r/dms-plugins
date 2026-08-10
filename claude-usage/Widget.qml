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
// porcentaje pasa de una cifra a dos.

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
    readonly property bool hasNumber: !!primary
    readonly property bool warning: !!(primary && primary.warning)
    readonly property bool hiddenWarning: !!(usage && usage.hiddenWarning)

    // "Píldora atenuada" del spec §9: el dato no viene de un sondeo bueno.
    readonly property bool dimmed: usageStatus === "stale"

    // El glifo de los estados sin número. El de la píldora normal lo trae el
    // daemon dentro de `primary.glyph` (hourglass_empty / calendar_month), que
    // es lo que codifica QUÉ ventana se está enseñando.
    readonly property string stateGlyph: {
        if (usageStatus === "expired")
            return "key_off";
        if (usageStatus === "loading")
            return "monitoring";
        return "cloud_off";
    }

    readonly property string glyph: hasNumber ? primary.glyph : stateGlyph
    readonly property string percentText: hasNumber ? String(primary.percent) : ""

    // Severidad e identidad de ventana viajan por canales distintos —color y
    // glifo—, que es la propiedad que protegía el anillo del diseño original.
    //
    // El atenuado es SUFIJO ALFA sobre el mismo color, no un color distinto:
    // bajo un esquema monocromo varios roles Material colapsan en el mismo gris
    // y cambiar de rol no atenuaría nada. 0.7 y no menos: por debajo se queda
    // por debajo de AA para un número pequeño.
    function attenuate(c) {
        return root.dimmed ? Theme.withAlpha(c, 0.7) : c;
    }

    readonly property color glyphColor: hasNumber ? attenuate(warning ? Theme.error : Theme.widgetIconColor) : Theme.surfaceVariantText
    readonly property color textColor: hasNumber ? attenuate(warning ? Theme.error : Theme.widgetTextColor) : Theme.surfaceVariantText

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

                DankIcon {
                    name: root.glyph
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.glyphColor
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Ancho fijo con "100" de referencia: el número cambia de una a
                // tres cifras y la barra no debe moverse por eso.
                Item {
                    visible: root.hasNumber
                    width: visible ? Math.max(hBaseline.width, hNumber.implicitWidth) : 0
                    height: hNumber.implicitHeight
                    anchors.verticalCenter: parent.verticalCenter

                    StyledTextMetrics {
                        id: hBaseline
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        font.weight: Font.Bold
                        text: "100"
                    }

                    StyledText {
                        id: hNumber
                        anchors.centerIn: parent
                        text: root.percentText
                        color: root.textColor
                        font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                        font.weight: Font.Bold
                    }
                }

                // El equivalente del punto de 4 px del original: la única forma
                // de que un sublímite por modelo al 95 % no pase desapercibido,
                // dado que el glifo grande solo puede representar la ventana que
                // se está enseñando.
                DankIcon {
                    visible: root.hiddenWarning && root.hasNumber
                    name: "error"
                    size: Math.round(Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale) * 0.65)
                    color: root.attenuate(Theme.error)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Píldora vertical ─────────────────────────────────────────────────────
    // Misma información apilada. En vertical BasePill fija el ancho al grosor
    // del widget y solo mide el alto implícito.
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
                spacing: 1

                DankIcon {
                    name: root.glyph
                    size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                    color: root.glyphColor
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.hasNumber
                    text: root.percentText
                    color: root.textColor
                    font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                    font.weight: Font.Bold
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                DankIcon {
                    visible: root.hiddenWarning && root.hasNumber
                    name: "error"
                    size: Math.round(Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale) * 0.65)
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
