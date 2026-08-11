# Ledger — `claude-usage` para DMS

Registro de las 13 tareas del port de Noctalia (Luau) a DankMaterialShell
(QML + JavaScript), ejecutado con subagentes el 2026-08-10. El plan es
`../plans/2026-08-10-claude-usage-dms.md` y el spec
`../specs/2026-08-10-claude-usage-dms-design.md`.

Aquí queda lo que el historial de git no cuenta: las decisiones de daf3r, las
hipótesis refutadas con medidas, las trampas del host que costaron una tarea
entera descubrir, y la deuda que se triaró y se dejó pasar a propósito.

---


Rama: feat/claude-usage · repo: ~/Projects/dms-plugins
Pre-flight: 4 conflictos presentados y resueltos con daf3r el 2026-08-10.
  - implementar en main -> rama feat/claude-usage
  - 5 pasos necesitan GUI -> marcados 🖐️, los verifica daf3r
  - los subagentes tocan el escritorio en vivo -> aceptado
  - tarea 8 sin codigo -> reescrita con el QML completo antes de arrancar

Task 1: ficheros del spike creados en ~/.config/DankMaterialShell/plugins/SpikeHttp
Task 1: subagente af2b358d789225f75 (sonnet), estado DONE_WITH_CONCERNS
Task 1: corregido el plan — `dms ipc plugins rescan` no existe, es `plugin-scan scan`
Task 1: BLOQUEADA en el paso 3 🖐️ — requiere que daf3r cargue el widget y lea la pildora
Task 1: paso 3 verificado por daf3r — pildora mostro "status=429 date=SI"
Task 1: VEREDICTO — gana XMLHttpRequest; parseRetryAfter vuelve; Daemon.qml sin curl
Task 1: hallazgo — el 429 fue autoinfligido: la pildora corre 1 vez POR PANTALLA (2 aqui).
        Ninguna peticion debe salir de Widget.qml. Valida la arquitectura composite.
Task 1: complete (commits de94788..61a8f60, spike borrado, nota commiteada)

=== PIVOTE 2026-08-10 ===
Task 2 (v1): DESCARTADA. El subagente a8f8ae1b502a3a8b6 encontro que claude-usage/ ya
  contenia la implementacion COMPLETA de Noctalia en Luau (15 commits: logic.luau 548
  lineas, service, widget, panel, i18n en/es, 11 ficheros de test = 123 casos).
  La spec y el plan v1 partian de que solo existia la spec. Premisa falsa.
  Su commit 24d2c9d copiaba la version ANTERIOR del diseño y piso tests/run.fish.
  Revertido en edea82a.
Decision de daf3r: opcion B — partir de la version de Noctalia, i18n incluido en v1.
Spec corregida (9e179fa). Plan v2 con 13 tareas (5ff3670). Briefs regenerados.
Task 2: implementador a294301b231c0e84d (sonnet), commit fab5ebe, 9/9 verde
Task 2: fix round 1/5 (1 addressed, 0 open — desc.text y desc.weekday faltaban en i18n.js;
        los produce logic.luau:51 y :360, no eran pegamento del host; commits fab5ebe..e3184c5)
Task 2: re-revision (opus) — ADDRESSED, sin roturas nuevas, contrato de render.luau cubierto
Task 2: minor (deferred): resolve() usa || , asi que una traduccion de valor "" caeria al
        catalogo de respaldo; en Lua "" es truthy y render.luau la usaria. Hoy inocuo
        (ningun catalogo tiene cadenas vacias). Triar en la revision final.
Task 2: complete (commits 5ff3670..e3184c5, review clean)
Task 3: implementador afed872db0ecfb8bd (opus), commit 4476f5b
Task 3: 23 casos de format.test.luau traducidos, 37/37 verde con los de i18n
Task 3: PENDIENTE su revision de tarea formal (no dispatchada aun)
Task 3: duda abierta — describeMoney con currency="" devuelve simbolo vacio. Fiel al
        Luau ("" es truthy en Lua) pero huele a accidente. Decidir al portar
        normalizeUsage en la tarea 4: se blinda a "USD" o se conserva.
Task 3: corregido — tests/run.fish apuntaba al devshell noctalia-plugins, borrado al
        renombrar. Rodeo documentado en el plan y en los 13 briefs (c3f833c).
Task 4: implementador ace1ae8ffe2573134 (opus), commit 0e3fdab, 72/72 verde
Task 4: 35 casos traducidos (normalize 18 + ordering 17)
Task 4: byCriticality predicado->comparador, desempate por key conservado
Task 4: trampa NO listada que aparecio — math.round de Lua redondea .5 alejandose del
        cero, Math.round no. Hay helper `round` que conserva la semantica.
Task 4: truthiness de Lua mordio 3 veces (rank 0 de "normal", scopeName "", not not 0)
Task 4: mi brief pedia `limitLabel`, que NO existe en logic.luau — es el nombre de
        Caelestia para labelDescriptor. El subagente no lo invento.
Task 4: CONFIRMADO — currency puede llegar "" desde la API; describeMoney da simbolo
        vacio, identico en Luau y JS. Fiel por decision de daf3r. Triar en revision final.
Task 4: PENDIENTE su revision de tarea formal
Task 5: implementador afe23b2b06900d708 (opus), commit 353d425, 115/115 verde
Task 5: 43 casos nuevos (cadence 13, credentials 13, notifications 11, retry-after 6)
Task 5: parseRetryAfter recuperada de Caelestia; cubre las DOS formas del RFC 7231
        (delta-seconds y fecha HTTP). No se amplio el alcance.
