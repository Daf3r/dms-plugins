--!strict
-- Lógica pura del plugin claude-usage. Traducción de logic.js (Caelestia).
--
-- REGLA: este fichero no llama a NINGUNA API host. Ni noctalia.*, ni ui.*.
-- Lo que necesite del entorno se le pasa por parámetro. Es lo que permite
-- correr la suite con `luau` sin levantar el shell.
--
-- Luau no trae JSON ni Date: las fechas viajan como epoch en milisegundos.

local M = {}

-- Una severidad que no conocemos se trata como la más grave: si Anthropic
-- añade un estado nuevo, preferimos un falso rojo a un silencio.
M.SEVERITY_RANK = { normal = 0, warning = 1, critical = 2 }

return M
