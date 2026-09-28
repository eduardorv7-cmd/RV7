# Brave Origin: Mac, Windows y el proyecto «brave-origin-for-windows»

*Revisado el 28/09/2026. Código analizado: [`aivrar/brave-origin-for-windows@e9ceb69`](https://github.com/aivrar/brave-origin-for-windows/tree/e9ceb69cd4b06c24d7ec131fbdcfff426d378476) y su lanzador [`aivrar/portable-linux-in-a-box@0d03820`](https://github.com/aivrar/portable-linux-in-a-box/tree/0d03820f443e74b34fae5b604a1924157ba80505).*

## Respuesta corta

| Pregunta | Respuesta |
|---|---|
| ¿Se puede instalar Brave Origin en Mac? | **Sí, oficialmente.** Desde el 4 de junio de 2026 existe para Windows, macOS, Linux y Android (iOS anunciado). En Mac y Windows cuesta **59,99 $ en un único pago** y una compra sirve para todos tus dispositivos (la prensa habla de hasta 10). En Linux es gratis. |
| ¿Funciona `brave-origin-for-windows` en Mac? | **No.** Depende de WSL, que solo existe en Windows. Lo dice su propio README: *«macOS has no WSL»*. |
| ¿Lo instalo en mi Windows? | **No lo recomiendo como navegador de uso diario.** Ejecuta Brave **como root y sin el sandbox de Chromium**, dentro de un Linux que puede leer y modificar tus archivos de Windows. Detalles abajo. |
| ¿Hay una alternativa gratis y segura? | **Sí:** el Brave normal con las **mismas 16 políticas que aplica Brave Origin**. Para Windows usa [`windows/Brave-Minimalista.ps1`](../windows/Brave-Minimalista.ps1) y para Mac [`mac/Brave-Minimalista.mobileconfig`](../mac/Brave-Minimalista.mobileconfig). |

No he instalado nada en tu PC: trabajo desde un servidor en la nube sin acceso a tu equipo. Abajo tienes los pasos para hacerlo tú.

## Qué es Brave Origin

Es la versión «minimalista» de Brave. Quita Leo (IA), Brave News, Rewards y los anuncios de Brave, Speedreader, Talk, Tor, el VPN, la Wallet y los dominios Web3, la Wayback Machine, Web Discovery, Playlist y la telemetría (P3A y el ping diario de uso). Mantiene Brave Shields, que es el bloqueador de anuncios y rastreadores.

Tiene dos modos:

- **App independiente:** esas funciones se eliminan al compilar; no existen en el programa.
- **Modo actualización** del Brave que ya tienes: las funciones siguen dentro, pero Origin las apaga **mediante políticas del navegador**.

El segundo punto lo he comprobado en el código de Brave. El fichero [`brave_origin_service_factory.cc`](https://github.com/brave/brave-core/blob/341f93e7ad39ac8319ef163372288c1ee35db6fe/browser/brave_origin/brave_origin_service_factory.cc#L117-L247) define qué preferencias controla Origin y con qué valor. Cada una corresponde a una política oficial y documentada de Brave ([`brave_simple_policy_map.h`](https://github.com/brave/brave-core/blob/341f93e7ad39ac8319ef163372288c1ee35db6fe/browser/policy/brave_simple_policy_map.h)). Son estas 16:

| Política | Valor en Origin | Qué apaga |
|---|---|---|
| `BraveRewardsDisabled` | 1 | Rewards y anuncios de Brave |
| `BraveWalletDisabled` | 1 | Wallet (cripto, dominios Web3) |
| `BraveVPNDisabled` | 1 | Brave VPN |
| `BraveAIChatEnabled` | 0 | Leo (asistente de IA) |
| `BraveLocalAIEnabled` | 0 | IA local en el equipo |
| `BraveNewsDisabled` | 1 | Brave News |
| `BraveTalkDisabled` | 1 | Brave Talk |
| `TorDisabled` | 1 | Ventanas privadas con Tor |
| `BraveSpeedreaderEnabled` | 0 | Speedreader |
| `BravePlaylistEnabled` | 0 | Playlist |
| `BraveWaybackMachineEnabled` | 0 | Wayback Machine |
| `BraveWebDiscoveryEnabled` | 0 | Web Discovery Project |
| `BraveP3AEnabled` | 0 | Analítica de uso privada (P3A) |
| `BraveStatsPingEnabled` | 0 | Ping diario de uso |
| `EmailAliasesEnabled` | 0 | Alias de correo |
| `PsstEnabled` | 0 | Ajuste automático de privacidad por web |

## Brave Origin en Mac: opciones

| Opción | Coste | Seguridad | Cómo |
|---|---|---|---|
| **Brave Origin oficial**, app independiente | 59,99 $ (pago único) | La mejor: app firmada por Brave y sin esas funciones | [brave.com/origin](https://brave.com/origin/) |
| **Brave normal + perfil `Brave-Minimalista.mobileconfig`** | Gratis | La misma que Brave normal (sandbox, actualizaciones automáticas) | Ver abajo |
| `brave-origin-for-windows` | — | — | No funciona en macOS |
| Brave Origin para Linux en una máquina virtual (UTM) | Gratis | Aceptable, pero incómodo y lento | No merece la pena |

**Instalar el perfil en Mac:**

1. Instala Brave normal desde [brave.com/download](https://brave.com/download/).
2. Descarga [`mac/Brave-Minimalista.mobileconfig`](../mac/Brave-Minimalista.mobileconfig) y haz doble clic.
3. Abre **Ajustes del Sistema → General → Gestión de dispositivos**. En versiones anteriores está en *Privacidad y seguridad → Perfiles*. Allí aparece «Brave minimalista»: pulsa **Instalar** e introduce tu contraseña.
4. Cierra Brave del todo (⌘Q) y vuelve a abrirlo. En `brave://policy` deberías ver las 16 políticas.
5. Para quitarlo, selecciona el perfil en esa misma pantalla y pulsa **−**.

Si compras Brave Origin, la misma licencia te sirve también en Windows (el P14s). Además, apoyas el desarrollo de Brave.

## Revisión de seguridad de `brave-origin-for-windows`

### Cómo funciona

`Brave.exe` es un lanzador compilado a partir de `portable-linux-in-a-box`. Hace lo siguiente:

1. Importa un Ubuntu 24.04 mínimo como distribución de WSL llamada `linbox-Brave`.
2. Instala TigerVNC, noVNC y openbox.
3. Descarga la última `brave-origin-nightly` (.deb) de los *releases* oficiales de Brave en GitHub.
4. La ejecuta dentro de un servidor VNC y te la muestra en una ventana WebView2.

Es ingenioso, pero tiene estos problemas:

| Gravedad | Problema | Evidencia |
|---|---|---|
| **Alta** | **Brave se ejecuta como root y con `--no-sandbox`.** El sandbox de Chromium es lo que contiene a una web maliciosa que aprovecha un fallo del navegador; sin él, un solo fallo da control total de ese Linux. El README lo justifica con que WSL no concede `CAP_SYS_ADMIN`. En realidad, `--no-sandbox` hace falta porque lo ejecuta como root: Chromium no arranca como root con el sandbox activo. Con un usuario normal, el sandbox suele funcionar en WSL2. | [`start.sh` L197-L208](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/start.sh#L197-L208); usuario por defecto uid 0 en [`wsl_backend.c` L315](https://github.com/aivrar/portable-linux-in-a-box/blob/0d03820f443e74b34fae5b604a1924157ba80505/src/linux/wsl_backend.c#L315) |
| **Alta** | **Ese Linux no está aislado de tu Windows.** La distribución tiene activada la *interop* (puede ejecutar `powershell.exe` como tú) y el montaje de `C:`. Además, `/opt/app` es un enlace a la carpeta de Windows donde descomprimiste la app. Un atacante que entre por el navegador podría leer o cifrar tus archivos, o reemplazar `Brave.exe`, que tú volverías a ejecutar. El README la llama *«disposable VM»*, pero no es un aislamiento real. | [`wsl_backend.c` L32-L36](https://github.com/aivrar/portable-linux-in-a-box/blob/0d03820f443e74b34fae5b604a1924157ba80505/src/linux/wsl_backend.c#L32-L36); [`main.c` L694-L709](https://github.com/aivrar/portable-linux-in-a-box/blob/0d03820f443e74b34fae5b604a1924157ba80505/src/main.c#L694-L709) |
| **Media** | **Una API que ejecuta cualquier comando como root.** `POST /api/exec` escucha en `0.0.0.0:9612` y la protege un token. Pero ese token se escribe dentro de `index.html`, que websockify sirve sin contraseña en `0.0.0.0:9611`, junto a un VNC también sin contraseña. Quien llegue al puerto 9611 puede ver y controlar tu navegador y ejecutar comandos. Por defecto solo llega tu propio PC (red NAT de WSL). Con `networkingMode=mirrored` y el firewall de Hyper-V abierto, llegaría también tu red local. | [`control.py` L308-L336](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/control.py#L308-L336), [L451](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/control.py#L451); [`start.sh` L108-L128](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/start.sh#L108-L128), [L237](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/start.sh#L237) |
| **Media** | **Binarios que no se pueden verificar.** `Brave.exe`, `webview.dll` y `ubuntu-base.tar.gz` no están en el repositorio: solo vienen en el zip del autor, un desarrollador individual. No hay forma de comprobar que coinciden con el código publicado. | [`.gitignore`](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/.gitignore) y README («Developing») |
| **Media** | **Es la versión Nightly**, una versión de pruebas diaria menos probada que la estable. | [`setup.sh` L94-L105](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/setup.sh#L94-L105) |
| Uso | Pasa por VNC y sin GPU (`--disable-gpu`): el vídeo va a saltos. No se integra con Windows: no funcionan las passkeys con Windows Hello ni las notificaciones, y no puede ser el navegador predeterminado. Cada vez que se abre borra las pestañas de la sesión anterior, y las descargas se quedan dentro de Linux. | [`start.sh` L145-L208](https://github.com/aivrar/brave-origin-for-windows/blob/e9ceb69cd4b06c24d7ec131fbdcfff426d378476/start.sh#L145-L208) |

**A su favor:** es MIT y el código es legible. Descarga Brave de la fuente oficial, la API usa un token distinto en cada arranque y se desinstala limpiamente con `wsl --unregister`.

**Veredicto:** sirve para curiosear Brave Origin, pero no para entrar en tu banco, tu correo o tus cuentas. Para eso es mejor Brave Origin oficial o Brave normal con las políticas.

## Opción recomendada en Windows (gratis): Brave normal + políticas

En PowerShell, desde la carpeta del repositorio:

```powershell
winget install --id Brave.Brave -e        # si aún no tienes Brave
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Brave-Minimalista.ps1
```

- Como administrador, se aplica a todos los usuarios; si no, solo a tu usuario.
- `-Mantener VPN,Tor` conserva las funciones que elijas.
- `-Revertir` lo deshace.
- Comprueba el resultado en `brave://policy`. Brave mostrará *«Tu organización administra el navegador»*: es normal cuando hay políticas.

Diferencia con Origin: con las políticas, esas funciones siguen dentro del programa, apagadas y ocultas. En la app independiente de Origin no existen.

## Si aun así quieres probar `brave-origin-for-windows`

1. **Requisitos:** Windows 10 2004 o posterior, u 11. WSL2: ejecuta `wsl --install` en PowerShell como administrador y reinicia. WebView2 ya viene en Windows 11. Unos 1,5 GB libres.
2. Descarga `Brave.zip` de [la última versión publicada](https://github.com/aivrar/brave-origin-for-windows/releases/latest).
3. Antes de abrirlo: clic derecho → **Analizar con Microsoft Defender**. Opcionalmente, sube `Brave.exe` a [VirusTotal](https://www.virustotal.com/). Como no está firmado, SmartScreen te avisará.
4. Descomprímelo en una carpeta propia, por ejemplo `C:\Apps\BraveOrigin` (no en Documentos ni en el Escritorio), y ejecuta `Brave.exe`. La primera vez tarda unos 5 minutos.
5. **Refuerzo recomendado** tras el primer arranque: impide que ese Linux ejecute programas de Windows. Los scripts de la app no los usan, así que no debería romper nada.
   ```powershell
   wsl -d linbox-Brave -u root -- sh -c "printf '\n[interop]\nenabled=false\nappendWindowsPath=false\n' >> /etc/wsl.conf"
   wsl --terminate linbox-Brave
   ```
   El montaje de `C:` no se puede quitar, porque la app lo necesita para leer su carpeta.
6. No actives `networkingMode=mirrored` en `.wslconfig` ni abras el firewall de Hyper-V para WSL.
7. No inicies sesión en cuentas importantes ni guardes contraseñas en él.
8. **Desinstalar:** cierra la app, ejecuta `wsl --unregister linbox-Brave` y borra la carpeta.

El script [`windows/Auditoria-Seguridad.ps1`](../windows/Auditoria-Seguridad.ps1) detecta si esta app está instalada y te lo indica en el informe.

## Fuentes

- Brave: [anuncio de Brave Origin](https://brave.com/blog/brave-origin/), [página de Origin](https://brave.com/origin/), [¿Qué es Brave Origin?](https://support.brave.app/hc/en-us/articles/38561489788173-What-is-Brave-Origin), [precio y licencia en X](https://x.com/brave/status/2062582955000664263).
- Prensa: [gHacks](https://www.ghacks.net/2026/06/05/brave-software-launches-origin-a-paid-bloat-free-version-of-brave-without-crypto-ai-and-rewards-features/), [Linuxiac (gratis en Linux)](https://linuxiac.com/brave-gives-linux-users-its-stripped-down-origin-browser-for-free/), [Tech Times (funciones eliminadas y 10 dispositivos)](https://www.techtimes.com/articles/317922/20260606/brave-origin-browser-launches-60-compile-out-build-removes-leo-tor-wallet.htm), [Privacy Guides](https://www.privacyguides.org/news/2026/06/07/brave-launches-paid-minimalist-brave-origin-browser/).
- Código: [brave-core (definición de políticas)](https://github.com/brave/brave-core/tree/341f93e7ad39ac8319ef163372288c1ee35db6fe/components/policy/resources/templates/policy_definitions/BraveSoftware).
- WSL y el firewall de Hyper-V: [Microsoft Learn](https://learn.microsoft.com/en-us/windows/wsl/networking).
