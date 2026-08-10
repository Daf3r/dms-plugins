// Traído de caelestia-plugins (feat/claude-usage:claude-usage/components/UsageRing.qml),
// donde nunca llegó a instanciarse (`git grep UsageRing` no da ningún uso allí).
// Tarea 11: se retematiza a los tokens de DMS y se enchufa en la tarjeta
// destacada del popout de Widget.qml, sustituyendo al par glifo+porcentaje de
// la ventana primaria. La UsageBar de las demás filas NO usa este componente.
//
// ── Lo que NO se toca (diseño, no tema) ──────────────────────────────────────
//
// La codificación por forma es el motivo de que este componente exista:
// `openArc: true` dibuja un arco de 270° con hueco abajo -> la ventana de
// sesión (5 h, algo que se vacía y reinicia). `openArc: false` dibuja un
// anillo cerrado -> el cupo semanal. La forma distingue las dos ventanas
// incluso cuando las dos están en rojo y el color deja de servir. Ese
// predicado, `startAngle`/`sweep` de 270 frente a 360, `thickness =
// max(3, ringSize*0.115)`, `RoundCap` y `CurveRenderer` son geometría del
// diseño original y se conservan sin cambios. Igual `safePercent`: el guard
// contra NaN/fuera de rango que ambas bindings (arco y etiqueta) tienen que
// seguir leyendo en vez de `percent` directamente.
//
// ── El mapa de tokens (Caelestia -> DMS) ─────────────────────────────────────
//
//   Colours.palette.m3primary                  -> Theme.primary
//   Colours.palette.m3error                     -> Theme.error
//   Colours.palette.m3surfaceContainerHighest   -> Theme.surfaceContainerHighest
//   Anim {}                                     -> NumberAnimation { duration:
//                                                  Theme.shortDuration; easing.type:
//                                                  Theme.standardEasing }, el mismo
//                                                  idioma que ya usa `Behavior on
//                                                  width` de `component UsageBar`
//                                                  en Widget.qml.
//   Tokens.font.body.builders.small.scale(...)
//     .weight(Font.DemiBold).build()            -> font.pixelSize (token
//                                                  Theme.fontSize*) + font.weight:
//                                                  Font.DemiBold.
//   qs.components / qs.services (Caelestia)     -> qs.Common (Theme) + qs.Widgets
//                                                  (StyledText), que es de donde
//                                                  los toma el resto del plugin.
import QtQuick
import QtQuick.Shapes
import qs.Common
import qs.Widgets

Item {
    id: root

    // openArc = true dibuja un arco de 270° con hueco abajo: la ventana de
    // 5 h, algo que se vacía y reinicia. false dibuja un anillo cerrado: el
    // cupo semanal completo. La forma distingue las dos ventanas incluso
    // cuando ambas están en rojo y el color deja de servir.
    property int percent: 0
    property bool openArc: false
    property bool warning: false
    property bool dimmed: false
    property int ringSize: 34
    property bool showLabel: true

    // Guards against non-finite or out-of-range percent (e.g. NaN from a
    // null UsageService.primary) reaching either the arc geometry or the
    // label text. Both bindings below must read this instead of `percent`
    // directly.
    readonly property int safePercent: isFinite(percent) ? Math.min(100, Math.max(0, percent)) : 0

    readonly property real thickness: Math.max(3, ringSize * 0.115)
    readonly property real sweep: openArc ? 270 : 360
    readonly property real startAngle: openArc ? 135 : -90
    readonly property color activeColour: warning ? Theme.error : Theme.primary

    implicitWidth: ringSize
    implicitHeight: ringSize
    opacity: dimmed ? 0.45 : 1

    Behavior on opacity {
        NumberAnimation {
            duration: Theme.shortDuration
            easing.type: Theme.standardEasing
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true

        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.surfaceContainerHighest
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.ringSize - root.thickness) / 2
                radiusY: (root.ringSize - root.thickness) / 2
                startAngle: root.startAngle
                sweepAngle: root.sweep
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.activeColour
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                id: progress

                centerX: root.width / 2
                centerY: root.height / 2
                radiusX: (root.ringSize - root.thickness) / 2
                radiusY: (root.ringSize - root.thickness) / 2
                startAngle: root.startAngle
                sweepAngle: root.sweep * root.safePercent / 100

                Behavior on sweepAngle {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }
            }
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.showLabel
        text: root.safePercent
        color: root.activeColour
        font.pixelSize: Math.round(Theme.fontSizeSmall * (root.ringSize / 40))
        font.weight: Font.DemiBold
    }
}
