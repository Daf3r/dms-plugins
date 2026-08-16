# Ledger — Codex en `claude-usage`

Fecha de inicio: 2026-08-16 · repo: `~/Projects/dms-plugins`

## Evidencia inicial

- Árbol limpio en `main`, alineado con `origin/main`, antes de tocarlo.
- `codex-cli 0.147.0`; autenticación ChatGPT válida.
- El endpoint privado actual responde en esta cuenta con HTTP 200 a
  `https://chatgpt.com/backend-api/wham/usage`.
- La respuesta observada contiene una ventana principal de 7 días, límites
  adicionales, créditos y control de gasto. No se ha incorporado ningún valor
  de esa cuenta a fixtures ni documentación.

## Decisiones

- Se conserva el nombre del plugin por compatibilidad con NixOS/DMS.
- Codex no se convierte en una segunda instancia del daemon: comparte el ciclo y
  publica dentro del objeto global existente, para no crear otro sondeo por
  pantalla.
- La ausencia de Codex es un estado normal, no un error del plugin de Claude.
- Las notificaciones específicas de Codex quedan deliberadamente fuera de la primera pasada; sus límites sí participan en el aviso visual y la cadencia compartida.

## Evidencia de implementación

- `logic.js` normaliza las dos ventanas base, límites adicionales, plan y
  créditos; los casos inválidos no inventan resets ni porcentajes.
- `Daemon.qml` lee Codex después de Claude dentro del mismo ciclo, con
  `codexFailures`/`codexStatus` separados y sin publicar el token.
- `Widget.qml` conserva las dos unidades de Claude y añade una unidad compacta
  de Codex más un bloque independiente en el popout.
- Suite completa: 201/201; contrato Codex: 12/12; JSON, `git diff --check`,
  `qmlformat` y `qmllint`: correctos. La mutación de `codexResetMs` fue
  detectada con código 1.
- La comprobación real del endpoint devolvió HTTP 200 y las claves
  `rate_limit`, `additional_rate_limits`, `credits` y `plan_type`; ningún valor
  de cuenta se guardó en el repo.
- Para probar el flujo en DMS se guardó el symlink Nix como
  `~/.config/DankMaterialShell/plugins/claude-usage.nix-managed-20260816T162212Z`
  y se activó temporalmente el symlink al repo local. Tras reiniciar
  `dms.service`, el journal confirmó `auth=ok`, HTTP 200 y 2 límites Codex
  normalizados. El reload aislado no bastaba porque el motor QML conservaba el
  módulo `logic.js` cacheado.
- Se corrigió además el orden de entrega de `FileView`: el callback se ejecuta
  antes de destruir la instancia; el contrato quedó cubierto por una prueba.

## Estado de cierre

- El usuario confirmó visualmente la tercera unidad y el bloque Codex del popout
  después de activar temporalmente el árbol local.
- La publicación del repositorio queda autorizada; aún no se ha ejecutado el
  commit ni el push en este punto.
- Si el usuario quiere activarlo en NixOS, hacer después `commit → push → nix
  flake update dms-plugins → nh os switch`, con verificación de la sesión real.