Task 5: ACEPTADO — trajo tambien la rama state.retryAfter de nextInterval. parseRetryAfter
        sola no hace nada y la logica pura es mejor sitio que el daemon.
        >>> INTERFAZ PARA TAREA 8: Daemon.qml NO debe programar el retraso a mano. Mete
        >>> retryAfter en el state que pasa a nextInterval y deja que la logica decida.
Task 5: ACEPTADO con reserva — safeParse endurecido a typeof text !== "string" (antes
        dejaba pasar JSON.parse(true)). Es cambio de comportamiento en un port, pero
        safeParse no tenia contraparte en Luau, asi que no habia equivalencia que
        preservar. Triar en revision final.
Task 5: PENDIENTE su revision de tarea formal
Task 6: implementador (opus), 147/147 verde (144 pass + 3 skip), 0 fail
Task 6: 32 casos nuevos (fixtures 22, smoke 1, translations 9). Los .json de tests/fixtures/
        se leen con require, sin conversion. json2luau.py BORRADO.
Task 6: json2luau.py tambien alimentaba translations.fixture.luau, del que dependen format,
        normalize, notifications y translations en Luau, y los tres modulos generados estan
        en .gitignore. run.fish ahora se salta con aviso el .test.luau cuyo modulo falte, en
        vez de reventar con MODULE_NOT_FOUND. En esta maquina los modulos siguen ahi: 123/123.
