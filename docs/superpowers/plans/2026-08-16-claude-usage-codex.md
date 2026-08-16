# Plan — integrar uso de Codex en `claude-usage`

> Plan ejecutable para el cambio de 2026-08-16. El switch de NixOS queda fuera;
> commit y push requieren petición explícita y validación visual previa.

## Contrato

- Mantener `usage.primary`, `usage.weekly`, `usage.others` y todos los campos que
  consume la vista actual de Claude.
- Añadir `usage.codex` como estado independiente, ya decorado y traducido.
- Mantener `logic.js` sin APIs de QML/Quickshell y en ES5 estricto.
- No imprimir ni persistir tokens.

## Pasos

- [x] Inspeccionar repo, instrucciones, rama y diff local.
- [x] Verificar `codex-cli`, su autenticación local y el endpoint actual del propio
      Codex CLI; redactar el contrato y sus riesgos.
- [x] Añadir a `logic.js` el parser de `~/.codex/auth.json`, la normalización del
      payload de `/wham/usage` y helpers de selección/orden/formato.
- [x] Añadir fixture y pruebas de credenciales, ventanas, límites adicionales,
      créditos, respuestas incompletas y resets inválidos.
- [x] Integrar en `Daemon.qml` dos cadenas de sondeo independientes, con una única
      guarda de ciclo y cadencia compartida.
- [x] Extender `Widget.qml`, traducciones y documentación para la tercera unidad
      compacta y el bloque Codex del popout.
- [x] Ejecutar la suite completa, comprobar que una mutación relevante rompe las
      pruebas, validar sintaxis/QML disponible y revisar secretos/diff.
- [x] Verificar la tercera unidad y el popout en DMS usando el árbol local
      temporal; el store queda pendiente de `commit → push → flake update → nh os switch`.

## Verificación

```bash
TZ=Europe/Madrid node --test claude-usage/tests/*.test.js
nix develop ~/nixos-config#dms-plugins -c fish claude-usage/tests/run-js.fish

git diff --check
git status --short --branch
```

Resultado: 201/201 tests JS pasan mediante el devshell, la mutación de
`codexResetMs` falla como debe, `qmlformat`/`qmllint` aceptan ambos QML y la
respuesta real del endpoint devolvió HTTP 200 con las claves esperadas sin
imprimir credenciales. En DMS, con el symlink local temporal, el flujo real
terminó en `auth=ok → HTTP 200 → 2 límites normalizados`; el reinicio del
servicio fue necesario para invalidar la caché del módulo JavaScript QML. La
La confirmación visual del popout fue realizada por el usuario tras activar el
árbol local; la suite JS y el parser QML no demuestran por sí solos el layout.
