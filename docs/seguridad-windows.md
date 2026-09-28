# Seguridad de tu Windows (ThinkPad P14s Gen 1 AMD)

*Situación a 28/09/2026.*

Trabajo desde un servidor en la nube y **no tengo acceso a tu portátil**, así que no puedo analizarlo directamente. En su lugar hay un script que lo revisa en tu PC y genera un informe en español: [`windows/Auditoria-Seguridad.ps1`](../windows/Auditoria-Seguridad.ps1). **Solo lee la configuración; no cambia nada.**

## 1. Ejecutar el análisis (unos 2 minutos)

1. Descarga el repositorio: botón verde **Code → Download ZIP** en GitHub. Descomprímelo, por ejemplo en `C:\RV7`.
2. Abre **PowerShell**: clic derecho en Inicio → *Terminal*.
3. Ejecuta:
   ```powershell
   cd C:\RV7
   Unblock-File .\windows\Auditoria-Seguridad.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Auditoria-Seguridad.ps1
   ```
4. Acepta la ventana de permisos (UAC). Hacen falta para leer BitLocker, Secure Boot y el TPM.
5. Al terminar se abre el informe HTML y se guarda también un `.txt` en el Escritorio.

`-ExecutionPolicy Bypass` solo afecta a esa ejecución; no cambia la configuración de tu PC. Si quieres que te ayude con el resultado, pega aquí el contenido del `.txt`. **No lo subas a este repositorio: es público** y el informe incluye nombres de usuario y programas. El `.gitignore` ya lo excluye por si acaso.

## 2. Qué revisa

| Área | Comprobaciones |
|---|---|
| Sistema y actualizaciones | Versión de Windows y fecha de fin de soporte, último parche instalado, servicio de Windows Update (y si se ha bloqueado con programas de «optimización»), reinicio pendiente y aplicaciones desactualizadas (winget). |
| Antivirus | Defender o el antivirus instalado, firmas, protección contra alteraciones, protección en la nube, bloqueo de aplicaciones no deseadas, **exclusiones** (el malware se esconde ahí), amenazas de los últimos 30 días y SmartScreen. |
| Cifrado y arranque | TPM (fTPM de AMD o chip aparte), **BitLocker** (y si pide PIN), Secure Boot y **sus certificados de 2023**, VBS/integridad de memoria, protección de LSA y lista de drivers vulnerables. |
| Red | Firewall, redes públicas o privadas, uso compartido en redes públicas, SMBv1, Escritorio remoto, programas que aceptan conexiones, archivo hosts, proxy y DNS. |
| Cuentas | UAC, cuenta de administrador para el día a día, Administrador integrado e Invitado, cuentas sin contraseña, bloqueo por intentos fallidos, inicio de sesión automático con contraseña guardada y WDigest. |
| Programas | Arranque automático (firmas y rutas sospechosas), tareas programadas con comandos típicos de malware, servicios sin firma o con rutas sin comillas, programas de control remoto (AnyDesk, TeamViewer…), PowerShell 2.0 y distribuciones de WSL (incluida `brave-origin-for-windows`). |
| Hardware y firmware | Versión de la BIOS (en tu modelo, compara con la 1.53 / R1BET84W), contraseñas y ajustes de la BIOS Lenovo (**AMD Memory Guard**, protección contra rollback), memoria (velocidad y configuración asimétrica), salud y desgaste del SSD, espacio libre y salud de la batería. |

## 3. Prioridades para tu P14s Gen 1 AMD, aunque todavía no hayas pasado el script

Por orden de importancia:

1. **Actualiza a Windows 11 25H2.** La 24H2 Home/Pro deja de recibir parches el **13/10/2026**, igual que las ESU de Windows 10. Ve a Configuración → Windows Update.
2. **Actualiza la BIOS** a la 1.53 (R1BET84W) o posterior con Lenovo Commercial Vantage. Trae los parches de AMD (Zenbleed, SinkClose, EntrySign) y de LogoFAIL.
3. **Cifra el disco y pon un PIN de arranque largo.** BitLocker con TPM + PIN mejorado tipo frase de 15 a 20 caracteres. Tiene que ser largo por el ataque faulTPM a los TPM integrados de AMD Zen 2, que permite probar PINs sin límite ([detalles](analisis-p14s-gen1-amd.md#seguridad-del-hardware-cómo-aprovecharla)). Guarda la clave de recuperación fuera del PC.
4. **Activa todo en «Aislamiento del núcleo»** (Seguridad de Windows → Seguridad del dispositivo): integridad de memoria, protección de LSA y lista de bloqueados de drivers vulnerables.
5. **Revisa los certificados de Secure Boot de 2023.** El script te dice si ya los tienes; si faltan, basta con Windows Update y la BIOS al día.
6. **Microsoft Defender basta: no instales otro antivirus.** Comprueba que estén activadas la protección contra alteraciones, la protección en la nube y el bloqueo de aplicaciones no deseadas.
7. **Usa una cuenta estándar para el día a día** y Windows Hello con la huella en lugar de la contraseña.
8. **Mantén tus programas al día:** `winget upgrade --all`.
9. **Haz copias de seguridad** (OneDrive o similar más un disco externo desconectado). Son tu protección contra el ransomware.
10. **Protege tus cuentas:** verificación en dos pasos o passkey en la cuenta Microsoft y el correo, y un gestor de contraseñas.
11. En la BIOS: activa **AMD Memory Guard**. La contraseña de supervisor es opcional; si la olvidas, hay que cambiar la placa.

## 4. Tu «Windows» en GitHub Actions (el workflow de este repositorio)

Este repositorio tiene [`.github/workflows/main.yml`](../.github/workflows/main.yml). Arranca una máquina Windows de GitHub, activa el Escritorio remoto, crea el usuario `RDP` como administrador y la conecta a tu red Tailscale. **Todavía no se ha ejecutado nunca** (0 ejecuciones), así que no se ha filtrado nada. Aun así, tiene problemas:

| Problema | Por qué importa |
|---|---|
| **Escribe la contraseña del usuario `RDP` en el log** (`Write-Host "Password: ..."`) | **El repositorio es público**: cualquiera puede leer los logs de sus Actions. |
| Desactiva NLA (`UserAuthentication=0`) y pone `SecurityLayer=0` | RDP sin autenticación previa ni TLS. Tailscale cifra el tráfico, pero cualquier equipo de tu tailnet llega directamente a la pantalla de inicio de sesión. |
| Abre el puerto 3389 a cualquier origen y el usuario es administrador | Aumenta el daño si alguien consigue la contraseña. |
| `timeout-minutes: 3600` | Los runners de GitHub cortan los trabajos a las **6 horas**. No tendrás 60 horas. |
| Uso como escritorio remoto | Los [términos de GitHub para Actions](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features#actions) no permiten usar los runners para fines ajenos a compilar, probar o publicar el software del repositorio. **Pueden suspender tu cuenta.** |

Además, esa máquina se borra al terminar: lo que instales en ella desaparece. **Mi recomendación es no usarlo.** Para probar programas sin riesgo en tu propio portátil, usa **Windows Sandbox** (Windows Pro: «Activar o desactivar características de Windows» → *Espacio aislado de Windows*). Es gratis y se borra al cerrarlo.

No he tocado el workflow. Si quieres, lo borro o lo corrijo: quitar la contraseña del log, activar NLA y limitar el firewall.