Task 6: el exit 1 de run.fish es PREVIO a esta tarea (3 TypeError de luau-analyze sobre
        logic.luau + luau-lsp ausente de nix shell nixpkgs#luau). Verificado contra HEAD.
Task 6: translations.test.js deja 3 casos en SKIP con motivo escrito: escanean plugin.json y
        los .qml, que llegan en las tareas 7 a 12. Se activan solos; verificado que activan y
        que fallan por lo correcto.
        >>> INTERFAZ PARA TAREA 10: el caso "ninguna clave de panel.* queda sin usar" exigira
        >>> que el panel use panel.updatedAgo, panel.refresh y panel.extraCredits.
        >>> INTERFAZ PARA TAREAS 8-12: el escaneo NO busca noctalia.tr(); busca los literales
        >>> con forma de clave, asi que da igual como se invoque a i18n.render.
Task 6: MEJORA justificada — 1 caso nuevo en translations.test.js. El original solo miraba que
        las siete weekday.N existieran en el catalogo; la COMPOSICION de weekday.<N> la hacia
        tests/render.luau, un espejo de la suite. En el port la hace i18n.js, que es
        produccion. El caso nuevo recorre los 11 descriptores en los dos idiomas y exige que
        no se pinten como su clave, no dejen {hueco} y no contengan weekday.N.
Task 6: manifest.test.luau (5 casos) sigue SIN sucesor — prueba plugin.toml, va con la tarea 7.
Task 6: PENDIENTE su revision de tarea formal
Task 6: implementador addb7294cb977e548 (opus), commit 3ad8bb3
Task 6: 147 casos · 144 pass · 0 fail · 3 skipped. json2luau.py borrado.
Task 6: MEJORA JUSTIFICADA — translations.test original solo comprobaba PRESENCIA de las
        claves weekday.N; la composicion la hacia render.luau, que era espejo de la suite,
        no produccion. Ahora la hace i18n.js, que si lo es. Caso 9 nuevo recorre los once
        descriptores en los dos idiomas. Verificado por mutacion: atrapa un {hueco} mal
        escrito que el test original dejaba pasar.
Task 6: 3 casos en SKIP con motivo impreso — escanean plugin.json y los .qml, que no
        existen hasta las tareas 7-12. Verificado que se activan solos y fallan por lo
        correcto.
Task 6: run.fish modificado (no es .luau) — json2luau.py tambien generaba
        translations.fixture.luau, del que dependen 4 suites Luau. Ahora se salta con
        aviso las que les falte un modulo generado.
Task 6: el exit 1 de run.fish es PREVIO — TypeErrors de luau-analyze y luau-lsp ausente
        de `nix shell nixpkgs#luau`. Consecuencia de quitar luau del devshell.

>>> INTERFAZ PARA TAREA 7: manifest.test.luau (5 casos) sigue SIN SUCESOR. Su sitio es
>>> la tarea 7, cuando exista plugin.json. Portarlo alli.
>>> INTERFAZ PARA TAREA 10: el caso "ninguna clave de panel.* queda sin usar" exige que
>>> el popout use panel.updatedAgo, panel.refresh y panel.extraCredits.

Task 6: complete — LOGICA TERMINADA. Tareas 3,4,5,6 pendientes de revision formal.
SIGUIENTE: tarea 7 (manifiesto + daemon). Su paso 3 es 🖐️ y lo verifica daf3r.
Task 7: implementador a88bade380c89303b (sonnet), commits bf0eabd + 50edd39
Task 7: fix round 1/5 (1 addressed) — la suite quedaba en 3 ROJOS. Las guardas de la
        tarea 6 se ataban a plugin.json cuando cada caso depende de otro fichero.
        Ahora: 149 verde / 0 fallos / 3 skip, guardas verificadas por mutacion.
        Uno de los tres estaba MAL PLANTEADO: comprobaba ajustes inline en el manifiesto
        al estilo plugin.toml, y en DMS van en Settings.qml. Reescrito.
Task 7: HALLAZGO — DMS DESCUBRE un composite con componentes que faltan pero NO lo activa.
        PLUGIN_ENABLE_FAILED hasta que exista Widget.qml. No se puede verificar el daemon
        hasta la tarea 9.
Task 7: HALLAZGO — console.log de los plugins NO llega al journal. Las tareas 8 y 10 no
        pueden verificar por journalctl; hay que buscar otra via.
Task 7: sonda desechable ClaudeProbe (type daemon) creada y borrada. NO respondio la
        pregunta: ni con imports JS ni sin ellos escribio su fichero, asi que
        Component.onCompleted + Quickshell.execDetached no sirve como via de prueba en un
        daemon. Metodo descartado, no es evidencia sobre los imports.
Task 7: RIESGO REDUCIDO — logic.js ya cierra `module.exports` con
        `if (typeof module !== "undefined")`, asi que no reventara al importarlo desde QML.
        Las funciones son declaraciones de nivel superior, que es lo que QML expone.
        Verificacion definitiva: tarea 9, cuando exista Widget.qml.
Task 7: complete (commits 3ad8bb3..50edd39) — con la verificacion del daemon diferida a la 9
Task 8: implementador a7bca8bffe7f4db7c (opus), commit 3876e8a. Suite intacta.
Task 8: verificado sin activar el plugin — qmlformat diff vacio, qmllint SIN avisos
        (montando un arbol qs.* con qmldir del DMS instalado), las 12 claves de catalogo
        existen en los dos idiomas, y `dms ipc toast warnWith` probado EN VIVO.
Task 8: ACEPTADO — toast warnWith en vez de warn: `warn` acepta un solo texto y habria
        perdido el resumen "Claude" que pide §11.
Task 8: ACEPTADO — 4 campos nuevos al estado (statusLabel, footerLabel, strings, inFlight)
        y 2 a extraUsage. DMS no tiene i18n para plugins y el catalogo solo lo ve el
        daemon, asi que lo que panel.luau montaba con noctalia.tr baja aqui.
        CONSECUENCIA: Widget.qml NO necesita i18n.js ni translations/.
Task 8: ACEPTADO — fuera el state.json a mano; DMS tiene savePluginState/loadPluginState.
Task 8: ACEPTADO — glifos: "calendar" NO existe en Material Symbols y habria pintado un
        hueco. Ahora hourglass_empty y calendar_month.

>>> RIESGO ABIERTO 1 (el mayor): XMLHttpRequest con URL file:// NO esta probado dentro de
>>> un plugin. El spike de la tarea 1 solo probo https://. Si esta bloqueado, el daemon no
>>> lee ni credenciales, ni cache, ni catalogos. LA TAREA 9 LO RESUELVE: si el texto sale
>>> traducido, file:// funciona; si salen las claves crudas, no.

>>> RIESGO ABIERTO 2 (fidelidad, contra §11): ToastService de DMS tiene maxQueueSize = 3 y
>>> DESCARTA los toasts que no son de nivel error cuando la cola esta llena. Si cuatro
>>> limites cruzan el umbral a la vez, uno se pierde EN SILENCIO — y el antirrebote de
>>> logic.js ya lo habra marcado como notificado, asi que no se reintenta. noctalia.notify
>>> no tenia ese techo. §11 exige cubrir TODOS los limites. Hay 5 ventanas posibles, asi
>>> que 4 a la vez es plausible cerca de un reinicio semanal. PENDIENTE DE DECISION.
Task 9: implementador ae76ed31fe25a209b (opus), commit 31f20c2. Suite 150 pass / 0 fail / 2 skip.
Task 9: RIESGO 1 RESUELTO Y ROTO — XMLHttpRequest con file:// esta VETADO por Qt
        (QML_XHR_ALLOW_FILE_READ). Falla EN SILENCIO: open() no lanza y el callback nunca
        llega a DONE, asi que el daemon se queda con catalogsPending=1 y no publica NADA.
        Sustituto verificado en vivo: FileView de Quickshell.Io. Fix despachado a la tarea 8.
        DECISION: FileView, NO la variable de entorno — esta levantaria el veto para todo
        el shell y haria el plugin no distribuible.
Task 9: RIESGO 2 RESUELTO OK — QML SI resuelve logic.js. toMilliseconds(5)=5000 y
        DEFAULT_WARN_THRESHOLD=90 impresos desde un plugin cargado. La guarda de
        module.exports no estorba y no hace falta Logic.Logic.*
Task 9: el test de panel.* se activo solo y PASA sin tocar su guarda — las tres claves ya
        son literales de Daemon.qml.
Task 9: XMLHttpRequest SIGUE siendo el camino para https. El veto es solo file://.

>>> PENDIENTE DE DAF3R 1: `dms ipc plugins enable claudeUsage` sigue fallando, y NO es por
>>> el codigo: el motor QML cacheo el "No such file or directory" de cuando faltaba
>>> Widget.qml. Ni `plugins reload` lo limpia. Se arregla con `dms restart`, que reinicia
>>> su barra, por eso no lo ejecuto ningun subagente. Demostrado con una copia integra en
>>> otro directorio: PLUGIN_ENABLE_SUCCESS y cero errores QML.
>>> PENDIENTE DE DAF3R 2: la locale de la sesion resuelve `en`, no `es` — el daemon solo
>>> pidio en.json. El i18n se eligio precisamente por el español. Decidir si se sigue la
>>> locale del sistema, se fuerza es, o se anade un ajuste.
Task 9: complete (commit 31f20c2), con el fix de file:// en curso sobre la tarea 8

>>> DECISION DE DAF3R (idioma) — para la TAREA 12:
>>> Anadir un SelectionSetting `language` con opciones Automatico / English / Espanol,
>>> por defecto "Automatico" (sigue la locale del sistema).
>>> Motivo: i18n.defaultLocale = "en_US.UTF-8" esta puesto A PROPOSITO en su
>>> configuration.nix, asi que seguir la locale a secas le condena al ingles para siempre
>>> — justo lo contrario de por que se conservo el i18n. Y forzar `es` romperia el plugin
>>> para cualquiera de fuera, siendo el repo publico.
>>> Implica: 2 claves nuevas en LOS DOS catalogos (settings.language.label y .description)
>>> y que el daemon recargue el catalogo al cambiar pluginData, cosa que ya sabe hacer.
>>> NOTA: en Noctalia esto nunca se resolvio — service.luau delegaba en noctalia.tr y el
>>> host elegia. Aquella implementacion tambien le habria salido en ingles.
>>> NO ROMPER: notify.bodyWithReset pasa la hora de reinicio como PARAMETRO, no
>>> concatenada, porque segun la lengua va en un sitio distinto de la frase. Con el
>>> selector eso pasa a ser util de verdad.

>>> DECISION DE DAF3R (pildora) — revisita de la TAREA 9:
>>> La pildora muestra LAS DOS ventanas: sesion (primary) + semanal (others[0]),
>>> cada una con su glifo y su porcentaje, la semanal atenuada.
>>> Problema que resuelve: hay un agujero entre 0 y 90% donde la semanal es INVISIBLE en
>>> la barra, porque hiddenWarning solo salta al cruzar el umbral. Con 84% real y umbral
>>> 90, el numero que decide su semana no aparecia en ninguna parte.
>>> DESCARTADO "gana el mayor porcentaje" (que era la conducta anterior a 5c6d242):
>>> siempre pierdes una de las dos, no se sabe cual estas viendo sin mirar el glifo, y
>>> cuando los porcentajes se acercan la pildora saltaria de ventana entre sondeos.
>>> NO SE TOCA: pickPrimary, la logica, los tests de ordering, ni la spec. Es cambio de
>>> presentacion. hiddenWarning sigue haciendo falta para los sublimites por modelo.
>>> CORRECCION MIA: en el primer analisis di por bueno el argumento de 5c6d242 ("la sesion
>>> solo asomaba cuando ya no hacia falta mirarla"). No se sostiene: sesion al 88% es
>>> justo cuando quieres verla. El caso malo era el inverso, sesion al 20%.
Task 9 (ampliacion): commit 6488721 — la pildora enseña las DOS ventanas.
        Ancho medido con su geometria real: 56px -> 109px (peor caso 124). Vertical
        49 -> 93px. Colores verificados volcando valores: primaria #e4e1e9, secundaria
        #b3e4e1e9 (alfa 0.702 sobre el MISMO rol, hue sin cambiar). Con aviso #b3f2b8b5.
        Los dos motivos de atenuacion NO se acumulan (0.49 seria ilegible).
        CAMBIO COLATERAL ACEPTADO: el tinte rojo del fondo salta si CUALQUIERA de las dos
        avisa, no solo la primaria.
        PENDIENTE DE DAF3R: others[0] es "la mas critica de las demas", NO "la semanal".
        Si un sublimite por modelo fuese mas critico saldria ese. Preguntado, sin responder.
Task 8: fix round 2/5 — commit dc5229c. NOTIFICACIONES REPETIDAS.
        MIS DOS HIPOTESIS ERAN FALSAS, refutadas con medidas:
        H1 (pluginService null en onCompleted) — sonda svcProbe demuestra que ya funciona
        un savePluginState+loadPluginState DENTRO del propio onCompleted.
        H2 (re-notifica cada sondeo) — primer sondeo notifs=1, todos los demas notifs=0.
        CAUSA REAL: saveNotifyState comparaba contra root.notifyState, la copia EN MEMORIA.
        En regimen son iguales cada vuelta, asi que savePluginState NO se volvia a llamar
        NUNCA durante la vida del daemon. Cualquier divergencia de la copia persistida se
        volvia permanente (fichero borrado, o escritura perdida en los 150ms de rebote al
        cerrar el shell). Arranque en frio -> lee NULL -> antirrebote vacio -> vuelve a
        avisar. UN AVISO REPETIDO POR CADA ARRANQUE DEL SHELL.
        El propio subagente lo provoco en la ronda 1 al borrar el fichero, y lo anoto como
        comportamiento correcto. Era el fallo y no lo vio.
        Verificado A/B sin red, con mtime forzada: la version nueva escribe, la vieja no.
        3 guardas silenciosas mas; 2 arregladas (load avisa y reintenta, save avisa),
        3 dejadas con justificacion. maybeStart() no sondea sin catalogo Y antirrebote,
        pero se rinde a los 10s y arranca en modo degradado con las notificaciones calladas.
        NO reprodujo el sintoma exacto de daf3r. Siguiente sospechoso si persiste:
        generaciones de daemon que sobreviven a una recarga (quickshell#898, documentado
        en el propio codigo de DMS como _daemonSpawnQueue).
        EFECTO COLATERAL: agoto la cuota de la API sondeando a 30s. El plugin quedara en
        status=stale source=cache hasta que el backoff lo recupere.
Task 9 (ranura fija): commit e8cc747. Suite 159 / 157 pass / 0 fail / 2 skip.
        Daemon.qml publica `weekly` (el limite con key weekly_all, o null). Widget.qml lo
        pinta en la segunda ranura. 7 casos de test nuevos.
        REGLA: la pildora muestra los dos PRIMARY_KINDS que logic.luau ya definia
        ({session, weekly_all}). Los sublimites por modelo van a hiddenWarning y al popout.
        Verificado con el escenario exacto que motivo el cambio: sesion 44, semanal 84
        normal, weekly_scoped:Fable 61 EN AVISO (o sea others[0] = Fable) -> la segunda
        ranura sigue siendo LA SEMANAL. Antes habria mostrado Fable.
        Ausencia: weekly null -> pildora de una ranura, 56px, sin separador colgando. NO
        cae a others[0] ni con others llena (verificado, 71px con el glifo de hiddenWarning).
        CASO QUE EL ENCARGO NO CUBRIA, resuelto bien: pickPrimary devuelve la semanal
        cuando no hay sesion, asi que publicarla tambien en `weekly` la pintaria dos veces.
        pickWeekly devuelve null ahi.
        Banco de pruebas sin red: compila el Daemon.qml real dentro del shell sin
        instanciarlo (status === Ready) e inyecta estados a mano. No gasto cuota.
NOTA: un subagente dejo claudeUsage [loaded]; daf3r lo habia desactivado a proposito.
      Restaurado a disabled. Hace falta `dms restart` para que la pildora viva enseñe esto.
Task 10: implementador acd07c0c78e8fa925 (opus), commit d3e3f9d. Suite 159/157/0 fallos/2 skip.
        panel.luau -> popoutContent. Un solo fichero tocado (Widget.qml). No necesito
        ningun campo nuevo del daemon, asi que 51ec4ae y dc5229c intactos.
        PARADO en el paso 2 (pasada manual de los 7 estados) — es 🖐️ de daf3r.
        HALLAZGO PARA LA TAREA 12: `show_scoped_limits` esconde `others` ENTERA, incluida
        la ventana semanal. Es lo que hacia panel.luau y se porto igual, pero la etiqueta
        del ajuste dice "sublimites por modelo", asi que apagarlo hace mas de lo que
        promete. Filtrar solo weekly_scoped* es una linea. Decidir en la 12.
        NO puede firmar: que el naranja del pie (dato viejo) no se confunda con el rojo
        del umbral sobre el tema real. Eso lo mira daf3r.

=== PARADA 2026-08-10 — 11 de 13 tareas ===
FUNCIONAL Y VERIFICADO EN VIVO por daf3r: pildora de dos ranuras (75 · 87), popout con
reinicios absoluto y relativo, semanal, sublimite Fable, creditos extra, pie de
procedencia y boton Refresh. Sondeo automatico 300s/60s. Respaldo por cache funcionando
(la API lleva rato en 429 por las sondas, y el pie lo dice: "Local cache · 5 min ago",
edad verificada independientemente = 5.7 min). El naranja del pie SI se distingue del
rojo del umbral sobre su tema — era lo unico que el subagente no podia firmar.
QUEDAN: tarea 11 (UsageRing), 12 (Settings.qml) y 13 (retirar Luau + Nix + README).
La 12 acumula 3 decisiones ya tomadas: el selector de idioma (Automatico/en/es), el test
que ata los defaults a las constantes de logic.js, y arreglar show_scoped_limits para que
filtre solo weekly_scoped* en vez de esconder `others` entera.
SIN REVISION FORMAL: tareas 3,4,5,6,8,9,10. Tests en verde e informes revisados por mi,
pero no pasaron por revisor independiente. Va al triaje de la revision final.
DEUDA ABIERTA: ToastService de DMS descarta toasts no-error con la cola llena (max 3) y
el antirrebote ya los da por enviados. Contradice §11. Sin decidir.
EL PLUGIN VIVE POR SYMLINK, no declarado en Nix todavia (eso es la tarea 13).

=== REANUDACION 2026-08-10 (tras reinicio de sesion) ===
Task 10: paso 2 🖐️ VERIFICADO por daf3r en vivo (ver la PARADA de arriba: los 7 estados
        del popout, el naranja del pie distinguible del rojo del umbral).
Task 10: complete (commit d3e3f9d, sin revision formal — va al triaje de la revision final)
Estado del plugin al reanudar: `dms ipc plugins list` -> claudeUsage [loaded]. Vive.
SIGUIENTE: tarea 11 (UsageRing). BASE = d3e3f9d.
Task 11: implementador a2364cd623a53d212 (sonnet), commit de51136, DONE_WITH_CONCERNS.
        components/UsageRing.qml traido de caelestia-plugins (donde nunca se instanciaba)
        y enchufado en la tarjeta destacada del popout. Suite 159/157/0/2, sin cambios.
Task 11: VERIFICADO que `import "components"` SI resuelve dentro de un plugin de DMS —
        sonda desechable con Qt.createComponent sobre el Widget.qml real: status=1 Ready,
        error=[]. No hizo falta el respaldo de componente inline.
Task 11: geometria del arco y codificacion por forma identicas al original byte a byte
        (openArc=270 con hueco=sesion, cerrado=semanal). openArc se lee de
        primary.key === "session", el mismo predicado de Daemon.qml:468. Daemon intacto.
Task 11: el anillo NO ata su propio `dimmed` a root.dimmed — la Column que lo envuelve ya
        atenua el bloque entero, y encadenar las dos atenuaciones bajaria del umbral legible.
Task 11: revision de tarea (sonnet) — spec ✅, calidad Aprobado con 1 menor.
Task 11: minor (deferred): ringSize 36 en el sitio de uso frente al 34 por defecto del
        original. Estetica no pedida por el brief. Triar en la revision final.
Task 11: OBSERVACION para daf3r: el anillo pinta el numero SIN `%`; las filas de abajo del
        popout SI lo llevan (fiel al original de Caelestia). Una linea si se quiere igualar.
Task 11: complete (commit de51136, review clean) — PASO 3 🖐️ PENDIENTE DE DAF3R: mirar el
        anillo en vivo (forma abierta=sesion / cerrada=semanal, color en aviso, animacion).
SIGUIENTE: tarea 12 (Settings.qml). BASE = de51136.
Task 12: implementador ae2dbd65ca0ef7aaa (opus), commit 2bc6ba3, DONE_WITH_CONCERNS.
        Settings.qml (299 lineas) + las 3 decisiones acumuladas. Suite 187/187 pass/0 fail/
        0 skip — los DOS skip que quedaban esperaban justo a Settings.qml y se activaron solos.
Task 12: BUG CAZADO POR SU SONDA EN VIVO antes de commitear — un FileView REUTILIZADO
        devuelve el texto del fichero ANTERIOR al cambiarle la ruta, incluso con
        blockLoading. El panel se habria quedado en ingles al elegir Español. Arreglado con
        una instancia por lectura (el patron que Daemon.qml ya usaba). Antes/despues medidos.
Task 12: ACEPTADO — «Auto» como etiqueta de la opcion por defecto, literal y sin traducir.
        Solo habia 2 claves nuevas autorizadas y una tercera haria falta para
        «Automatico»/«Automatic». «Auto» se escribe igual en los dos idiomas; las otras dos
        son endonimos (English, Español), que no se traducen nunca.
Task 12: ACEPTADO — onPluginDataChanged republica ante CUALQUIER cambio de ajuste, no solo
        el de idioma. Sin eso el paso 3 🖐️ no seria observable (la pildora no reaccionaria
        hasta 5 min despues). El revisor lo verifico camino a camino: NINGUNA ruta llega a
        la red, publish() recalcula nowMs (la antiguedad no se congela), y todos los caminos
        que publican pasan por publish(), asi que lastPublishArgs nunca queda por detras.
Task 12: revision de tarea (opus) — spec ✅ (brief + las 3 decisiones), calidad CON
        HALLAZGOS: 0 criticos, 1 importante, 7 menores.
Task 12: fix round 1/5 despachado — hallazgo importante: DankSlider emite
        sliderValueChanged en CADA onPositionChanged del raton, no al soltar, asi que
        bajar warn_threshold arrastrando son ~50 republicaciones completas en las 3
        instancias (daemon + 1 pildora por pantalla). Y es literalmente el paso 3 🖐️.
        Arreglo pedido: Timer de coalescencia ~150ms, sin perder la inmediatez ni empeorar
        el cambio de idioma (evento unico, no arrastre).
Task 12: minor (deferred) x7 — al triaje de la revision final:
        (2) Settings.qml:189 root.loadVariants() es codigo muerto: pluginService aun es null
            en ese onCompleted; quien carga las variantes es onPluginServiceChanged.
        (3) Settings.qml:154-171 catalogRetry — 17 lineas defensivas nunca ejercitadas y sin
            test; ademas `attempts` no se reinicia y el stop() rompe el binding de `running`
            para siempre, asi que la red de seguridad muere tras el primer agotamiento.
        (4) Settings.qml:139 relee en.json en CADA cambio de idioma; contradice el criterio
            que el propio autor escribe en Daemon.qml:329. Un `if (!fallbackCatalog)` lo cierra.
        (5) Settings.qml:120-131 readCatalog sin try/finally: si text() o safeParse lanzaran
            se filtra el FileView y catalogView queda no-null.
        (6) tests/settings.test.js:260 y :268 — DOS casos que NINGUNA mutacion de Settings.qml
            puede hacer fallar: uno no lee Settings.qml en absoluto (duplica i18n.test.js),
            el otro codifica ["en","es"] a mano en vez de leer found.body, asi que una cuarta
            opcion sin su translations/xx.json PASARIA. Los otros 18 casos si son solidos.
        (7) tests/settings.test.js — nadie comprueba que las DOS superficies usen
            pickLanguage, que es justo por lo que se pidio extraerla. Una asercion textual.
        (8) Daemon.qml:344-349 — carrera si el idioma cambia dos veces antes de que llegue la
            lectura (es->fr->es): activeLanguage se fija antes del callback. Inalcanzable a
            mano; un contador de generacion lo cierra.
Task 12: HALLAZGO OPERATIVO — Settings.qml NO se abre en el shell que corre ahora: el motor
        QML cacheo el listado del directorio al arrancar y da «File name case mismatch».
        No es del fichero (la misma copia en otro directorio carga perfecta, y un Item{}
        vacio creado ahora falla igual). Es el MISMO sindrome de la tarea 9. Hace falta
        `dms restart`, que ningun subagente ejecuta.
        >>> PENDIENTE DE DAF3R: `dms restart` antes de poder ver el panel Y el anillo de la 11.
Task 12: fix round 1/5 (1 addressed, 0 open — commit c0e5c61). onPluginDataChanged solo
        hace settingsSettle.restart(); un Timer de 150ms sin repeticion llama a
        applySettings(), que es el cuerpo que antes estaba inline. Un arrastre de 99 a 50
        pasa de ~50 republicaciones a UNA.
Task 12: re-revision (sonnet) — ADDRESSED, CERO roturas nuevas. Verificado: applySettings()
        no captura nada al armarse (gana el estado final, no el orden de llegada); la guarda
        !root.started NO se movio, asi que la maquina de arranque sigue intacta; ningun
        camino desde applySettings() llega a la red (ni poll(), ni applyCadence(), ni
        pollTimer); y el comentario incoherente esta corregido.
Task 12: minor (deferred) — la suite no puede ejercitar el Timer de 150ms: settings.test.js
        y pill-slots.test.js son escaneres estaticos de texto, QML no es ejecutable en node.
        Limitacion PREVIA del arnes, no empeorada por este diff.
Task 12: complete (commits de51136..c0e5c61, review clean tras 1 ronda)

=== HALLAZGOS DE LA TAREA 13 (recogidos antes de despachar) ===
La opcion de Nix existe y es `programs.dank-material-shell.plugins.<nombre>` con
{ enable, src, settings } — options.nix:88 del source de DMS. El modulo escribe
xdg.configFile."DankMaterialShell/plugins/<nombre>" (home.nix:120), o sea EL MISMO
CAMINO que ocupa hoy el symlink de desarrollo: declararlo lo sustituye por un enlace
de solo lectura al store.
>>> TRAMPA: el submodulo tiene un campo `settings`, y `managePluginSettings` se activa
>>> SOLO si algun plugin lo trae no vacio (home.nix:17-22). Si se activa, DMS escribe
>>> plugin_settings.json como symlink de solo lectura al store y EL PANEL DE AJUSTES DE
>>> LA TAREA 12 YA NO PODRIA GUARDAR. Hay que dejar `settings` sin poner. Es exactamente
>>> el mismo compromiso que dms.nix ya documenta para `settings = { }` del shell.
>>> CONSECUENCIA: declararlo en Nix TERMINA el desarrollo en vivo — cada cambio de codigo
>>> pasaria a exigir `nh os switch`. Por eso el orden importa frente a la revision final.
Task 13: PARTIDA POR DECISION DE DAF3R — solo pasos 1 y 4. Los pasos 2 y 3 (editar
        ~/nixos-config/dms.nix, quitar el symlink, nh os build/switch) quedan PROHIBIDOS
        hasta que cierre la revision final: declararlo en Nix deja el plugin de solo
        lectura en el store y cada arreglo exigiria un rebuild.
Task 13: implementador afa53d028d4c4691c (opus), commits c53d8be + 96f267e.
        Suite 187/187/0/0, identica antes del borrado, despues y tras la documentacion.
Task 13: revision de tarea (sonnet) — spec ✅, calidad APROBADO SIN HALLAZGOS.
        Verificado que dms.nix NO aparece en el diff, el symlink sigue vivo y no se corrio
        nh os. tests/fixtures/*.json conservados. `grep -rn luau` da ~40 aciertos, TODOS
        prosa; ninguno es require, ruta ni comando.
Task 13: VERIFICADA CONTRA EL CODIGO la afirmacion de seguridad del README — Daemon.qml
        :967-1005, el token solo aparece en el header Authorization; los 8 console.* del
        fichero no lo incluyen; publish() nunca lo recibe. El README no miente.
Task 13: ACEPTADO — description de plugin.json a ingles (decision de daf3r: manifiesto y
        README en ingles, el español vive en el catalogo, que es donde el i18n aporta).
        Ningun test lo aseveraba, asi que no quedo nada desincronizado.
Task 13: ACEPTADO — docs/img/*.png sacadas de los README (son del build de Noctalia y
        enseñan una pildora de UNA ventana; la de DMS enseña dos desde la tarea 9). Los
        ficheros NO se borran: esa ruta es el sitio de las capturas de DMS cuando se tomen.
Task 13: ACEPTADO — .gitignore reescrito a `.direnv/`. Su contenido entero eran las tres
        entradas de los modulos que generaba el runner de Luau, huerfanas al irse los .luau.
Task 13: DEUDA ANOTADA — tests/MANUAL.md reescrito contra DMS, pero su columna «Observado»
        es la pasada del 2026-08-08 sobre el build de LUAU. Falta una pasada manual completa
        de los siete estados sobre el build de DMS. Marcado como tal, sin fingirla.
Task 13: complete (commits c0e5c61..96f267e, review clean) — PASOS 2 Y 3 PENDIENTES DE DAF3R.

=== LAS 13 TAREAS COMPLETAS. Siguiente: revision final de rama. ===

=== REVISION FINAL DE RAMA (opus) — 6d072ce..96f267e, 28 commits ===
VEREDICTO: NO lista para fusionar tal cual. 1 critico, 3 importantes, 4 menores.
Contrastada funcion por funcion contra el Luau del historial y contra el DMS 1.5.3 que
corre ahora. Suite 187/187. Cero peticiones a la API.
CONFIRMADO OK: las 3 restricciones duras se cumplen (unico XHR en Daemon.qml:982, cero XHR
sobre file://, token solo en Daemon.qml:999 y fuera de los 8 console.warn y de publish()).
Fidelidad al Luau verificada en round, luaTruthy, el desempate por key, describeMoney con
currency="" y el #raw>0. Paridad de catalogos verificada aparte.
DESCARTADO UN RIESGO QUE CREIAMOS ABIERTO: PluginGlobalVar es un binding de SOLO LECTURA
sobre PluginService.globalVars, asi que las dos instancias por pantalla de Widget.qml NO
pueden pisar lo que publica el daemon.

CRITICO 1 — sesion caducada con modelo en memoria: publish("expired", lastModel) publica
CON datos, asi que hasNumber es true y se apagan TODAS las señales a la vez: sin glifo
key_off (Widget.qml:333/:409 son visible: !hasNumber), numeros a brillo completo (dimmed
solo mira "stale"), statusLabel NO se pinta (Widget.qml:830) aunque el daemon SI lo calcula
(Daemon.qml:641), y footerLabel vacio (publish no pasa source ni fetchedAt). Regresion del
tramo QML: widget.luau comprobaba status=="expired" ANTES que `if not u.primary`. Contradice
README.md:63, MANUAL.md caso 4 y la §9 de la spec. Misma ruta afecta al 401/403.
>>> DECISION DE DAF3R: colapsar al glifo. Una linea, restaura el original y hace verdad a
>>> la documentacion sin tocarla.

IMPORTANTE 2 — el techo de toasts es PEOR de lo anotado. ToastService.qml:58-63 descarta
por MENSAJE DUPLICADO *antes* de mirar maxQueueSize, y notify() manda siempre el mismo
resumen "Claude" con nivel warn. Con 3 limites cruzando en el mismo sondeo el tercero se
descarta en silencio y notificationsFor ya devolvio notified:true para los tres. El techo
efectivo es 2, no 3, y se alcanza con TRES limites, no con cuatro.
>>> DECISION DE DAF3R: un solo toast por sondeo, con los cuerpos unidos. Inmune a las DOS
>>> barreras sin depender de tripas de ToastService. Descartado el resumen distinto por
>>> limite: esquiva los duplicados pero sigue perdiendo el cuarto por maxQueueSize.

IMPORTANTE 3 — tests/settings.test.js:260 y :268 son INERTES (no debiles): el primero no
lee Settings.qml en absoluto, el segundo itera ["en","es"] a mano. Un cuarto idioma sin su
translations/fr.json PASARIA. Son el unico guardian del selector de idioma.
IMPORTANTE 4 — nadie ata las dos superficies a pickLanguage, que es por lo que se extrajo.

MENORES que SE QUEDAN (triados por el revisor): (5) Daemon.qml:298-303 un catalogo que
llega tras el guard de 10s se guarda pero no repinta; (6) Daemon.qml:890-897 pollStalled
no aborta el XHR; (7) Daemon.qml:1050-1057 en modo degradado se persiste notified sin
avisar — SE APROVECHA con el arreglo 2, que toca esa misma funcion; (8) el `%` del anillo.
TRIAJE DE LA DEUDA PREVIA: TODA se queda salvo los importantes 3 y 4. Motivos en el informe
del revisor. Notable: resolve() con || esta protegido por translations.test.js:123
(«ninguna traduccion vacia»), que hace el modo de fallo inalcanzable POR CONSTRUCCION;
y Settings.qml:189 loadVariants() NO es codigo muerto — PluginSettings.qml:40 la llama y
:43-53 la repite en onPluginServiceChanged, asi que cubre que el handler derivado pise al base.
NOTA DE PROCESO DEL REVISOR: los dos hallazgos serios estan en las tareas 8, 9 y 10 — justo
el tramo QML que nunca paso por revisor independiente. logic.js e i18n.js aguantan limpios.

=== RONDA DE ARREGLOS DE LA REVISION FINAL ===
Implementador a34ac26f8a4d664e3 (opus), commits 4f4e2be + ef15ac4 + 3fd14fd.
Suite 189/189 pass/0 fail/0 skip (venia de 187/187). qmlformat diff vacio en los 4 .qml;
qmllint 0 errores y los MISMOS 92 avisos Unqualified access preexistentes en Widget.qml.
4f4e2be — critico 1: hasNumber: !!primary && usageStatus !== "expired". Ademas el tinte
        rojo atado al mismo predicado y publishExpired() unica para las dos rutas (token
        vencido y 401/403), que pasa source/fetchedAt para que el pie deje de salir vacio.
        Verificado en vivo en 9 escenarios con DOS sondas gemelas —una con el codigo nuevo
        y otra con el de 96f267e— que instancian el Daemon.qml y el Widget.qml reales.
        La regresion sale clavada: antes expired = pildora de 113.2px con «44 · 84» a brillo
        pleno y pie vacio; ahora 18.0px con key_off, «Session expired…» y pie «8 min ago».
        Cero peticiones a la API (rutas locales a ficheros inexistentes).
ef15ac4 — importante 2: notifyBody + notify(lista), UN solo execDetached por sondeo con los
        cuerpos unidos por \n. Y saveNotifyState dentro de la guarda notifyStateLoaded.
3fd14fd — importantes 3 y 4 en tests/settings.test.js.
RE-REVISION (opus): los CUATRO ADDRESSED, CERO roturas nuevas en ningun grado.
        El re-revisor NO se fio del informe y rehizo las mutaciones por su cuenta sobre
        copias en scratchpad: cuarta opcion `fr` sin catalogo -> falla con el codigo nuevo
        (23 casos, 1 fail) y PASA con el de 96f267e (21/21), o sea que eran inertes de
        verdad. Y `pt_BR` CON catalogo tambien muerde el segundo caso.
        Cobertura 187->189 = exactamente +2, sin perdida (el caso sustituido cubre mas).
        Verificado que warning atado a hasNumber no altera nada: logic.js:394-421 hace que
        pickPrimary()===null implique pickWeekly()===null, asi que no hay estado alcanzable
        con primary null y secondary no null.
        Verificado que source/fetchedAt NO etiquetan mal el dato: footerLabelFor solo pone
        marcador con status "stale", y provenanceGlyph sale por !dimmed. Sin claves nuevas.
        Verificado que la guarda de saveNotifyState no deja nada sin persistir:
        notifyStateRetry hace stop() al degradarse, asi que no existe la secuencia
        «degradado -> cargado» que reimportaria un notified:true fantasma.
        SUB-MENOR anotado: la regex /value\s*:\s*"([^"]*)"/g de settings.test.js:271 no esta
        anclada y tambien casa el defaultValue: "auto". Hoy inocuo y el fallo posible seria
        un falso POSITIVO, nunca un falso verde.
VEREDICTO FINAL: LA RAMA ENTRA.

>>> PENDIENTE DE DAF3R, por orden:
>>> 1. `dms restart` — el motor QML compilo la version de las 17:02; la pildora que corre
>>>    NO tiene el anillo de la 11, ni el panel de la 12, ni ninguno de estos arreglos.
>>> 2. Los dos pasos 🖐️ sin firmar: el anillo del popout (tarea 11) y bajar el umbral con
>>>    el panel (tarea 12). Y la pasada manual de los 7 estados de tests/MANUAL.md sobre el
>>>    build de DMS, que su columna «Observado» sigue siendo del build de Luau.
>>> 3. Los pasos 2 y 3 de la tarea 13: pegar el bloque de claude-usage/README.md:143-163 en
>>>    ~/nixos-config/dms.nix (SIN el campo `settings`) y `nh os switch`.
