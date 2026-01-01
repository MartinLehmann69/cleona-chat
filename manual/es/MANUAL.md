# Cleona Chat -- Manual de Usuario

Version 3.1.125 | Julio 2026

---

## Índice

1. [¿Qué es Cleona Chat?](#1-que-es-cleona-chat)
2. [Primeros pasos](#2-primeros-pasos)
3. [Contactos](#3-contactos)
4. [Mensajes](#4-mensajes)
5. [Grupos](#5-grupos)
6. [Canales públicos](#6-canales-publicos)
7. [Llamadas](#7-llamadas)
8. [Calendario](#8-calendario)
9. [Encuestas](#9-encuestas)
10. [Múltiples identidades](#10-multiples-identidades)
11. [Multi-Device](#11-multi-device)
12. [Recuperación](#12-recuperacion)
13. [Configuración](#13-configuracion)
14. [Seguridad](#14-seguridad)
15. [Actualizaciones de software](#15-actualizaciones-de-software)
16. [Preguntas frecuentes](#16-preguntas-frecuentes)

---

## 1. ¿Qué es Cleona Chat?

### Tu mensajero, tus datos

Cleona Chat es un mensajero que funciona completamente sin un servidor central.
Tus mensajes viajan directamente de tu dispositivo al dispositivo de tu
interlocutor -- sin pasar por la sede de ninguna empresa, sin nube, sin
centro de datos. Ninguna empresa puede leer, almacenar o compartir tus
mensajes, porque sencillamente no hay ninguna empresa de por medio.

### Sin cuenta, sin número de teléfono

En Cleona no necesitas ni un número de teléfono ni una dirección de correo
electrónico para registrarte. Tu identidad consiste en un par de claves
criptográficas que se genera automáticamente en tu dispositivo la primera
vez que inicias la aplicación. Esto significa que nadie puede localizarte a
través de tu número de teléfono o tu dirección de correo, a menos que tú
mismo compartas tus datos de contacto.

### Cifrado a prueba de futuro

Cleona utiliza el llamado cifrado post-cuántico. Esto significa que ni
siquiera los futuros ordenadores cuánticos podrán descifrar tus mensajes.
No necesitas entender los detalles técnicos -- lo importante es que tu
comunicación está protegida lo mejor posible según el estado actual de la
tecnología.

### ¿Cómo funciona sin servidor?

Imagina que tú y tus contactos formáis juntos una red. Cada dispositivo
ayuda a reenviar los mensajes. Si tu interlocutor está conectado en ese
momento, el mensaje llega directamente. Si tu interlocutor está sin
conexión, los contactos en común almacenan el mensaje temporalmente y lo
entregan en cuanto el destinatario vuelve a estar disponible. Tus contactos
son, por tanto, también tu red.

### Plataformas

Cleona está disponible para Android, iOS, macOS, Linux y Windows.

---

## 2. Primeros pasos

### Instalar la aplicación

**Android:**
1. Descarga el archivo APK desde la página web de Cleona o desde GitHub Releases.
2. Abre el archivo en tu teléfono. Si es necesario, permite la instalación
   desde fuentes desconocidas (Android te lo pedirá automáticamente).
3. Toca "Instalar" y espera a que finalice la instalación.

**iOS:**
1. Abre el enlace de invitación de TestFlight en tu iPhone.
2. Toca "Instalar". TestFlight es la vía oficial de Apple para distribuir
   aplicaciones beta.
3. Tras la instalación encontrarás Cleona en tu pantalla de inicio.

**macOS:**
1. Descarga el archivo DMG desde la página web de Cleona o desde GitHub Releases.
2. Abre el DMG y arrastra Cleona a tu carpeta de Aplicaciones.
3. Al iniciarla por primera vez, es posible que macOS te pregunte si quieres
   abrir la aplicación de un desarrollador identificado -- confírmalo.

**Linux (Ubuntu/Debian):**
1. Descarga el archivo .deb desde la página web de Cleona o desde GitHub Releases.
2. Instálalo con doble clic o en la terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Inicia Cleona desde el menú de aplicaciones o en la terminal con `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Descarga el archivo .rpm desde la página web de Cleona o desde GitHub Releases.
2. Instálalo con: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Inicia Cleona desde el menú de aplicaciones o en la terminal con `cleona-chat`.

**Linux (todas las distribuciones -- AppImage):**
1. Descarga el archivo .AppImage desde la página web de Cleona o desde GitHub Releases.
2. Haz que el archivo sea ejecutable: clic derecho, Propiedades, Ejecutable, o en la terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Inícialo con doble clic o en la terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Descarga el instalador desde la página web de Cleona o desde GitHub Releases.
2. Ejecuta el archivo de instalación y sigue las instrucciones.
3. Inicia Cleona desde el menú Inicio o el acceso directo del escritorio.

### Crear una identidad

Al iniciarla por primera vez, Cleona crea automáticamente una nueva identidad
para ti. Puedes elegir un nombre para mostrar -- es el nombre que verán tus
contactos. Este nombre se puede cambiar en cualquier momento.

### Anotar la Seed-Phrase -- lo más importante de todo

Después de crear tu identidad, Cleona te muestra 24 palabras. Esta es tu
**Seed-Phrase** -- tu clave de recuperación personal.

**Anota estas 24 palabras en papel y guárdalas en un lugar seguro.**

¿Por qué es tan importante?

- Si tu teléfono se rompe, se pierde o te lo roban, puedes usar estas 24
  palabras para restaurar toda tu identidad en un dispositivo nuevo.
- Sin la Seed-Phrase no hay vuelta atrás. No existe un botón de "olvidé mi
  contraseña" ni un soporte técnico que pueda devolverte tu cuenta -- porque
  no existe ninguna cuenta en ningún servidor.
- Nunca compartas la Seed-Phrase con nadie. Quien conozca estas palabras
  puede hacerse pasar por ti.

Más adelante también encontrarás la Seed-Phrase en los ajustes, en
"Seguridad", por si necesitas volver a consultarla.

### Añadir tu primer contacto

Para chatear con alguien, primero debes añadir a esa persona como contacto.
Hay varias formas de hacerlo -- todas se explican en la siguiente sección.

---

## 3. Contactos

### Escanear un código QR (recomendado)

La forma más sencilla de añadir un contacto:

1. Tu interlocutor abre su página de detalles de identidad (toca su propio
   nombre en la barra superior) y te muestra su código QR.
2. Tú tocas el botón de más y seleccionas "Escanear código QR".
3. Apunta tu teléfono hacia el código QR de tu interlocutor.
4. La solicitud de contacto se envía automáticamente. En cuanto tu
   interlocutor la acepta, podéis escribiros.

Cuando os encontráis en persona, el código QR es el método más seguro,
porque sabes exactamente con quién estás intercambiando el contacto.

### NFC (acercar los teléfonos)

Si ambos dispositivos son compatibles con NFC:

1. Ambos abrís la función de añadir contacto.
2. Acercáis vuestros teléfonos espalda con espalda.
3. Los datos de contacto se intercambian automáticamente.

Al igual que el código QR, el NFC ofrece un alto nivel de seguridad, porque
el intercambio solo funciona si estáis físicamente uno junto al otro.

### Compartir un enlace (URI cleona://)

También puedes enviar tu enlace de contacto por correo electrónico, SMS o a
través de otro mensajero:

1. Abre tu página de detalles de identidad.
2. Copia tu enlace cleona://.
3. Envía el enlace a la persona que quiere añadirte.
4. La otra persona abre el enlace, o lo pega en el diálogo de añadir
   contacto.

Ten en cuenta que con este método confías en que el enlace no haya sido
alterado durante la transmisión. Para contactos especialmente sensibles
recomendamos el código QR o el NFC.

### Aceptar solicitudes de contacto

Cuando alguien te envía una solicitud de contacto, esta aparece en tu bandeja
de entrada (la última pestaña de la barra inferior). Ahí puedes:

- **Aceptar** -- la persona se añade a tus contactos.
- **Rechazar** -- la solicitud se descarta.
- **Bloquear** -- la persona no podrá enviarte más solicitudes.

### Niveles de verificación

Cleona te muestra cuán segura está confirmada la identidad de un contacto:

| Nivel | Significado |
|-------|-----------|
| Desconocido | Solo has recibido el Node-ID o un enlace. |
| Visto | El intercambio de claves fue exitoso, podéis comunicaros de forma cifrada. |
| Verificado | Os habéis encontrado en persona y os habéis verificado mediante código QR o NFC. |
| De confianza | Has marcado explícitamente este contacto como de confianza. |

Cuanto más alto sea el nivel, más seguro puedes estar de que realmente estás
hablando con la persona correcta.

---

## 4. Mensajes

### Enviar y recibir texto

Simplemente escribe tu mensaje en el campo de entrada de abajo y pulsa Enter
o el botón de enviar. Tu mensaje se cifra automáticamente antes de salir de
tu dispositivo.

Los mensajes entrantes aparecen en el historial del chat. Una marca de
verificación te indica si tu mensaje fue entregado.

### Enviar imágenes, vídeos y archivos

Tienes varias opciones:

- **Icono de clip** en el campo de entrada: tócalo para seleccionar un
  archivo, una imagen o un vídeo desde tu galería o tu sistema de archivos.
- **Arrastrar y soltar** (escritorio): arrastra un archivo directamente a la
  ventana del chat.
- **Pegar desde el portapapeles** (escritorio): copia una imagen y pégala en
  el chat.

Los archivos pequeños (menos de 256 KB) se envían directamente. Los archivos
más grandes se transfieren en un proceso de dos etapas: primero se anuncia
el archivo, luego se transmite por partes.

### Mensajes de voz

1. Mantén pulsado el botón del micrófono en el campo de entrada.
2. Habla tu mensaje.
3. Suelta el botón para enviar el mensaje.

Si el reconocimiento de voz está activado en tu dispositivo (consulta los
ajustes), tu mensaje de voz se transcribe automáticamente como texto. Tu
interlocutor verá entonces tanto la grabación como el texto transcrito.

### Responder a mensajes (citar)

Para responder a un mensaje concreto:

1. Abre el menú de tres puntos junto al mensaje.
2. Selecciona "Responder".
3. Sobre el campo de entrada aparecerá un banner con el mensaje citado.
4. Escribe tu respuesta y envíala.

El mensaje citado se muestra en tu respuesta, de modo que la referencia
queda clara.

### Editar y eliminar mensajes

- **Editar:** menú de tres puntos del mensaje, luego "Editar". Cambia el
  texto y vuelve a enviarlo. Tu interlocutor verá que el mensaje fue
  editado. La edición es posible dentro de los 15 minutos posteriores al
  envío.
- **Eliminar:** menú de tres puntos del mensaje, luego "Eliminar". El
  mensaje se elimina tanto en tu dispositivo como en el de tu interlocutor.
  Puedes eliminar tus propios mensajes en cualquier momento -- no existe
  ningún límite de tiempo para eliminar.

### Reacciones con emoji

En lugar de escribir una respuesta, puedes reaccionar a un mensaje con un
emoji:

1. Abre el menú de tres puntos o mantén pulsado el mensaje.
2. Elige un emoji de la selección rápida o abre el selector de emojis para
   ver todas las opciones.
3. Tu reacción aparecerá debajo del mensaje.

### Copiar texto

A través del menú de tres puntos de un mensaje puedes copiar el texto del
mensaje al portapapeles.

### Buscar mensajes

En la parte superior de la ventana del chat encontrarás la función de
búsqueda. Introduce un término de búsqueda y Cleona te mostrará todos los
resultados en el chat actual. Con las teclas de flecha puedes desplazarte
entre los resultados.

En la pantalla de inicio hay además un filtro de búsqueda que abarca todas
las pestañas, con el que puedes buscar un término en todas tus
conversaciones.

### Vista previa de enlaces

Cuando envías un enlace, Cleona genera automáticamente una vista previa
(título, descripción, imagen de vista previa). Esta vista previa se genera
en tu dispositivo y se envía junto con el mensaje -- tu interlocutor no
necesita establecer ninguna conexión con el sitio web enlazado para verla.

Cuando tocas un enlace recibido, se te pregunta si quieres abrirlo en el
navegador normal, en modo incógnito, o si prefieres no abrirlo.

---

## 5. Grupos

### Crear un grupo

1. Cambia a la pestaña "Grupos".
2. Toca el botón de más.
3. Ponle un nombre al grupo.
4. Selecciona los contactos que quieres invitar.
5. Toca "Crear".

Los contactos invitados reciben una notificación y pueden unirse al grupo.

### Invitar miembros

También después de la creación puedes invitar a más contactos:

1. Abre la información del grupo (menú de tres puntos en la vista general
   del grupo o barra superior en el chat de grupo).
2. Toca "Invitar".
3. Selecciona los contactos que quieres añadir.

### Roles

Cada grupo tiene tres roles:

- **Propietario (Owner):** tiene el control total. Puede añadir y eliminar
  miembros, nombrar administradores y gestionar el grupo. El propietario
  también puede transferir su estatus a otro miembro.
- **Administrador (Admin):** puede eliminar miembros y ayudar en la gestión.
- **Miembro:** puede leer y escribir mensajes.

### Abandonar un grupo

1. Abre el menú de tres puntos en la vista general del grupo.
2. Selecciona "Abandonar".
3. Confirma tu decisión.

Cuando abandonas un grupo, tus mensajes anteriores siguen siendo visibles
para los demás miembros.

---

## 6. Canales públicos

### ¿Qué son los canales?

Los canales son foros de discusión públicos dentro de la red de Cleona. A
diferencia de los grupos, aquí cualquiera puede leer sin necesidad de ser
invitado. Solo el propietario y los administradores pueden publicar
contenido -- los suscriptores solo leen.

### Buscar y unirse a canales

1. Cambia a la pestaña "Canales".
2. Abre la pestaña "Buscar".
3. Busca entre los canales disponibles por nombre o tema.
4. Toca un canal y luego "Suscribirse".

Los canales se pueden filtrar por idioma. Algunos canales están marcados
como "No apto para menores" -- estos solo son visibles si has confirmado en
tu perfil que eres mayor de 18 años.

### Crear tu propio canal

1. Cambia a la pestaña "Canales".
2. Toca el botón de más.
3. Introduce un nombre de canal (debe ser único en toda la red).
4. Elige el idioma y si el canal será público o privado.
5. Opcional: añade una descripción y una imagen.
6. Toca "Crear".

En los canales públicos puedes definir si el contenido se clasifica como "No
apto para menores".

### Reportar contenido

Si detectas contenido inapropiado en un canal público, puedes reportarlo.
Cleona utiliza un sistema de moderación descentralizado: los reportes son
evaluados por miembros de la red seleccionados al azar (una especie de
"jurado popular"). Si se detecta una infracción, el canal recibe una
advertencia. En caso de infracciones repetidas, el canal se degrada en el
índice de búsqueda o se bloquea.

### Canales del sistema

Cleona cuenta con dos canales del sistema integrados:

- **Bug Log (registro de errores):** cuando Cleona detecta un fallo, te
  pregunta si quieres enviar un informe de error anonimizado. Estos
  informes se publican en el canal Bug Log, donde la comunidad puede
  consultarlos. No se transmite ningún dato personal -- solo descripciones
  técnicas del error. También puedes enviar manualmente un informe de
  registro (con un diálogo de vista previa y consentimiento explícito).
- **Feature Requests (solicitudes de funciones):** aquí los usuarios pueden
  enviar sugerencias de funciones y votar por las propuestas existentes.
  Las propuestas se ordenan según los votos.

Ambos canales del sistema tienen un límite de tamaño de 25 MB y están
supervisados por el sistema de moderación por jurado.

---

## 7. Llamadas

### Iniciar una llamada de voz

1. Abre el chat con el contacto al que quieres llamar.
2. Toca el icono del teléfono en la barra superior.
3. Espera a que tu interlocutor acepte la llamada.

Durante la conversación verás una línea de tiempo con la duración de la
llamada y tendrás acceso a silenciar el micrófono y al altavoz.

Para colgar, toca el botón rojo de colgar.

### Iniciar una videollamada

1. Abre el chat con el contacto.
2. Toca el icono de la cámara en la barra superior.
3. Tu imagen de vídeo aparece en una ventana pequeña, la imagen de tu
   interlocutor en el área grande.

Puedes cambiar entre la cámara frontal y la trasera durante la llamada.

### Llamadas entrantes

Cuando alguien te llama, aparece una ventana de notificación con el nombre
de quien llama. Puedes:

- **Aceptar** -- comienza la conversación.
- **Rechazar** -- la persona que llama recibe una notificación.

Si ya estás en una llamada, cualquier llamada nueva se rechaza
automáticamente.

### Llamadas grupales

También puedes realizar llamadas grupales en las que participan varias
personas al mismo tiempo. La llamada se organiza mediante un árbol de
reenvío inteligente, de modo que no todos los participantes necesitan estar
conectados directamente entre sí. Todas las conversaciones están cifradas de
extremo a extremo.

### Cifrado en las llamadas

Todas las llamadas se cifran con claves de un solo uso que existen
únicamente durante la duración de la conversación. Al colgar, estas claves
se eliminan inmediatamente. Nadie puede descifrar una conversación pasada a
posteriori.

---

## 8. Calendario

Cleona incluye un calendario integrado que funciona cifrado y de forma
completamente descentralizada -- sin ningún servicio en la nube.

### Vistas

El calendario ofrece cinco vistas: día, semana, mes, año y una vista de
tareas. Cambia entre ellas usando las pestañas en la parte superior de la
pantalla del calendario.

### Crear citas

Toca una franja horaria o utiliza el botón de añadir para crear una nueva
cita. Puedes introducir título, fecha, hora, lugar y notas. Las citas se
almacenan cifradas en tu dispositivo.

### Citas recurrentes

Las citas pueden repetirse a diario, semanalmente, mensualmente o
anualmente. Puedes ajustar el patrón (por ejemplo, cada segundo martes, el
primer día de cada mes) y establecer una fecha de finalización o un número
de repeticiones.

### Invitar contactos

Al crear o editar una cita puedes invitar a tus contactos de Cleona. Ellos
reciben una invitación de calendario cifrada y pueden responder con
Aceptar, Rechazar o Quizás. Los cambios en la cita se envían automáticamente
a todos los invitados.

### Indicador de disponibilidad

Puedes compartir tu disponibilidad con tus contactos sin revelar los
detalles de la cita. Hay tres niveles de privacidad: detalles completos,
solo bloques de tiempo, u oculto. Puedes establecer un valor predeterminado
y sobrescribirlo por contacto.

### Recordatorios

Las citas pueden tener recordatorios que activan una notificación del
sistema antes del inicio de la cita. Puedes posponer los recordatorios si
lo necesitas.

### Sincronización con calendarios externos

Cleona puede sincronizarse con servicios de calendario externos:

- **CalDAV** -- conéctate con cualquier servidor compatible con CalDAV
  (Nextcloud, Radicale, etc.).
- **Google Calendar** -- sincronización a través de la API de Google
  Calendar con autenticación segura mediante OAuth2.
- **Servidor CalDAV local** -- Cleona puede iniciar un servidor CalDAV local
  en tu dispositivo, de modo que las aplicaciones de calendario de
  escritorio (Thunderbird, Outlook, Apple Calendar, Evolution) puedan
  sincronizarse con tu calendario de Cleona.
- **Calendario del sistema de Android** -- las citas de Cleona pueden
  transferirse a la aplicación de calendario integrada de tu dispositivo
  Android.
- **Archivos ICS** -- importa y exporta citas en el formato estándar
  iCalendar.

### Exportación a PDF

Puedes imprimir o exportar cualquier vista del calendario (día, semana, mes,
año) como documento PDF.

---

## 9. Encuestas

Puedes crear encuestas en cualquier chat o grupo para recabar opiniones o
planificar citas.

### Tipos de encuesta

Cleona admite cinco tipos de encuestas:

- **Selección simple** -- los participantes eligen una opción.
- **Selección múltiple** -- los participantes pueden elegir varias
  opciones.
- **Encuesta de fecha** -- encuentra una fecha que funcione para todos. Cada
  participante marca las fechas como disponible, quizás o no disponible.
- **Escala** -- valora algo en una escala numérica (por ejemplo, del 1 al
  5).
- **Texto libre** -- los participantes escriben su propia respuesta.

### Crear una encuesta

Abre un chat y toca el icono de encuesta (o utiliza el menú de adjuntos).
Elige el tipo de encuesta, formula tu pregunta y las opciones, y envía la
encuesta. Aparecerá como un mensaje en el chat.

### Votar

Toca una encuesta para emitir tu voto. Puedes cambiar o retirar tu voto en
cualquier momento.

### Votación anónima

Las encuestas se pueden configurar para votación anónima. Si está activada,
los votos son criptográficamente anónimos -- nadie, ni siquiera quien creó
la encuesta, puede ver quién votó qué. El número de votos sigue siendo
visible.

### De encuesta de fecha a calendario

Cuando una encuesta de fecha se cierra, la fecha ganadora puede convertirse
directamente en una entrada de calendario con un solo toque.

---

## 10. Múltiples identidades

### ¿Por qué varias identidades?

Imagina que quieres separar tu vida profesional de tu vida privada -- de
forma similar a tener dos números de teléfono distintos, pero sin un
segundo móvil. En Cleona puedes usar varias identidades en un mismo
dispositivo. Cada identidad tiene su propio nombre, su propia foto de
perfil, sus propios contactos y sus propias conversaciones.

### Crear una nueva identidad

1. En la barra superior ves tu identidad actual como pestaña.
2. Toca el signo de más (+) a la derecha de tus pestañas de identidad.
3. Introduce un nombre para la nueva identidad.
4. Listo -- la nueva identidad está activa de inmediato.

### Cambiar entre identidades

Simplemente toca la pestaña de identidad en la barra superior. El cambio es
inmediato -- sin tiempos de espera, sin recargas.

### Todas funcionan simultáneamente

Un punto importante: todas tus identidades están activas al mismo tiempo.
Aunque en ese momento se muestre tu identidad "Trabajo", tu identidad
"Privada" sigue recibiendo mensajes. No te pierdes nada, sin importar qué
identidad tengas seleccionada en ese momento.

### Página de detalles de identidad

Cuando tocas la pestaña de tu identidad activa, se abre la página de
detalles. Aquí puedes:

- Mostrar tu código QR para contactos.
- Cambiar o eliminar tu foto de perfil.
- Añadir una descripción de perfil.
- Cambiar tu nombre para mostrar.
- Elegir un diseño (skin) para esta identidad.
- Eliminar la identidad si ya no la necesitas.

### Eliminar una identidad

Cuando eliminas una identidad, tus contactos son notificados al respecto. La
identidad y todos los datos asociados se eliminan de tu dispositivo. Este
proceso no se puede deshacer.

---

## 11. Multi-Device

### Usar Cleona en varios dispositivos

Puedes usar la misma identidad en hasta 5 dispositivos simultáneamente. Un
dispositivo es el principal (guarda la Seed-Phrase), y los demás
dispositivos se vinculan a él.

### Vincular un nuevo dispositivo

1. Abre los ajustes en tu dispositivo principal.
2. Ve a "Dispositivos vinculados".
3. Selecciona "Vincular nuevo dispositivo".
4. Instala Cleona en el nuevo dispositivo y, al iniciarlo, selecciona
   "Vincular con dispositivo existente".
5. Escanea el código QR de emparejamiento que se muestra en tu dispositivo
   principal, o utiliza el enlace de emparejamiento.

El dispositivo vinculado recibe un certificado de delegación del dispositivo
principal. Los mensajes enviados desde un dispositivo vinculado están
firmados criptográficamente con una clave delegada, de modo que los
contactos pueden verificar que el mensaje realmente proviene de tu
identidad.

### Cómo funciona

- El dispositivo principal guarda tu Seed-Phrase y las claves maestras.
- Los dispositivos vinculados reciben claves de firma derivadas y un
  certificado de delegación -- nunca reciben la Seed-Phrase en sí.
- Todos los dispositivos comparten la misma identidad y los mismos
  contactos. Los mensajes llegan a todos los dispositivos.
- Los certificados de delegación se renuevan automáticamente antes de
  caducar.

### Gestión de dispositivos

Abre los ajustes y ve a "Dispositivos vinculados" para ver todos tus
dispositivos vinculados, su estado y su última actividad. Puedes revocar un
dispositivo vinculado en cualquier momento si se pierde o te lo roban.

### Rotación de claves de emergencia

Si sospechas que un dispositivo ha sido comprometido, puedes activar una
rotación de claves de emergencia. En este proceso se generan nuevas claves,
y la rotación debe ser confirmada por una mayoría de tus otros dispositivos.
Esto evita que un único dispositivo robado pueda rotar las claves por su
cuenta.

---

## 12. Recuperación

### Usar la Seed-Phrase

Si pierdes tu dispositivo o configuras uno nuevo:

1. Instala Cleona en el nuevo dispositivo.
2. Selecciona "Restaurar" al iniciar.
3. Introduce tus 24 palabras.
4. Cleona restaura tu identidad y contacta automáticamente a tus contactos
   anteriores.
5. Tus contactos responden con tus datos de contacto, las membresías de
   grupo y los historiales de mensajes.

La recuperación ocurre en tres pasos:
- Primero regresan tus contactos y grupos.
- Luego los últimos 50 mensajes de cada conversación.
- Por último, el historial completo de mensajes.

Basta con que uno solo de tus contactos esté conectado para que la
recuperación funcione.

### Guardian Recovery (personas de confianza)

Puedes nombrar hasta cinco personas de confianza como "Guardianes". Para
ello, tu clave de recuperación se divide en cinco partes, de las cuales cada
guardián recibe una. Para restaurar tu identidad bastan tres de las cinco
partes.

Esto significa que, incluso si has perdido tu Seed-Phrase, tres de tus
guardianes pueden restaurar tu cuenta juntos. Ningún guardián individual
puede acceder solo a tus datos -- siempre se necesitan al menos tres.

Así configuras a tus guardianes:
1. Abre los ajustes.
2. Ve a "Seguridad".
3. Selecciona "Guardian Recovery".
4. Elige cinco contactos de confianza.

### Por qué tus contactos son tu copia de seguridad

En los mensajeros tradicionales, tus datos residen en los servidores del
proveedor. En Cleona no hay ningún servidor -- pero tus contactos asumen ese
papel. Cuando envías un mensaje, los contactos en común guardan una copia
cifrada por si el destinatario está sin conexión en ese momento. En una
recuperación, tus contactos te devuelven tus datos.

Esto significa que cuantos más contactos activos tengas, más fiable será tu
copia de seguridad. Basta con un contacto que se conecte regularmente para
que la recuperación tenga éxito.

---

## 13. Configuración

Accedes a la configuración a través del icono del engranaje en la esquina
superior derecha.

### Notificaciones y tonos de llamada

- Elige entre seis tonos de llamada diferentes para las llamadas entrantes.
- Configura un tono de notificación para los mensajes.
- En dispositivos Android puedes además activar o desactivar la vibración.

### Diseños (Skins)

Cleona ofrece diez diseños diferentes: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold y Contrast. El diseño Contrast cumple el
nivel más alto de accesibilidad (WCAG AAA) y es especialmente legible para
personas con visión reducida.

Cada identidad puede tener su propio diseño. Cambias el diseño en la página
de detalles de identidad (toca la pestaña de identidad activa).

Además, en los ajustes, bajo "Apariencia", puedes cambiar entre el tema
claro, el oscuro y el tema del sistema.

### Cambiar el idioma

Cleona está disponible en 33 idiomas, incluidos idiomas con escritura de
derecha a izquierda (por ejemplo, árabe, hebreo). Cambia el idioma en los
ajustes, bajo "Idioma".

### Límite de almacenamiento

Puedes definir cuánto espacio de almacenamiento puede usar Cleona en tu
dispositivo (entre 100 MB y 2 GB). Cuando se alcanza el límite, los archivos
multimedia más antiguos se archivan o se eliminan automáticamente -- los
mensajes de texto siempre se conservan.

### Archivado de contenido multimedia

Si tienes un almacenamiento en red (NAS) o una carpeta compartida en casa,
Cleona puede archivar automáticamente tus archivos multimedia allí. Se
admiten SMB, SFTP, FTPS y WebDAV.

Así funciona el almacenamiento escalonado:
- Los primeros 30 días: todo permanece en tu dispositivo.
- Después de 30 días: una vista previa permanece en el dispositivo, el
  original se archiva.
- Después de 90 días: solo queda una pequeña vista previa en el
  dispositivo.
- Después de un año: solo queda un marcador de posición, el original se
  guarda de forma segura en el archivo.

Puedes tocar en cualquier momento un archivo multimedia archivado para
recuperarlo -- siempre que estés conectado a tu red doméstica. Los archivos
multimedia especialmente importantes se pueden fijar para que nunca se
archiven.

### Transcripción de mensajes de voz

Si está activada, tus mensajes de voz se convierten en texto localmente en
tu dispositivo (con el modelo de código abierto Whisper). El texto
transcrito se envía junto con la grabación a tu interlocutor. La
transcripción ocurre completamente en tu dispositivo -- no se envían datos a
servicios externos.

### Descarga automática

Puedes configurar a partir de qué tamaño los archivos multimedia se
descargan automáticamente. Así puedes, por ejemplo, dejar que las imágenes
se carguen automáticamente, pero decidir manualmente en el caso de vídeos
grandes.

### Dispositivos vinculados

Gestiona tus dispositivos vinculados en esta sección de los ajustes. Consulta
el capítulo de Multi-Device para más detalles.

---

## 14. Seguridad

### ¿Qué significa el cifrado post-cuántico?

El cifrado actual se basa en problemas matemáticos que son extremadamente
difíciles de resolver para los ordenadores normales. Los ordenadores
cuánticos podrían resolver rápidamente algunos de estos problemas en el
futuro. El cifrado post-cuántico utiliza métodos adicionales que también
resisten a los ordenadores cuánticos.

Cleona combina ambos enfoques: cifrado clásico para la fiabilidad y métodos
post-cuánticos para la seguridad a futuro. Así estás protegido
simultáneamente frente a las amenazas actuales y las futuras.

Para cada mensaje individual se genera una clave propia. Incluso si un
atacante lograra descifrar la clave de un mensaje, no podría leer con ella
ningún otro mensaje.

### Por qué la ausencia de servidor es más segura

En los mensajeros tradicionales, tus mensajes pasan por los servidores del
proveedor. Aunque estén cifrados allí, el proveedor tiene acceso a los
metadatos (quién se comunica con quién, cuándo, con qué frecuencia, desde
dónde) y en ocasiones debe entregarlos por orden judicial.

En Cleona no existe ese punto central. Tus mensajes viajan directamente de
dispositivo a dispositivo. No hay ningún lugar donde converjan todos los
metadatos. Nadie puede reconstruir tu comportamiento de comunicación a
partir de un único punto de datos.

### ¿Qué pasa si estás sin conexión?

Si envías un mensaje y el destinatario está sin conexión:

1. Cleona intenta primero entregar el mensaje directamente.
2. Si no lo consigue, el mensaje se reenvía a través de contactos en común.
3. Al mismo tiempo, el mensaje se distribuye como fragmentos cifrados entre
   varios nodos de la red (parecido a un rompecabezas de 10 piezas, de las
   cuales bastan 7 para reconstruir la imagen).
4. El mensaje se conserva hasta 7 días.

En cuanto el destinatario vuelve a conectarse, los mensajes se entregan.
Recibes una confirmación cuando tu mensaje ha llegado.

### Anti-censura

Si tu red bloquea el método de conexión estándar (UDP), Cleona cambia
automáticamente a una transmisión alternativa (TLS), que es más difícil de
detectar y bloquear. Esto ocurre de forma transparente -- no necesitas
configurar nada.

### Almacenamiento seguro de claves

En las plataformas compatibles, Cleona almacena tus claves de cifrado en el
llavero seguro del sistema operativo (Android Keystore, iOS Keychain, macOS
Keychain). Cuando está disponible, esto ofrece protección respaldada por
hardware para tus claves.

### Cifrado de la base de datos

Todos tus mensajes, contactos y ajustes se almacenan cifrados en tu
dispositivo. Incluso si alguien accediera a tu sistema de archivos, no
podría leer nada sin tu clave criptográfica. Esta clave se deriva de tu
identidad y solo existe en tu dispositivo.

### Red cerrada

Cleona funciona como una red cerrada. Cada paquete de red está autenticado,
de modo que solo pueden participar dispositivos Cleona legítimos. Esto
impide que personas ajenas introduzcan mensajes falsificados o intercepten
el tráfico de la red.

---

## 15. Actualizaciones de software

### ¿Cómo recibo las actualizaciones?

Cleona se puede actualizar de varias formas. El objetivo es que puedas
seguir recibiendo actualizaciones incluso si algunas vías de distribución
fallan o son bloqueadas:

1. **App Store / Play Store:** si instalaste Cleona a través de una tienda
   de aplicaciones, recibes las actualizaciones de la forma habitual a
   través de la tienda.
2. **GitHub Releases:** en la página de GitHub del proyecto encontrarás
   paquetes de instalación firmados para todas las plataformas.
3. **Actualizaciones dentro de la red:** si otro usuario de Cleona en tu red
   ya tiene la versión más reciente, Cleona puede obtener la actualización
   directamente a través de la red P2P -- sin ningún servidor externo. Para
   ello, la nueva versión se divide en fragmentos con corrección de errores
   y se distribuye entre varios nodos. Tu dispositivo reúne suficientes
   fragmentos y reconstruye la actualización. La autenticidad se verifica
   mediante una firma Ed25519 del desarrollador.
4. **Enlaces de invitación:** puedes crear enlaces de invitación que
   contienen todo lo que un nuevo usuario necesita para instalar Cleona y
   conectarse a la red.
5. **Transferencia física:** en entornos sin internet puedes compartir
   Cleona con otras personas mediante una memoria USB o en la red local.

### Notificación de actualización

Cuando hay una nueva actualización disponible, Cleona te muestra una
notificación en la pantalla de inicio. Si la actualización también está
disponible a través de la red (actualización dentro de la red), puedes
elegir descargarla directamente desde la red.

### Distribución binaria

Por defecto, tu dispositivo ayuda a distribuir las actualizaciones a otros
usuarios de la red. Si no lo deseas, puedes desactivar esta función en los
ajustes, bajo "Red". El uso de almacenamiento para los fragmentos de
actualización está limitado (5 MB en dispositivos móviles, 20 MB en
dispositivos de escritorio) y se depura periódicamente.

### Verificación de firma

Cada actualización está firmada criptográficamente. Cleona verifica la
firma automáticamente antes de instalar una actualización. Esto garantiza
que solo se acepten actualizaciones del desarrollador oficial -- incluso si
la actualización se obtuvo a través de la red P2P.

---

## 16. Preguntas frecuentes

### "¿Puedo usar Cleona sin internet?"

No, Cleona necesita una conexión de red para enviar y recibir mensajes. Sin
embargo, no es necesario que tú y tu interlocutor estéis conectados al mismo
tiempo: los mensajes enviados mientras el destinatario está sin conexión se
almacenan temporalmente y se entregan automáticamente en cuanto ambas partes
vuelven a estar conectadas. En una red local (por ejemplo, en la misma
WLAN) también podéis comunicaros sin ningún acceso a internet.

### "¿Qué pasa si pierdo mi Seed-Phrase?"

Si has configurado guardianes, tres de las cinco personas de confianza
pueden restaurar tu acceso conjuntamente. Sin guardianes y sin Seed-Phrase,
lamentablemente no hay forma de recuperar tu identidad. Por eso es tan
importante guardar las 24 palabras en un lugar seguro.

### "¿Puede alguien leer mis mensajes?"

No. Cada mensaje se cifra con una clave de un solo uso que solo es válida
para ese mensaje concreto. Solo tú y tu interlocutor podéis descifrar el
mensaje. No existe ningún servidor central, ninguna clave maestra ni ningún
acceso para el desarrollador. Incluso si un dispositivo reenvía el mensaje
en su camino, solo ve datos cifrados sin sentido.

### "¿Por qué no necesito un número de teléfono?"

Porque tu identidad es puramente criptográfica. En lugar de un número de
teléfono o una dirección de correo electrónico vinculada a tu nombre real,
te identifica un par de claves generado en tu dispositivo. Añades contactos
mediante código QR, NFC o enlace -- no a través de una agenda telefónica.
Esto significa más privacidad, porque tu cuenta de mensajería no está
vinculada a tu identidad real.

### "¿Cómo encuentro a otras personas en Cleona?"

Cleona deliberadamente no tiene búsqueda de contactos por número de
teléfono o nombre -- eso sería un problema de privacidad. En su lugar,
intercambias los datos de contacto directamente: mediante código QR, NFC,
enlace cleona:// o en canales públicos. Es como intercambiar tarjetas de
visita en lugar de consultar una guía telefónica.

### "¿Funciona Cleona también en el extranjero?"

Sí. Mientras tengas conexión a internet, Cleona funciona en cualquier parte
del mundo. Como no existe ningún servidor central, el servicio tampoco se
puede bloquear para determinados países. Cleona cuenta además con un
mecanismo de anti-censura: si la conexión normal (UDP) es bloqueada, Cleona
cambia automáticamente a una transmisión alternativa (TLS), que es más
difícil de detectar y bloquear.

### "¿Es gratis Cleona?"

Sí. Cleona se puede usar de forma gratuita y sin publicidad. Como no existe
ningún servidor central, tampoco se generan costes de servidor por su
funcionamiento. En la aplicación encontrarás, bajo "Donar", la posibilidad
de apoyar voluntariamente el desarrollo.

### "Mi mensaje tiene un icono de reloj -- ¿qué significa?"

Significa que el mensaje aún no ha sido entregado. Es probable que tu
interlocutor esté sin conexión en ese momento. En cuanto el mensaje se
entregue, el icono cambiará. Los mensajes se conservan hasta 7 días para su
entrega.

### "¿Puedo cambiarme de WhatsApp a Cleona?"

Sí, pero no puedes transferir tus chats de WhatsApp. Cleona y WhatsApp son
sistemas completamente distintos. Debes añadir a tus contactos uno por uno
en Cleona. La forma más sencilla es publicar tu enlace cleona:// en un grupo
de WhatsApp y pedir a los demás que te añadan desde allí.

### "¿Puedo usar Cleona en varios dispositivos a la vez?"

Sí. Puedes vincular hasta 5 dispositivos con la misma identidad. Un
dispositivo es el principal (guarda la Seed-Phrase), y los demás
dispositivos se vinculan mediante un proceso de emparejamiento seguro. Todos
los dispositivos comparten la misma identidad, los mismos contactos y las
mismas conversaciones. Consulta el capítulo de Multi-Device para más
detalles.

### "¿Cómo recibo actualizaciones si la App Store está bloqueada?"

Cleona puede obtener actualizaciones directamente a través de la red P2P,
sin depender de una App Store, un sitio web o un servidor de descargas. Si
otro usuario de la red tiene la versión más reciente, tu dispositivo puede
descargar la actualización desde allí. La autenticidad se verifica mediante
una firma digital del desarrollador. Alternativamente, un contacto puede
compartirte la aplicación mediante un enlace de invitación o una memoria
USB. Más información en el capítulo "Actualizaciones de software".

---

## Ayuda y contacto

Si tienes preguntas o te encuentras con un problema, encontrarás información
actualizada en la página web de Cleona y en GitHub. Como Cleona es un
proyecto descentralizado, no existe un soporte técnico clásico -- pero sí
una comunidad activa que ayuda con gusto.

---

*Este manual describe Cleona Chat versión 3.1.125. Algunas funciones pueden
cambiar o ampliarse en versiones posteriores.*
