import QtQuick
import qs.Widgets
import qs.Modules.Plugins
import "logic.js" as Logic
import "i18n.js" as I18n

PluginComponent {
    id: root

    PluginGlobalVar {
        id: usageState
        varName: "usage"
        defaultValue: ({ status: "loading" })
    }

    Component.onCompleted: {
        console.log("claudeUsage: daemon arrancado, logic:",
                    typeof Logic.normalizeUsage === "function",
                    "i18n:", typeof I18n.render === "function")
    }
}
