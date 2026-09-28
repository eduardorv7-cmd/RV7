# RV7: ThinkPad P14s Gen 1 AMD, seguridad de Windows y Brave Origin

Análisis de mi portátil (ThinkPad P14s Gen 1, AMD Ryzen 7 PRO 4750U y 40 GB de RAM) y scripts para revisarlo y mejorarlo.

| Archivo | Qué es |
|---|---|
| [`docs/analisis-p14s-gen1-amd.md`](docs/analisis-p14s-gen1-amd.md) | Análisis del portátil: para qué sirve en 2026, soporte, BIOS, puntos débiles y mejoras. |
| [`docs/seguridad-windows.md`](docs/seguridad-windows.md) | Cómo revisar la seguridad de Windows, prioridades para este modelo y problemas del workflow de RDP de este repositorio. |
| [`docs/brave-origin.md`](docs/brave-origin.md) | Brave Origin en Mac y Windows, revisión de seguridad de `brave-origin-for-windows` y alternativas seguras. |
| [`windows/Auditoria-Seguridad.ps1`](windows/Auditoria-Seguridad.ps1) | Auditoría de seguridad y hardware de Windows 10/11. **Solo lectura**; genera un informe HTML y otro de texto. |
| [`windows/Brave-Minimalista.ps1`](windows/Brave-Minimalista.ps1) | Aplica al Brave normal las 16 políticas que usa Brave Origin (y `-Revertir` las quita). |
| [`mac/Brave-Minimalista.mobileconfig`](mac/Brave-Minimalista.mobileconfig) | Las mismas políticas para Brave en macOS. |

## Uso rápido (Windows)

En PowerShell, dentro de la carpeta del repositorio descomprimido:

```powershell
# 1) Análisis de seguridad (pedirá permisos de administrador)
Unblock-File .\windows\*.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Auditoria-Seguridad.ps1

# 2) Opcional: Brave "minimalista", como Brave Origin, gratis
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Brave-Minimalista.ps1
```

> **Este repositorio es público.** No subas aquí los informes del análisis: contienen nombres de usuario y programas instalados. El `.gitignore` ya los excluye.
