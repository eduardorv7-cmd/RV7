# Análisis: ThinkPad P14s Gen 1 (AMD) con Ryzen 7 PRO 4750U y 40 GB de RAM

*Situación a 28/09/2026. Los datos de tu unidad concreta (BIOS, batería, disco, TPM, tarjeta Wi-Fi…) te los da el script [`windows/Auditoria-Seguridad.ps1`](../windows/Auditoria-Seguridad.ps1).*

## Veredicto

**Sigue siendo un buen portátil de trabajo en 2026, y tus 40 GB de RAM son su mayor baza.** Va sobrado para ofimática, navegar con muchas pestañas, videollamadas, programar, Docker o WSL2 y máquinas virtuales. Se queda corto en la gráfica, en autonomía (por la edad de la batería) y en las funciones de IA de Windows (Copilot+).

Para seguir usándolo con seguridad hay **tres deberes urgentes**, que se explican abajo:

1. **Windows 11 25H2.** La 24H2 (Home/Pro) y las ESU de Windows 10 dejan de recibir parches el **13/10/2026**.
2. **BIOS al día** (1.53 o posterior). Trae los parches de firmware de AMD y Lenovo.
3. **BitLocker con un PIN de arranque largo**, por un ataque específico a los TPM integrados de AMD Zen 2 (faulTPM).

## Qué tienes

| Componente | Detalle | Comentario |
|---|---|---|
| Procesador | AMD Ryzen 7 PRO 4750U: Zen 2 («Renoir», 7 nm), **8 núcleos / 16 hilos**, 1,7–4,1 GHz, 8 MB de L3, 15 W | En multinúcleo sigue siendo competente. En un solo núcleo es bastante más lento que un chip actual (del orden de un 40 %), algo que se nota en webs pesadas y apps de un solo hilo. |
| Gráfica | Radeon integrada (Vega, 7 CU) | Da para vídeo 4K, varios monitores y juegos ligeros. No decodifica AV1 por hardware. |
| Memoria | **40 GB DDR4-3200** = 8 GB soldados + 32 GB en el único zócalo SO-DIMM | Es el máximo con 8 GB soldados. Ver «Memoria asimétrica» abajo. |
| Almacenamiento | 1 ranura M.2 2280 NVMe (PCIe 3.0 x4) | Admite cualquier SSD NVMe. Uno PCIe 4.0 funcionará a velocidad 3.0. |
| Pantalla | 14" FHD IPS (entre 250 y 400 nits según la configuración) | — |
| Conectividad | Wi-Fi 6 según configuración (el script dice qué tarjeta tienes), 2 USB-C con carga y vídeo, 2 USB-A, HDMI, Ethernet RJ45, conector de dock lateral | **Sin Thunderbolt ni USB4**. |
| Batería | 50 Wh | Tras unos 6 años, lo normal es que conserve entre el 60 y el 85 %. |
| Seguridad | TPM 2.0, Secure Boot, **AMD Memory Guard** (cifrado de RAM, exclusivo de los Ryzen PRO), lector de huellas e IR opcionales, tapa de cámara ThinkShutter, contraseñas de BIOS | Ver la sección de seguridad. |

### Memoria asimétrica (8 + 32 GB)

Como los módulos son distintos, solo una parte de la memoria (8 + 8 = 16 GB) trabaja en doble canal y el resto en canal simple. En el día a día casi no se nota. Afecta algo a la gráfica integrada, porque usa la RAM como memoria de vídeo. A cambio, tener 40 GB en vez de 16 vale mucho más para máquinas virtuales, contenedores y navegadores.

Dos detalles:

- **El módulo tiene que ser DDR4-3200.** Si es más lento (2666 o 2933), toda la memoria baja a esa velocidad. El script lo comprueba.
- **Windows mostrará algo menos de 40 GB**, porque la gráfica integrada se reserva una parte. Es normal.

### ¿Para qué va bien?

- **Muy bien:** ofimática, navegar, Teams o Zoom, programar, WSL2 y Docker, 2 o 3 máquinas virtuales a la vez gracias a la RAM, y edición de fotos.
- **Regular:** edición de vídeo 4K, juegos modernos (solo a 720p/1080p en calidad baja) e IA local. Los modelos de lenguaje pequeños (7–8B cuantizados) funcionan en la CPU, pero despacio. Los 40 GB permiten cargar modelos más grandes, que irán aún más lentos.
- **No disponible:** las funciones Copilot+ de Windows (Recall, Click to Do…), porque necesitan una NPU de 40 TOPS y este equipo no tiene NPU.

## Soporte y actualizaciones en 2026

