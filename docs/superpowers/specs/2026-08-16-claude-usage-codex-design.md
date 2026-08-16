# Diseño — Codex en `claude-usage`

Fecha: 2026-08-16 · Estado: implementación y activación local validadas; publicación pendiente

## Objetivo

Extender el plugin `claude-usage` de DankMaterialShell para mostrar también los
límites de uso de Codex, sin cambiar el contrato existente de Claude ni hacer que
la ausencia de una sesión Codex oculte el uso de Claude.

## Hechos comprobados

- En esta máquina está instalado `codex-cli 0.147.0` y `codex login status` informa
  `Logged in using ChatGPT`.
- El propio binario de Codex y su fuente pública de la misma versión usan el endpoint
  privado `GET https://chatgpt.com/backend-api/wham/usage` para una sesión ChatGPT.
  La ruta equivalente del backend Codex es `/api/codex/usage`.
- La autenticación usa el `access_token` de `~/.codex/auth.json` en la cabecera
  `Authorization: Bearer [REDACTED]` y, si existe, `tokens.account_id` en
  `ChatGPT-Account-Id`.
- Una petición de solo lectura realizada sin imprimir credenciales devolvió HTTP 200
  con `plan_type`, `rate_limit.primary_window`, `additional_rate_limits`, `credits`
  y `spend_control`.
- El endpoint no es una API pública documentada. Puede cambiar o desaparecer; el
  plugin debe fallar cerrado y degradar a dato viejo o a ausencia, nunca inventar un
  porcentaje.

## Decisión de producto

1. Claude conserva sus dos ventanas actuales en la barra.
2. Codex añade una tercera unidad compacta en la barra: su ventana principal. Las
   ventanas adicionales se señalan con el indicador de aviso y aparecen completas
   en el popout.
3. El popout añade un bloque independiente de Codex con ventana principal,
   secundaria, límites adicionales, plan y créditos cuando el backend los entrega.
4. Codex se detecta automáticamente. Si falta `~/.codex/auth.json`, no hay token
   ChatGPT, o el usuario está autenticado solo con API key, el bloque Codex no ocupa
   espacio y Claude sigue funcionando.
5. El umbral de aviso, la inversión «restante/consumido» y la cadencia existentes
   se aplican a ambos proveedores. Las notificaciones de Codex quedan fuera de esta
   primera integración para no mezclar antirrebote ni titulares de Claude sin una
   decisión específica.

## Seguridad y fallos

- `~/.codex/auth.json` es solo lectura.
- El token solo se inserta en la cabecera del XHR de Codex; nunca entra en logs,
  estado publicado, textos de error o cachés del plugin.
- Un 401/403 produce estado caducado para Codex; un error de transporte, 5xx, 429 o
  JSON inválido conserva el último dato de Codex en memoria como obsoleto, si existe.
- Claude y Codex tienen estados y fallos independientes, aunque comparten un ciclo
  de sondeo y la decisión de cadencia.
- El estado global sigue siendo un único objeto ya calculado y traducido; la UI no
  interpreta el payload del backend.

## Fuera de alcance

- Consumo histórico de tokens de Codex.
- Uso de la API de OpenAI autenticada con `OPENAI_API_KEY`.
- Redención de créditos o acciones de escritura contra el backend.
- Notificaciones específicas de Codex.
- Cambiar el nombre de la carpeta o el `id` `claudeUsage` del plugin.