| Elemento | Estado | Qué hacer |
|---|---|---|
| **Windows 11** | Compatible oficialmente (el Ryzen 4000 está en la lista de Microsoft). | Si tienes Windows 10, actualiza ya: dejó de tener soporte el 14/10/2025 y las ESU para particulares acaban el **13/10/2026**. |
| **Versión de Windows 11** | La 24H2 Home/Pro recibe parches hasta el **13/10/2026**. La 25H2, hasta el 12/10/2027. | Configuración → Windows Update → activa «Obtener las actualizaciones más recientes en cuanto estén disponibles» e instala la 25H2. Es un paquete pequeño con un solo reinicio. |
| **BIOS** (familia R1BET, compartida con el T14 Gen 1 AMD) | La versión más reciente que he encontrado publicada es la **1.53 (R1BET84W)**. | Actualiza con **Lenovo Commercial Vantage** o Lenovo System Update, o desde la [página de soporte de Lenovo](https://support.lenovo.com/us/en/downloads/ds544977-bios-update-utility-bootable-cd-for-windows-10-64-bit-thinkpad-t14-gen-1-types-20ud-20ue). Hazlo enchufado y con la clave de recuperación de BitLocker a mano. |
| **Firmware de AMD** | Zen 2 tiene vulnerabilidades importantes con parche: **Zenbleed** (CVE-2023-20593), **SinkClose** (CVE-2023-31315) y **EntrySign** (CVE-2024-36347). En un portátil, esos parches solo llegan con la BIOS del fabricante. | Otra razón para tener la BIOS al día. |
| **Vida del modelo** | Salió en 2020. Lenovo irá dejando de publicar BIOS y drivers, y cuando lo haga, los fallos de firmware nuevos ya no se corregirán. | Mientras siga recibiendo BIOS, el riesgo es bajo. Revísalo cada pocos meses. |

## Seguridad del hardware: cómo aprovecharla

| Función | Qué hace | Recomendación |
|---|---|---|
| **TPM 2.0** | Guarda las claves de BitLocker y de Windows Hello. Según la unidad, es el fTPM de AMD (dentro del procesador) o un chip aparte; el script te dice cuál. | Con fTPM de AMD Zen 2 existe el ataque [**faulTPM**](https://arxiv.org/abs/2304.14717): con el portátil en la mano y unas horas de trabajo se extraen los secretos del TPM. Con un chip aparte, el riesgo equivalente es espiar el bus. **En ambos casos, la solución es BitLocker con TPM + un PIN mejorado largo, tipo frase de 15 a 20 caracteres** (Windows Pro). Tiene que ser largo porque, tras extraer el TPM, el atacante puede probar PINs sin límite. |
| **BitLocker / Cifrado del dispositivo** | Si te roban el portátil, no pueden leer el disco. | Actívalo y guarda la clave de recuperación fuera del PC. |
| **AMD Memory Guard** | Cifra toda la RAM (protege de ataques de «arranque en frío»). Solo lo tienen los Ryzen PRO. | Actívalo en la BIOS (F1 al encender → Security), si tu BIOS muestra la opción. El script lo comprueba. |
| **Secure Boot** | Solo arrancan cargadores firmados. | Déjalo activado. En 2026 hay que tener los **certificados de 2023** (los de 2011 caducan entre junio y octubre de 2026). Windows Update los instala; el script comprueba si ya los tienes. |
| **Integridad de memoria (HVCI)** | Impide cargar drivers maliciosos. | Actívala. Zen 2 tiene soporte por hardware (GMET), así que apenas se nota en el rendimiento. |
| **Lector de huellas / cámara IR** | Windows Hello. | Úsalo en vez de escribir la contraseña. |
| **Contraseña de supervisor de BIOS** | Impide desactivar Secure Boot o arrancar desde un USB. | Opcional. **Si la olvidas, en un ThinkPad hay que cambiar la placa base.** Guárdala en tu gestor de contraseñas. |
| No disponible | Microsoft Pluton y la protección de pila por hardware (necesitan Zen 3 o posterior). | No tiene arreglo; con lo anterior bien configurado, el nivel de seguridad es bueno. |

## Mantenimiento recomendado

1. **Batería:** mira el porcentaje de salud en el informe del script. Si lo usas casi siempre enchufado, limita la carga al 75–80 % en Lenovo Vantage → Energía. Si baja del 60 % o notas el touchpad levantado o la carcasa abombada (batería hinchada), cámbiala por una original o de marca fiable.
2. **SSD:** revisa su desgaste en el informe. Un NVMe de 1–2 TB es una mejora barata y fácil: hay una sola ranura M.2 2280.
3. **Temperatura:** después de 6 años conviene limpiar el ventilador y cambiar la pasta térmica si ves que se calienta mucho y baja de rendimiento. Hazlo si sabes, o en un servicio técnico.
4. **Drivers y BIOS:** abre Lenovo Commercial Vantage una vez al mes.
5. **Copias de seguridad:** OneDrive o similar más un disco externo. Es lo que te salva del ransomware y de un disco que falla.

## ¿Merece la pena cambiarlo?

- **Quédatelo** si lo usas para trabajar, estudiar, programar o navegar. Con batería nueva y un SSD más grande (si lo necesitas), aguanta 2 o 3 años más.
- **Plantéate cambiar** si necesitas una gráfica potente, muchas horas de batería, funciones de IA en local con NPU, USB4 o Thunderbolt, o cuando Lenovo deje de publicar BIOS para este modelo.
