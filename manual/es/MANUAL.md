# Cleona Chat -- Manual de usuario

Versión 4.2 | A noviembre de 2026

---

## Índice

1. [¿Qué es Cleona Chat?](#1-qué-es-cleona-chat)
2. [Primeros pasos](#2-primeros-pasos)
3. [Contactos](#3-contactos)
4. [Mensajes](#4-mensajes)
5. [Grupos](#5-grupos)
6. [Canales públicos](#6-canales-públicos)
7. [Llamadas](#7-llamadas)
8. [Calendario](#8-calendario)
9. [Encuestas](#9-encuestas)
10. [Múltiples identidades](#10-múltiples-identidades)
11. [Varios dispositivos](#11-varios-dispositivos)
12. [Recuperación](#12-recuperación)
13. [Ajustes](#13-ajustes)
14. [Seguridad](#14-seguridad)
15. [Actualizaciones de software](#15-actualizaciones-de-software)
16. [Preguntas frecuentes](#16-preguntas-frecuentes)

---
## 1. ¿Qué es Cleona Chat?

### Tu mensajería, tus datos

Cleona Chat es un mensajero que funciona completamente sin servidor central.
Tus mensajes viajan de tu dispositivo al dispositivo de tu interlocutor --
sin rodeo por la sede de una empresa, sin nube, sin centro de datos. Allí
donde otro dispositivo ayuda por el camino, solo reenvía paquetes
cifrados. Ninguna empresa puede leer, almacenar ni transmitir tus mensajes,
simplemente porque no hay ninguna empresa entremedio.

### Sin cuenta, sin número de teléfono

En Cleona no necesitas ningún número de teléfono ni dirección de correo
electrónico para registrarte. Tu identidad consiste en un par de claves
criptográficas que se genera automáticamente en tu dispositivo en el primer
inicio. Esto significa: nadie puede localizarte por tu número de teléfono
o tu dirección de correo electrónico, a menos que tú mismo compartas tus
datos de contacto.

### Cifrado preparado para el futuro

Cleona utiliza el llamado cifrado post-cuántico. Esto significa: ni
siquiera futuros ordenadores cuánticos podrían descifrar tus mensajes. No
tienes que entender los detalles -- lo único importante es que tu
comunicación está protegida de la mejor forma posible según el estado
actual de la técnica.

### ¿Cómo funciona sin servidor?

La red de Cleona está formada solo por los dispositivos de sus usuarios.
Cada dispositivo es un nodo, ningún nodo es más importante que otro, y
cada uno conoce solo a sus vecinos. Cuatro cosas hacen esta red especial:

- **Ningún punto fijo.** En la app no hay ninguna dirección de servidor, y
  la red no depende de ningún nodo concreto. No hay nada que se pueda
  apagar para apagar Cleona.
- **Al instante.** Tu mensaje sale en el mismo momento en que lo envías.
  No espera ningún reloj ni nada más.
- **Cobertura de fondo.** Tu dispositivo envía continuamente pequeños
  paquetes de cobertura, para que desde fuera no se pueda saber cuándo
  estás escribiendo de verdad. Ningún mensaje depende de ello -- la
  cobertura solo funciona en paralelo.
- **Códigos en lugar de nombres.** Quien reenvía un mensaje solo ve un
  código que cambia cada día. Normalmente, ninguno de ellos conoce al
  mismo tiempo remitente y destinatario; las excepciones se describen en
  el capítulo 14.

**Tres caminos, todos a la vez.** Cuando envías un mensaje, Cleona no
prueba un camino tras otro, sino todos los adecuados a la vez. En cuanto
tu interlocutor confirma la recepción, los demás se cancelan.

1. **En la misma red:** Si estáis en la misma red Wi-Fi, el mensaje va
   directamente.
2. **Por los vecinos fijos:** En internet, tu dispositivo entrega el
   mensaje a su vecino fijo. Este lo reenvía a los vecinos fijos de tu
   interlocutor (hasta tres a la vez), y uno de ellos lo entrega.
3. **Buzón:** Si tu interlocutor está desconectado, Cleona deposita el
   mensaje cifrado en tres vecinos. Ahí permanece hasta 7 días. Cuando
   tu interlocutor vuelve a estar en línea, lo recoge.

**¿Cómo entras en la red?** En la app no hay ninguna dirección de servidor.
Tu punto de entrada lo obtienes de tu primer contacto: su invitación
contiene las direcciones a través de las cuales tu dispositivo encuentra
sus primeros vecinos. En la misma red Wi-Fi, los dispositivos Cleona también
se encuentran por sí mismos. A partir de ahí, tu dispositivo va conociendo
más vecinos con cada vecino que encuentra.

### Plataformas

Cleona está disponible para Android, iOS, macOS, Linux y Windows. En los
ordenadores y en Android, los mensajes y las llamadas llegan en cuestión de
segundos. En el iPhone esto se cumple mientras la app está abierta. Cuando
no lo está, iOS solo la despierta brevemente de vez en cuando; cuándo, lo
decide iOS. Cleona entonces recoge todo lo que se guardó para ti y muestra
una notificación con un número en el icono de la app. Las llamadas no
alcanzan un iPhone con la app cerrada. Es una regla de Apple, no un defecto
de Cleona.

---

## 2. Primeros pasos

### Instalar la app

**Android:**
1. Descarga el archivo APK del sitio web de Cleona o de GitHub Releases.
2. Abre el archivo en tu teléfono. Si es necesario, permite la instalación
   desde fuentes desconocidas (Android te lo pregunta automáticamente).
3. Toca "Instalar" y espera hasta que la instalación termine.

**iOS:**
1. Abre el enlace de invitación de TestFlight en tu iPhone.
2. Toca "Instalar". TestFlight es la forma oficial de Apple de distribuir
   apps beta.
3. Tras la instalación encontrarás Cleona en tu pantalla de inicio.

**macOS:**
1. Descarga el archivo DMG del sitio web de Cleona o de GitHub Releases.
2. Abre el DMG y arrastra Cleona a tu carpeta de Aplicaciones.
3. En el primer inicio, es posible que macOS te pregunte si quieres abrir
   la app de un desarrollador identificado -- confírmalo.

**Linux (Ubuntu/Debian):**
1. Descarga el archivo .deb del sitio web de Cleona o de GitHub Releases.
2. Instala con doble clic o en la terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Inicia Cleona desde el menú de aplicaciones o en la terminal con `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Descarga el archivo .rpm del sitio web de Cleona o de GitHub Releases.
2. Instala con: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Inicia Cleona desde el menú de aplicaciones o en la terminal con `cleona-chat-beta`.

**Linux (todas las distribuciones -- AppImage):**
1. Descarga el archivo .AppImage del sitio web de Cleona o de GitHub Releases.
2. Haz el archivo ejecutable: clic derecho, propiedades, ejecutable, o en
   la terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Inicia con doble clic o en la terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Los nombres de los paquetes corresponden a la beta, que por ahora es la
única versión publicada; se llaman `cleona-chat-beta`.

**Windows:**
1. Descarga el instalador del sitio web de Cleona o de GitHub Releases.
2. Ejecuta el archivo de instalación y sigue las instrucciones.
3. Inicia Cleona desde el menú Inicio o el acceso directo del escritorio.

### Crear una identidad

En el primer inicio, Cleona crea automáticamente una identidad nueva para
ti. Puedes darte un nombre para mostrar -- ese es el nombre que ven tus
contactos. Este nombre se puede cambiar en cualquier momento.

### Anotar la frase semilla -- lo más importante de todo

Tras crear tu identidad, Cleona te muestra 24 palabras. Esa es tu
**frase semilla** -- tu clave de recuperación personal.

**Anota estas 24 palabras en papel y guárdalas de forma segura.**

¿Por qué es tan importante?

- Si tu teléfono se rompe, se pierde o lo roban, puedes restaurar toda tu
  identidad en un dispositivo nuevo con estas 24 palabras.
- Sin la frase semilla no hay vuelta atrás. No hay ningún botón de
  "contraseña olvidada" ni ningún soporte que pudiera devolverte tu
  cuenta -- porque no hay ninguna cuenta en un servidor. tampoco tus
  contactos pueden restaurar tu identidad, por muchos que sean. Un segundo
  dispositivo con la misma identidad llegará con una versión posterior
  (véase el capítulo 11).
- Nunca pases la frase semilla a otras personas. Quien conozca estas
  palabras puede hacerse pasar por ti.

También puedes encontrar las 24 palabras más adelante en los ajustes,
en "Respaldo" -> "Mostrar frase de recuperación", por si quieres leerlas
de nuevo. En Android lo confirmas para ello con el bloqueo de pantalla.

### Añadir el primer contacto

Para chatear con alguien, primero tienes que añadir a esa persona como
contacto. Para ello hay varios caminos -- todos se explican en la
siguiente sección.

---

## 3. Contactos

### Tu invitación

Los contactos en Cleona surgen únicamente a través de una invitación. Tu
invitación está ahí desde el primer inicio -- incluso sin internet y antes
de que tu dispositivo haya encontrado un vecino. La encuentras en tu
página de detalle de identidad (toca tu propio nombre en la barra superior).

La invitación existe en dos formas que contienen exactamente lo mismo:

- como **código QR**, cuando tu interlocutor está a tu lado, y
- como **línea de texto**, que envías por correo electrónico, SMS o por
  otro mensajero.

La invitación no contiene ningún número de teléfono ni ningún nombre de
un directorio. Contiene tus claves públicas y las direcciones a través de
las cuales tu interlocutor te alcanza a ti y a tus vecinos. Para alguien
que acaba de instalar Cleona, tu invitación es por tanto también el punto
de entrada a la red.

### Escanear código QR (recomendado)

Cuando os veáis en persona:

1. Muestras a tu interlocutor el código QR de tu invitación.
2. Tu interlocutor toca el botón de más, elige "Escanear código QR" y
   dirige la cámara hacia tu pantalla. Esto también funciona con la
   cámara web de un ordenador.
3. La petición va a ti y se **acepta automáticamente** -- porque tú
   mismo acabas de mostrar el código.

Un código QR solo vale una vez: la primera petición válida se acepta,
después la invitación queda consumida. El código QR es el método más
seguro, porque durante el proceso sabéis exactamente con quién estáis
intercambiando el contacto.

### NFC (juntar los teléfonos)

Si ambos dispositivos admiten NFC:

1. Abrid ambos la función de añadir contacto.
2. Juntad vuestros teléfonos espalda con espalda.
3. La invitación se transfiere y se acepta automáticamente.

NFC, al igual que el código QR, ofrece un alto nivel de seguridad, porque
el intercambio solo funciona cuando estáis físicamente uno al lado del
otro.

### Enviar la línea de texto

Cuando no podáis veros:

1. Abre tu invitación y copia la línea de texto.
2. Envíasela a la persona que debe añadirte -- por correo, SMS o por
   otro mensajero.
3. La otra persona pega la línea en Cleona, en el diálogo de añadir
   contacto.
4. La petición aparece en tu lado bajo **"Peticiones"**. Aquí **no** se
   acepta automáticamente: decides tú mismo, porque no puedes saber quién
   más leyó la línea por el camino.

### Aceptar peticiones de contacto

Una petición entrante aún no crea un contacto. Te plantea una pregunta y
aparece en la pestaña **"Peticiones"**. Allí ves el nombre y el nivel de
verificación, y puedes elegir:

- **Aceptar** -- solo ahora la persona pasa a ser tu contacto.
- **Rechazar** -- la petición se descarta.
- **Bloquear** -- la persona no puede enviarte más peticiones.

### Nunca usar como vecino fijo

En el menú de un contacto encuentras el interruptor **"Nunca usar como
vecino fijo"** (predeterminado: desactivado). Si está activado, este
contacto no reenvía mensajes para ti y por tanto tampoco se entera de
cuándo envías o recibes mensajes. Está pensado para el caso en que la
amenaza provenga de tu propio entorno.

De desconocidos (ni contacto ni miembro de un grupo común), Cleona deja
pasar aparte de esa petición nada -- ni mensaje, ni llamada, ni archivo. Y
ni siquiera la petición llega si el
remitente no ha resuelto antes una pequeña tarea de cálculo. Eso encarece
el spam masivo.

### Niveles de verificación

Cleona te indica lo confirmada que está la identidad de un contacto:

| Nivel | Significado |
|-------|-----------|
| No verificado | Estáis conectados, pero nada confirma que realmente sea la persona correcta quien está detrás. |
| Visto | El intercambio de claves fue correcto, podéis comunicaros cifradamente. |
| Verificado | Os habéis visto en persona y os habéis conectado mediante escaneo de cámara o NFC. |
| De confianza | Has marcado este contacto explícitamente como digno de confianza. |

"Verificado" solo existe para el intercambio en persona. Una invitación
que llegó por un chat o por correo nunca alcanza este nivel -- aunque
contenga los mismos datos.

Si las claves de un contacto cambian sin previo aviso, Cleona las restablece
a "No verificado". Eso te protege de que alguien se haga pasar por tu
contacto sin que te des cuenta.

---
## 4. Mensajes

### Enviar y recibir texto

Escribe simplemente tu mensaje en el campo de entrada de abajo y pulsa
Intro o el botón de enviar. Tu mensaje se cifra automáticamente antes de
abandonar tu dispositivo.

Los mensajes entrantes aparecen en el historial del chat.

### Qué significan las marcas de tu mensaje

| Marca | Significado |
|---------|-----------|
| Reloj | El mensaje está creado, pero aún ningún camino lo ha llevado. |
| Una palomita | El mensaje está en camino. Esto también aplica mientras espera en el buzón a tu interlocutor. |
| Dos palomitas | Entregado: el dispositivo de tu interlocutor ha confirmado la recepción. |
| Signo de advertencia | Durante 14 días, ningún camino ha llevado el mensaje. Tócalo para reenviarlo. |

**Estar desconectado no es un error.** Si tu interlocutor no es alcanzable,
el mensaje se queda en una palomita hasta que se recoge -- no se ha
perdido. Si tu propio dispositivo no tiene conexión, el mensaje se queda
en el reloj y sale por sí solo en cuanto vuelve a haber un camino. El
signo de advertencia aparece solo cuando el mensaje no ha encontrado
ningún camino durante 14 días; entonces puedes reenviarlo.

Esto también se aplica a un iPhone con la app cerrada: el mensaje espera en
el buzón hasta que iOS despierte brevemente la app o hasta que tu
interlocutor la abra. Eso puede tardar más que en otros dispositivos.

Dos palomitas solo existen cuando el destinatario confirma él mismo la
recepción. Este acuse de recibo está cifrado y firmado -- nadie en el
camino puede falsificarlo para simular una entrega.

### Enviar imágenes, vídeos y archivos

Tienes varias opciones:

- **Icono de clip** en el campo de entrada: tócalo para elegir un archivo,
  una imagen o un vídeo de tu galería o de tu sistema de archivos.
- **Arrastrar y soltar** (escritorio): arrastra un archivo a la ventana
  del chat.
- **Pegar desde el portapapeles** (escritorio): copia una imagen y
  pégala en el chat.

Los archivos pequeños (menos de 256 KB) viajan directamente dentro del
mensaje. Los archivos más grandes se dividen en fragmentos y se dotan de
corrección de errores, de modo que los fragmentos individuales perdidos
no importan. Si ambos estáis en línea, se transmiten por un vecino; en
caso contrario, se depositan en dispositivos que son alcanzables de forma
permanente, hasta que tu interlocutor los recoge.

A partir de 256 KB, Cleona te pregunta por cada archivo antes de
enviarlo: un archivo grande no puede tomar el camino de tus mensajes.
Su contenido permanece cifrado y tu interlocutor no se entera de tu
dirección de internet. Pero la transferencia es visible desde fuera como
un evento, y un dispositivo ajeno que la reenvía o la guarda ve quién
sube y quién recoge. Tu consentimiento vale solo para ese único archivo.

### Mensajes de voz

1. Mantén pulsado el botón de micrófono en el campo de entrada.
2. Di tu mensaje.
3. Suelta el botón para enviar el mensaje.

Si el reconocimiento de voz está activado en tu dispositivo (véase los
ajustes), tu mensaje de voz se transcribe automáticamente a texto. Tu
interlocutor ve entonces tanto la grabación como el texto transcrito.

### Responder mensajes (citar)

Para responder a un mensaje concreto:

1. Abre el menú de tres puntos junto al mensaje.
2. Elige "Responder".
3. Sobre el campo de entrada aparece un banner con el mensaje citado.
4. Escribe tu respuesta y envíala.

El mensaje citado se muestra en tu respuesta, de modo que la referencia
queda clara.

### Editar y eliminar mensajes

- **Editar:** menú de tres puntos del mensaje, luego "Editar". Cambia el
  texto y vuelve a enviarlo. Tu interlocutor ve que el mensaje fue
  editado. La edición es posible dentro de los 15 minutos posteriores al
  envío.
- **Eliminar:** menú de tres puntos del mensaje, luego "Eliminar". El
  mensaje se elimina de tu lado y del de tu interlocutor. Puedes eliminar
  tus propios mensajes en cualquier momento -- no hay ventana temporal
  para eliminar.

### Reacciones con emoji

En lugar de escribir una respuesta, puedes reaccionar a un mensaje con un
emoji:

1. Abre el menú de tres puntos o mantén pulsado el mensaje.
2. Elige un emoji de la selección rápida o abre el selector de emoji para
   la selección completa.
3. Tu reacción aparece debajo del mensaje.

### Copiar texto

A través del menú de tres puntos de un mensaje puedes copiar el texto
del mensaje al portapapeles.

### Buscar mensajes

En el borde superior de la ventana del chat encuentras la función de
búsqueda. Introduce un término de búsqueda y Cleona te muestra todas las
coincidencias en el chat actual. Con las teclas de flecha puedes saltar
hacia delante y hacia atrás entre las coincidencias.

En la página de inicio hay además un filtro de búsqueda entre pestañas,
con el que puedes buscar un término en todas las conversaciones.

### Vista previa de enlaces

Cuando envías un enlace, Cleona genera automáticamente una vista previa
(título, descripción, imagen de vista previa). Esta vista previa se crea
en tu dispositivo y se envía junto -- tu interlocutor no tiene que
establecer conexión con el sitio web enlazado para ello.

Qué hace un toque en un enlace recibido lo configuras en los ajustes, en
"Abrir enlaces": "Normal", "Preferir ventana privada" (donde el
dispositivo no puede abrir una ventana privada, el enlace se abre
normal) o "Preguntar cada vez".

---

## 5. Grupos

### Crear un grupo

1. Cambia a la pestaña "Grupos".
2. Toca el botón de más.
3. Dale un nombre al grupo.
4. Elige los contactos que quieres invitar.
5. Toca "Crear".

Los contactos invitados reciben una notificación y pueden unirse al
grupo.

### Cómo están protegidos los mensajes de grupo

En un grupo de hasta 16 miembros, Cleona envía cada mensaje a cada
miembro individualmente -- cifrado solo para ese miembro, como si le
hubieras escrito un mensaje aparte a cada uno. Las palomitas de
un mensaje de grupo muestran el estado del miembro que menos ha avanzado.

Si el grupo crece por encima de 16 miembros, utiliza una clave
compartida. Cambia cada día y se vuelve a generar cuando un miembro
abandona el grupo o es eliminado; un miembro nuevo solo lee a partir de
su incorporación. Ahí las palomitas ya no muestran el estado de cada
miembro, sino que el mensaje está depositado en la red. Si el grupo baja
a 12 miembros o menos, vuelve al envío individual.

### Imágenes en grupos y canales

En los ajustes de un grupo o de un canal decides con
"Cargar siempre las imágenes" si las imágenes se cargan al instante o
solo cuando tocas una.

### Invitar miembros

También tras la creación puedes invitar a más contactos:

1. Abre la información del grupo (menú de tres puntos en la vista general
   de grupos o barra superior en el chat de grupo).
2. Toca "Invitar".
3. Elige los contactos que quieres añadir.

### Roles

Cada grupo tiene tres roles:

- **Propietario (Owner):** Tiene el control total. Puede añadir y
  eliminar miembros, nombrar administradores y gestionar el grupo. El
  propietario también puede transferir su estado a otro miembro.
- **Admin:** Puede eliminar miembros y ayudar con la gestión.
- **Miembro:** Puede leer y escribir mensajes.

### Abandonar un grupo

1. Abre el menú de tres puntos en la vista general de grupos.
2. Elige "Abandonar".
3. Confirma tu decisión.

Cuando abandonas un grupo, tus mensajes anteriores siguen visibles para
los demás miembros.

---

## 6. Canales públicos

### ¿Qué son los canales?

Los canales son foros de discusión públicos dentro de la red de Cleona.
A diferencia de los grupos, aquí cualquiera puede leer sin tener que ser
invitado. Solo el propietario y los administradores pueden publicar
entradas -- los suscriptores leen.

### Encontrar y unirse a canales

1. Cambia a la pestaña "Canales".
2. Abre la pestaña "Buscar".
3. Busca entre los canales disponibles por nombre o tema.
4. Toca un canal y luego "Suscribirse".

Los canales se pueden filtrar por idioma. Algunos canales están marcados
como "No apto para menores" -- estos solo son visibles si has confirmado
en tu perfil que eres mayor de 18.

### Crear tu propio canal

1. Cambia a la pestaña "Canales".
2. Toca el botón de más.
3. Introduce un nombre de canal (debe ser único en toda la red).
4. Elige el idioma y si el canal debe ser público o privado.
5. Opcional: añade una descripción y una imagen.
6. Toca "Crear".

En los canales públicos puedes determinar si el contenido se clasifica
como "No apto para menores".

### Denunciar contenidos

Si notas contenidos inadecuados en un canal público, puedes denunciarlos.
Cleona usa un sistema de moderación descentralizado: las denuncias son
evaluadas por miembros de la red elegidos al azar (una especie de
"jurado"). Si se detecta una infracción, el canal recibe una advertencia.
En caso de infracciones repetidas, se degrada en el índice de búsqueda o
se bloquea.

### Canales del sistema

Cleona dispone de dos canales del sistema integrados:

- **Bug Log:** Cuando Cleona detecta un error, te pregunta si quieres
  enviar un informe de error; antes ves exactamente lo que se publica.
  Estos informes llegan al canal Bug Log, donde la comunidad puede
  consultarlos. Un informe no lleva ningún nombre ni ningún contenido de
  tus conversaciones, sino un seudónimo. En la beta indica además tu
  identificador (User-ID), para que los desarrolladores puedan preguntar.
  También puedes enviar un informe de registro manualmente (con diálogo
  de vista previa y consentimiento explícito).
- **Feature Requests:** Aquí los usuarios pueden enviar peticiones de
  funciones y votar por propuestas existentes. Las propuestas se ordenan
  por votos.

Cada ordenador guarda hasta 25 MB por canal del sistema, cada teléfono
hasta 5 MB; cuando se llena, se va primero lo más antiguo -- nunca lo
que tú ya has visto.

---
## 7. Llamadas

### Iniciar una llamada de voz

1. Abre el chat con el contacto al que quieres llamar.
2. Toca el icono de teléfono en la barra superior.
3. Espera hasta que tu interlocutor acepte la llamada.

Durante la llamada ves una línea de tiempo, la duración de la llamada y
tienes acceso a silenciar y altavoz.

Para colgar, toca el botón rojo de colgar.

Si ves "No disponible", el dispositivo de tu interlocutor no se puede
alcanzar ahora mismo, por ejemplo un iPhone con la app cerrada. Escríbele
un mensaje en su lugar.

### Iniciar una llamada de vídeo

1. Abre el chat con el contacto.
2. Toca el icono de cámara en la barra superior.
3. Tu imagen de vídeo aparece en una ventana pequeña, la de tu
   interlocutor en la zona grande.

Durante la llamada puedes cambiar entre la cámara frontal y la trasera.

### Llamadas entrantes

Cuando alguien te llama, aparece una ventana de notificación con el
nombre del llamante. Puedes:

- **Aceptar** -- la llamada comienza.
- **Rechazar** -- el llamante recibe notificación.

Si estás en una llamada, una llamada nueva no suena; en su lugar recibes
un mensaje "Llamada perdida". Lo mismo vale para una llamada de grupo que
no hayas aceptado -- el mensaje aparece entonces en el chat de grupo.

Si alguien llama a una de tus identidades que en este momento no está
mostrada, suena de todos modos; la pantalla de la llamada indica a cuál
de tus identidades se llama.

En el iPhone solo suena mientras la app está abierta. Quien te llama
mientras está cerrada ve "No disponible" tras 10 segundos. En cuanto abras
la app, encuentras un mensaje sobre la llamada perdida.

### Llamadas de grupo

También puedes realizar llamadas de grupo en las que varias personas
participan a la vez. La llamada se organiza a través de un árbol de
reenvío inteligente, de modo que no todos los participantes tienen que
estar conectados directamente entre sí. Todas las llamadas están cifradas
de principio a fin.

Cualquier miembro del grupo puede iniciar una llamada de grupo. Dos
participantes que no son contactos entre sí nunca ven la dirección de
internet del otro: su sonido e imagen pasan por un participante que es
contacto de ambos. Si no lo hay, los dos no quedan conectados, y el
recuadro dice "Ningún contacto en común en la llamada". Si un reenvío
está saturado, queda el sonido y el vídeo desaparece para esa pareja.

### Cifrado en las llamadas

Todas las llamadas se cifran con claves de un solo uso que existen solo
durante la llamada. Tras colgar, estas claves se borran de inmediato.
Nadie puede descifrar posteriormente una llamada pasada.

Sinceramente: las llamadas se realizan, siempre que sea posible,
directamente entre los dispositivos, porque incluso un pequeño retraso
molesta al hablar. A diferencia de con los mensajes, tu proveedor de
internet puede por tanto ver, durante una llamada, a qué dirección de
internet estás conectado. Lo que decís, no lo ve.

Durante una llamada, tu contacto también ve tu dirección de internet. Si
no quieres eso con un contacto, desactívale en su menú
"Permitir llamadas" (predeterminado: activado). Si lo desactivas más
tarde, le sigue siendo conocida una dirección que ya haya visto.

---

## 8. Calendario

Cleona contiene un calendario integrado que funciona cifrado y de forma
completamente descentralizada -- sin servicio en la nube.

### Vistas

El calendario ofrece cinco vistas: día, semana, mes, año y una vista de
tareas. Cambia entre ellas a través de las pestañas en la parte superior
de la pantalla del calendario.

### Crear citas

Toca una franja horaria o usa el botón de añadir para crear una cita
nueva. Puedes introducir título, fecha, hora, lugar y notas. Las citas se
almacenan cifradas en tu dispositivo.

### Citas recurrentes

Las citas pueden repetirse diaria, semanal, mensual o anualmente. Puedes
ajustar el patrón (p. ej. cada segundo martes, el día uno de cada mes) y
fijar una fecha de fin o un número de repeticiones.

### Invitar contactos

Al crear o editar una cita puedes invitar a tus contactos de Cleona.
Reciben una invitación de calendario cifrada y pueden responder con
aceptación, rechazo o quizás. Los cambios en la cita se envían
automáticamente a todos los invitados.

### Indicación de libre/ocupado

Puedes compartir tu disponibilidad con contactos sin revelar los
detalles de la cita. Hay tres niveles de privacidad: detalles completos,
solo bloques de tiempo, u oculto. Puedes fijar un valor predeterminado y
anularlo por contacto.

### Recordatorios

Las citas pueden tener recordatorios que desencadenan una notificación
del sistema antes del inicio de la cita. Puedes posponer los
recordatorios si lo necesitas.

### Sincronización con calendarios externos

Cleona puede sincronizarse con servicios de calendario externos:

- **CalDAV** -- Conéctate a cualquier servidor compatible con CalDAV
  (Nextcloud, Radicale, etc.).
- **Google Calendar** -- Sincronización vía la API de Google Calendar con
  autenticación OAuth2 segura.
- **Servidor CalDAV local** -- Cleona puede iniciar un servidor CalDAV
  local en tu dispositivo, de modo que las apps de calendario de
  escritorio (Thunderbird, Outlook, Apple Calendar, Evolution) puedan
  sincronizarse con tu calendario de Cleona.
- **Calendario del sistema Android** -- Las citas de Cleona pueden
  transferirse a la app de calendario integrada en tu dispositivo
  Android.
- **Archivos ICS** -- Importa y exporta citas en el formato estándar
  iCalendar.

### Exportación a PDF

Puedes imprimir o exportar cualquier vista del calendario (día, semana,
mes, año) como documento PDF.

---

## 9. Encuestas

Puedes crear encuestas en cualquier chat o grupo para recabar opiniones o
planificar fechas.

### Tipos de encuesta

Cleona admite cinco tipos de encuestas:

- **Opción única** -- Los participantes eligen una opción.
- **Opción múltiple** -- Los participantes pueden elegir varias opciones.
- **Encuesta de fechas** -- Encuentra una fecha que le venga bien a todos.
  Cada participante marca las fechas como disponible, quizás o no
  disponible.
- **Escala** -- Valora algo en una escala numérica (p. ej. de 1 a 5).
- **Texto libre** -- Los participantes escriben su propia respuesta.

### Crear una encuesta

Abre un chat y toca el icono de encuesta (o usa el menú de adjuntos).
Elige el tipo de encuesta, formula tu pregunta y las opciones, y envía
la encuesta. Aparece como un mensaje en el chat.

### Votar

Toca una encuesta para emitir tu voto. Puedes cambiar o retirar tu voto
en cualquier momento.

### Votación anónima

Las encuestas se pueden configurar para votación anónima. Si se activa,
los votos son anónimos criptográficamente -- nadie, ni siquiera el
creador de la encuesta, puede ver quién votó qué. El recuento de votos
sigue siendo visible de todos modos.

### Encuesta de fechas al calendario

Cuando una encuesta de fechas ha terminado, la fecha ganadora se puede
convertir con un toque directamente en una entrada de calendario.

---
## 10. Múltiples identidades

### ¿Por qué múltiples identidades?

Imagina que quieres separar tu vida profesional y tu vida privada -- de
forma parecida a tener dos números de teléfono distintos, pero sin un
segundo teléfono. En Cleona puedes usar varias identidades en un
dispositivo. Cada identidad tiene su propio nombre, su propia foto de
perfil, sus propios contactos y sus propias conversaciones.

### Crear una identidad nueva

1. En la barra superior ves tu identidad actual como pestaña.
2. Toca el signo de más (+) a la derecha de tus pestañas de identidad.
3. Introduce un nombre para la nueva identidad.
4. Listo -- la nueva identidad está activa de inmediato.

### Cambiar entre identidades

Toca simplemente la pestaña de identidad en la barra superior. El cambio
es inmediato -- sin tiempo de espera, sin recargar.

### Todas funcionan a la vez

Un punto importante: todas tus identidades están activas al mismo
tiempo. Aunque ahora mismo se te muestre como "Profesional", tu
identidad "Privada" sigue recibiendo mensajes. No te pierdes nada, sin
importar qué identidad tengas seleccionada ahora.

### Página de detalle de identidad

Cuando tocas la pestaña de tu identidad activa en este momento, se abre
la página de detalle. Aquí puedes:

- Mostrar tu código QR para contactos.
- Cambiar o eliminar tu foto de perfil.
- Añadir una descripción de perfil.
- Cambiar tu nombre para mostrar.
- Elegir un diseño (skin) para esta identidad.
- Eliminar la identidad, si ya no la necesitas.

### Eliminar una identidad

Cuando eliminas una identidad, tus contactos son notificados de ello. La
identidad y todos los datos asociados se eliminan de tu dispositivo.
Este proceso no es reversible.

---

## 11. Varios dispositivos

### Una identidad, un dispositivo -- por ahora

Una identidad funciona hoy en un dispositivo. Un segundo dispositivo
para la misma identidad llegará con una versión posterior; en los
ajustes, bajo "Dispositivos" -> "Gestionar dispositivos",
"Emparejar otro dispositivo" figura por eso todavía como
"Aún no disponible".

Cuando llegue, valdrá lo siguiente: Todos los dispositivos tendrán los
mismos derechos, no habrá ningún dispositivo principal. Un dispositivo
adicional lo configuras con tus 24 palabras, y uno de tus dispositivos
hasta entonces debe dar su consentimiento. Como máximo 5 dispositivos.

Si hoy introduces tus 24 palabras en un dispositivo nuevo, te mudas: la
identidad se restaura en el dispositivo nuevo y tu dispositivo hasta
entonces la elimina después de sí (véase el capítulo 12).

En varios dispositivos puedes usar hoy identidades distintas (capítulo
10).

### Rotar claves de identidad

Si sospechas que alguien ha conseguido tus claves, puedes generar claves
nuevas en "Gestionar dispositivos" -> "Rotar claves de identidad". Tus
contactos son notificados, tus invitaciones abiertas quedan revocadas.
Importante: después, las 24 palabras por sí solas vuelven a producir solo
las claves antiguas. Crea por eso justo después un paquete de
recuperación nuevo; a partir de entonces solo podrás restaurar junto con
ese paquete.

---

## 12. Recuperación

### Usar la frase semilla

Cuando pierdes tu dispositivo o configuras uno nuevo:

1. Instala Cleona en el dispositivo nuevo.
2. Elige "Restaurar" al iniciar.
3. Introduce tus 24 palabras.
4. Cleona genera a partir de ellas todas tus identidades de nuevo -- con
   las mismas claves que antes. Para tus contactos eres la misma
   persona.

### Qué vuelve -- y qué no

Tu identidad está en las 24 palabras; tus contactos y tu historial, no.
Lo que vuelve es tu acceso a la red a través del **paquete de
recuperación**: tu dispositivo deposita un pequeño paquete cifrado en la
red. Solo tus 24 palabras pueden encontrarlo y abrirlo. Dentro dice lo
que tu nuevo dispositivo necesita para volver a alcanzar a tus contactos,
y lo que mientras tanto estuvo guardado para ti en la red. Para eso no
hace falta que ningún contacto esté en línea.

El historial de chat anterior no lo devuelve una restauración.

El paquete de recuperación dura 7 días y tu dispositivo lo renueva
mientras funciona; en los ajustes ves hasta cuándo vale. Si durante más
de 7 días no ha funcionado ninguno de tus dispositivos, ha caducado.
Entonces las 24 palabras restauran tu identidad igualmente, pero a tus
contactos tienes que invitarlos de nuevo; lo que mientras tanto estuvo
guardado para ti en la red está perdido.

### Restaurar significa mudarse

Si tu dispositivo hasta entonces descubre más tarde que la identidad fue
restaurada en otro lugar, la elimina de sí mismo -- junto con su
historial. Por eso: quien tenga tus 24 palabras puede llevarse así tu
identidad desde tu dispositivo. Hasta que todos los contactos hayan
vuelto, la app te lo recuerda; con "Finalizar y renovar claves" terminas
tú mismo la restauración.

### Lo que nadie puede restaurar

Esto es importante, y por eso lo decimos claramente:

- **Nadie excepto tú puede restaurar tu identidad.** Ni el desarrollador,
  ni un soporte, y tampoco tus contactos -- por muchos que sean. No hay
  ninguna clave maestra ni ninguna parte de tu clave que esté depositada
  en otros.
- **Si has perdido las 24 palabras y no te queda ningún dispositivo, tu
  identidad está perdida.** Entonces solo queda crear una nueva y volver
  a invitar a tus contactos.

La mejor protección: anota las 24 palabras en papel y guárdalas de
forma segura.

---
## 13. Ajustes

Los ajustes los alcanzas a través del icono de engranaje en la esquina
superior derecha.

### Notificaciones y tonos de llamada

- Elige entre seis tonos de llamada distintos para las llamadas
  entrantes.
- Configura un tono de mensaje.
- En dispositivos Android puedes además activar o desactivar la
  vibración.
- **"Silenciar todo"** hace que en este dispositivo ningún mensaje vuelva
  a sonar, vibrar ni anunciarse -- para todas las identidades. Las
  llamadas siguen sonando.
- Las **"Horas de silencio"** las fijas por identidad con Desde/Hasta.
  Durante ese tiempo, ningún mensaje de esa identidad suena, vibra ni se
  anuncia; los mensajes llegan de todos modos.
- **"Notificaciones sin contenido"** (predeterminado: desactivado)
  muestra solo que ha llegado un mensaje, invitación o recordatorio --
  sin remitente, nombres ni texto. Las llamadas siguen mostrando el
  nombre.
- Lo que llega de golpe tras el inicio lo anuncia Cleona en un aviso
  conjunto ("5 mensajes nuevos en 2 conversaciones"); todo lo posterior,
  individualmente. Un toque en un aviso de mensaje abre la conversación,
  también en otra identidad.

### Diseños (skins)

Cleona ofrece diez diseños distintos: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold y Contrast. El diseño Contrast cumple
el nivel de accesibilidad más alto (WCAG AAA) y es especialmente legible
con visión limitada.

Cada identidad puede tener su propio diseño. Cambias el diseño en la
página de detalle de identidad (toca la pestaña de identidad activa).

Además, puedes cambiar entre el tema claro, oscuro y el del sistema en
los ajustes, en "Apariencia".

### Cambiar idioma

Cleona está disponible en 34 idiomas, entre ellos idiomas con escritura
de derecha a izquierda (p. ej. árabe, hebreo). Cambia el idioma en los
ajustes, en "Idioma".

### Archivado de medios

Si tienes en casa un almacenamiento en red (NAS) o una carpeta
compartida, Cleona puede descargar tus medios allí automáticamente. Se
admiten SMB, SFTP, FTPS y WebDAV.

Así funciona el almacenamiento por niveles:
- Los primeros 30 días: todo permanece en tu dispositivo.
- Tras 30 días: una imagen de vista previa permanece en el dispositivo,
  el original se archiva.
- Tras 90 días: solo una pequeña imagen de vista previa permanece en el
  dispositivo.
- Tras un año: solo queda un marcador de posición, el original está
  guardado de forma segura en el archivo.

Puedes tocar en cualquier momento un medio archivado para recuperarlo --
siempre que estés conectado a tu red doméstica. Los medios especialmente
importantes se pueden fijar para que nunca se descarguen.

En "Presupuesto de almacenamiento" fijas cuántos MB de medios permanecen
en el dispositivo (predeterminado: 100 MB en el teléfono, 2 GB en el
ordenador). Cuando está lleno, se archiva primero el medio más antiguo
no fijado. Un original solo se elimina cuando está a salvo en el
archivo -- los mensajes de texto siempre se conservan.

### Transcripción de mensajes de voz

Si está activado, tus mensajes de voz se convierten en texto localmente
en tu dispositivo (con el modelo de código abierto Whisper). El texto
transcrito se envía junto con la grabación a tu interlocutor. La
transcripción se realiza completamente en tu dispositivo -- no se envían
datos a servicios externos.

Qué modelo (tiny, base, small) se descarga lo configuras una vez por
dispositivo; el idioma (automático o fijo), por identidad.

### Descarga automática

Puedes configurar a partir de qué tamaño los medios deben descargarse
automáticamente. Así puedes, por ejemplo, dejar que las imágenes se
carguen automáticamente, pero decidir manualmente con los vídeos grandes.

### Dispositivos

En "Dispositivos" -> "Gestionar dispositivos" ves este dispositivo.
Emparejar otro dispositivo llegará con una versión posterior (capítulo 11).

### Red

Cleona no necesita ajustes de red para funcionar. Hay tres interruptores
de red:

- **Apertura de puertos en el router** (predeterminado: activado).
  Cleona pide a tu propio router que abra una puerta para Cleona. Si
  funciona, tu dispositivo es mejor alcanzable para otros y ayuda a la
  red. Cleona solo habla con tu router, no con internet.
- **Entradas de dirección públicas** (predeterminado: activado). Si tu
  dispositivo aún tiene pocos vecinos, busca más puntos de entrada en un
  directorio público (Nostr), y si él mismo es bien alcanzable, se
  registra allí. La entrada contiene una dirección, ningún nombre y
  ningún contacto. Si lo desactivas, tu dispositivo solo encuentra
  vecinos a través de invitaciones, la red local y los vecinos que ya
  conoce.
- **Menos paquetes de cobertura en la Wi-Fi** (predeterminado:
  desactivado). En la Wi-Fi o por cable puedes desactivar los paquetes
  de cobertura vacíos. Pero entonces vuelve a ser visible cuándo estás
  escribiendo. En los datos móviles no existe este interruptor -- allí
  Cleona envía de todos modos solo un paquete de cobertura por minuto.

El tráfico de cobertura en su conjunto no se puede desactivar. Esto es
intencionado: solo si siempre está funcionando, la actividad de tu
dispositivo no dice nada sobre si estás escribiendo en este momento.

Encima de los tres interruptores está el **modo de ahorro de datos**: en
los datos móviles Cleona te lo sugiere, pero nunca lo activa por sí solo.
Ahorra datos; a cambio, tu dispositivo es desde fuera más fácil de
reconocer.

Debajo configuras el **"Caché para medios de otras personas"**: tu
dispositivo guarda partes cifradas de medios de otras personas hasta
7 días, para que alcancen a sus destinatarios (predeterminado: 100 MB en
el teléfono, 1 GB en el ordenador). Un tamaño menor libera el espacio de
inmediato -- primero las partes más antiguas.

---

## 14. Seguridad

### ¿Qué significa cifrado post-cuántico?

El cifrado actual se basa en problemas matemáticos que son extremadamente
difíciles de resolver para ordenadores normales. Los ordenadores
cuánticos podrían resolver algunos de estos problemas rápidamente en el
futuro. El cifrado post-cuántico utiliza procedimientos adicionales que
también resisten a los ordenadores cuánticos.

Cleona combina ambos enfoques: cifrado clásico para fiabilidad y
procedimientos post-cuánticos para seguridad futura. Así estás protegido
contra amenazas actuales y futuras a la vez.

Para cada mensaje individual se genera una clave propia. Aunque un
atacante descifrara la clave de un mensaje, no podría leer ningún otro
mensaje con ella.

### Por qué no tener servidor es más seguro

En los mensajeros convencionales, tus mensajes pasan por los servidores
del proveedor. Aunque allí puedan estar cifrados: el proveedor tiene
acceso a metadatos (quién se comunica con quién, cuándo, con qué
frecuencia, desde dónde) y podría tener que entregarlos por orden
judicial.

En Cleona no existe ese punto central. No hay ningún lugar donde
converjan todos los metadatos, ni ningún directorio en el que se pueda
consultar quién eres o a quién conoces.

### ¿Quién ve que estás escribiendo con alguien?

El cifrado protege **qué** escribes. Igual de importante es que ningún
observador individual se entere de **con quién** y **cuándo** escribes.
Cleona lo asegura así:

- **En internet nunca directamente.** Si tu dispositivo enviara un
  mensaje directamente a la dirección de internet de tu interlocutor, tu
  proveedor podría ver con quién estás escribiendo. Por eso un mensaje en
  internet va siempre a través de vuestros vecinos fijos: los tuyos y los
  de tu interlocutor.
- **Vecinos en los que confías.** Tus vecinos fijos son, siempre que sea
  posible, dispositivos de tus propios contactos -- hasta tres que estén
  alcanzables desde fuera en ese momento. Si uno cae, sube otro
  contacto. Un contacto no se puede comprar con servidores; un nodo
  cualquiera de la red sí. Si aún no tienes ningún contacto alcanzable,
  Cleona toma otro vecino. Tu invitación nunca nombra a ninguno de tus
  contactos, para que nadie se entere a través de ellos de la dirección
  de un amigo.
- **Códigos en lugar de nombres.** Los vecinos no ven nombres ni
  identificadores, sino solo un código. Vale exactamente para vosotros
  dos, en una dirección, durante un día -- al día siguiente es otro
  distinto. Tu vecino sabe de dónde viene el paquete, pero no adónde va
  al final. El vecino de tu interlocutor sabe adónde va, pero no de dónde
  vino. Normalmente, nadie en el camino ve ambos extremos.
- **El tráfico de cobertura.** Tu dispositivo envía continuamente, a
  intervalos irregulares, paquetes de cobertura a sus vecinos. Son igual
  de grandes que los paquetes reales, van por el mismo puerto y desde
  fuera son indistinguibles de ellos. Si en este momento escribe un ser
  humano o el dispositivo simplemente está funcionando no se puede
  distinguir a partir de ello. Tus mensajes nunca esperan al tráfico de
  cobertura -- salen de inmediato, este solo funciona en paralelo.

**Lo que cuesta el tráfico de cobertura:** En la Wi-Fi unos 13 MB al
día. En los datos móviles, Cleona envía solo un paquete de cobertura por
minuto, eso son unos 1,7 MB al día. El motivo de la limitación en los
datos móviles no es el volumen de datos, sino la batería: cada paquete
despierta el módem de radio.

**Lo que Cleona no puede ocultar** -- sinceramente:

- Ningún **único** observador ve quién escribe con quién -- ni tu
  proveedor ni los nodos en el camino. Quien sin embargo vigile **ambos
  extremos a la vez**, por ejemplo un Estado que observa tu conexión y
  la de tu interlocutor o que controla ambos vecinos, puede correlacion
  con el tiempo: paquete sale de tu lado, poco después entra un paquete
  en tu interlocutor. Repetido con suficiente frecuencia, eso da una
  conexión.
- El tráfico de cobertura dificulta esta correlación, pero no la
  impide. Oculta mensajes individuales, no el volumen: quien envía mucho
  aumenta el tráfico total de su dispositivo.
- Un contacto que es tu vecino fijo se entera de **cuándo** y **cuánto**
  envías y recibes -- no con quién y no qué. Si la amenaza proviene de
  tu propio entorno, puedes eximir a cada contacto de ello (véase el
  capítulo 3, "Nunca usar como vecino fijo").
- Si dos usuarios nuevos solo tienen el mismo vecino, su mensaje va
  por exactamente ese nodo, y este ve ambos extremos. En cuanto uno de
  los dos tenga más vecinos, eso se acaba.
- Tu invitación contiene tus direcciones de internet. Quien tenga la
  línea de texto ve dónde estás en línea -- dásela solo a personas de
  las que te fíes para eso.
- Un vecino que reenvía ve que dos códigos intercambian paquetes -- no
  quién está detrás, y no qué hay dentro.
- Una señal de una llamada en curso puede, si el primer vecino no
  responde en ese momento, pasar por un nodo que ve ambos extremos; este
  se entera de que estáis hablando juntos por teléfono.
- Un archivo grande al que has dado tu consentimiento lo ve el ordenador
  que lo reenvía o lo guarda, por ambos extremos (véase el capítulo 4).
- Para las llamadas no se aplica la protección frente al proveedor, y tu
  contacto ve tu dirección de internet (véase el capítulo 7).

### ¿Qué pasa cuando tu interlocutor está desconectado?

1. Cleona arranca todos los caminos adecuados a la vez: en la misma Wi-Fi
   directamente, en internet a través de dos vecinos -- y además el
   buzón.
2. Para el buzón, Cleona deposita el mensaje cifrado en tres vecinos.
   En cuanto dos confirman la recepción, se considera depositado.
3. Cleona elige para ello preferentemente vecinos en los que tu
   interlocutor también busca -- primero el vecino que nombra su
   invitación.
4. El mensaje espera allí hasta 7 días. Cuando tu interlocutor vuelve,
   lo recoge y te confirma la recepción. Solo entonces ves dos
   palomitas.

El buzón solo puede vaciarlo tu interlocutor: recogerlo y eliminarlo
solo funciona con una clave que solo él posee, y la eliminación se
produce solo cuando ha confirmado la recepción. Los vecinos solo ven
paquetes cifrados bajo un valor que cambia cada día.

### Los desconocidos no pasan

De alguien que ni es tu contacto ni miembro de un grupo común, Cleona
acepta exactamente dos cosas:
la petición de tus claves públicas, mientras una de tus invitaciones
esté abierta, y una petición de contacto. La petición debe llevar una
invitación válida tuya, y el remitente debe haber resuelto antes una
tarea de cálculo. Todo lo demás -- mensajes, llamadas, archivos -- se
descarta antes de que llegue siquiera a la app. Quien solo tiene tu
tarjeta de visita impresa no puede por tanto simplemente llamarte. Un
miembro de un grupo común te alcanza solo en ese grupo -- con mensajes
de grupo y llamadas de grupo, nunca individualmente.

### Anticensura

Cleona está construido para que sea difícil de bloquear:

- **Sin servidor, sin dirección fija.** En la app no hay ninguna
  dirección que se pueda bloquear, y la red no depende de ningún nodo
  concreto.
- **Sin puerto fijo.** Cada dispositivo elige un puerto aleatorio en el
  primer inicio. No hay ningún número de puerto conocido por el que se
  pueda reconocer el tráfico de Cleona.
- **Como datos aleatorios.** El establecimiento de conexión entre dos
  dispositivos está codificado de modo que es indistinguible de datos
  aleatorios.
- **Muchos puntos de entrada.** Cada invitación, cada vecino y cada
  dispositivo en la misma Wi-Fi es un camino posible de vuelta a la red.

### Almacenamiento seguro de claves

En las plataformas admitidas, Cleona almacena tus claves de cifrado en
el llavero seguro del sistema operativo (Android Keystore, iOS
Keychain, macOS Keychain). Donde esté disponible, eso ofrece protección
respaldada por hardware para tus claves.

### Cifrado de la base de datos

Tus mensajes y conversaciones están en una base de datos cifrada -- una
propia para cada identidad, cada una con su propia clave. No solo se
cifra la propia base de datos, sino también sus archivos intermedios;
nada se escribe sin cifrar en el disco, ni siquiera brevemente. Los
ajustes, los contactos y los medios también están almacenados cifrados.

Las claves se derivan de tus 24 palabras y existen solo en tu
dispositivo. Aunque alguien se apodere de tu dispositivo y lea los
datos, sin estas claves solo encuentra datos ilegibles.

Sin cifrar está solo donde tú mismo sacas contenidos de Cleona:
- cuando guardas un archivo de un chat en tu dispositivo,
- cuando con el botón de captura de pantalla guardas una imagen en tus
  imágenes,
- cuando compartes algo con otra app,
- cuando configuras el archivado de medios (capítulo 13): los originales
  archivados están sin cifrar en tu almacenamiento en red de casa, para
  que puedas abrirlos allí también sin Cleona,
- cuando reflejas citas en el calendario del sistema Android: allí
  pueden leerlas otras apps con acceso al calendario.

Lo que así ha salido no se elimina con el mensaje y tampoco caduca con
él.

### Protección en la pantalla

En Android, Windows y macOS, Cleona no permite que otras apps hagan
capturas de pantalla. Si necesitas una imagen, usa el botón de captura de
pantalla en la barra superior: guarda la imagen en tus imágenes -- sin
cifrar. En una conversación en la que reenviar no está permitido, no hay
captura de pantalla.

---

## 15. Actualizaciones de software

### ¿Cómo obtengo actualizaciones?

Cleona se puede actualizar por diversos caminos. El objetivo es que
puedas recibir actualizaciones incluso cuando canales de distribución
individuales fallen o sean bloqueados:

1. **App Store / Play Store:** En cuanto Cleona aparezca allí y lo hayas
   instalado a través de una tienda, recibes las actualizaciones como de
   costumbre a través de la tienda. En el iPhone, las actualizaciones
   llegan a través de TestFlight.
2. **GitHub Releases:** En la página de GitHub del proyecto encuentras
   paquetes de instalación firmados para todas las plataformas.
3. **Actualizaciones por la red:** Cleona puede obtener una
   actualización directamente por la red -- sin servidor de descarga.
   La nueva versión se divide en fragmentos con corrección de errores
   que se reparten por la red; una parte viaja incluso junto con el
   tráfico de cobertura. Tu dispositivo reúne suficientes fragmentos y
   compone la actualización. Normalmente solo se transfiere el cambio --
   unos pocos MB en lugar de toda la app. Esto vale para Linux, Windows y
   Android; en macOS descargas versiones nuevas del sitio web o de
   GitHub.
4. **Enlaces de invitación:** Puedes crear enlaces de invitación que
   contienen todo lo que un usuario nuevo necesita para instalar Cleona
   y conectarse a la red.
5. **Transferencia física:** En entornos sin internet puedes pasar
   Cleona a otros por memoria USB o en la red local.

### Cómo se desarrolla una actualización

1. Cleona recoge los fragmentos de una actualización nueva
   automáticamente en segundo plano y los compone.
2. Solo cuando la actualización está **completa** y su **firma ha sido
   verificada** te la ofrece Cleona. Nunca se te ofrece por tanto una
   actualización a medias o sin verificar.
3. Al tocar "Instalar", la instalación se inicia sin más consulta. En
   Android, el sistema muestra además su diálogo de instalación.

No se ofrecen versiones más antiguas -- una actualización siempre solo
va hacia delante. Si una versión es tan antigua que ya no puede cooperar
con la red, Cleona lo indica claramente y te pide que actualices.

### Verificación de firma

Cada actualización está firmada dos veces: con un procedimiento clásico
y uno post-cuántico. Cleona verifica ambas firmas automáticamente. Así
se garantiza que solo se acepten actualizaciones del desarrollador
oficial -- aunque la actualización haya llegado por la red desde
dispositivos ajenos. Una actualización nunca se crea automáticamente a
partir del desarrollo, sino solo cuando el desarrollador la firma a
mano.

---
## 16. Preguntas frecuentes

### "¿Puedo usar Cleona sin internet?"

Cleona necesita una conexión de red, pero no necesariamente internet: en
la misma Wi-Fi los dispositivos Cleona se encuentran por sí mismos y
pueden escribir entre ellos completamente sin acceso a internet. Tener
que estar en línea a la vez con tu interlocutor no es necesario: si está
desconectado, el mensaje espera hasta 7 días en el buzón de tres vecinos,
hasta que lo recoge.

### "¿Qué pasa si pierdo mi frase semilla?"

Mientras aún funcione un dispositivo con tu identidad, no hay nada
perdido -- allí simplemente sigues escribiendo. En el dispositivo en el
que creaste la identidad, además puedes normalmente volver a leer las 24
palabras (véase el capítulo 2). No te fíes de ello: una reinstalación
elimina esa copia, y en Android también la destruye quitar o cambiar el
bloqueo de pantalla. Si no tienes ni las palabras ni un dispositivo, no
hay vuelta atrás -- tampoco a través de tus contactos, del desarrollador
o de cualquier otra persona. Por eso es tan importante guardar de forma
segura las 24 palabras.

### "¿Puede alguien leer mis mensajes?"

No. Cada mensaje se cifra con una clave de un solo uso que solo vale
para ese único mensaje. Solo tú y tu interlocutor podéis descifrar el
mensaje. No hay ningún servidor central, ninguna clave maestra y ningún
acceso para el desarrollador. Aunque un dispositivo reenvíe el mensaje
en el camino de transporte, solo ve datos cifrados ilegibles y un
código. Tu vecino sabe que el paquete viene de ti, pero no a quién va;
el vecino de tu interlocutor sabe a quién va, pero no de quién.

### "¿Por qué no necesito ningún número de teléfono?"

Porque tu identidad es puramente criptográfica. En lugar de un número de
teléfono o una dirección de correo electrónico vinculados a tu nombre
real, te identifica un par de claves que se generó en tu dispositivo.
Añades contactos por código QR, NFC o la línea de texto de tu invitación
-- no a través de una agenda telefónica. Eso significa más privacidad,
porque tu cuenta de mensajería no está vinculada a tu identidad real.

### "¿Cómo encuentro gente en Cleona?"

Cleona deliberadamente no tiene búsqueda de contactos por número de
teléfono o nombre -- eso sería un problema de privacidad. En su lugar,
intercambias invitaciones directamente: por código QR, NFC o como línea
de texto por otro camino. Eso es como intercambiar tarjetas de visita
en vez de buscar en una agenda telefónica.

### "¿Funciona Cleona también en el extranjero?"

Sí. Mientras tengas conexión a internet, Cleona funciona en cualquier
parte del mundo. Como no hay ningún servidor central ni ninguna dirección
fija, el servicio no se puede simplemente desconectar para países
concretos. Cómo dificulta Cleona los bloqueos se describe en el capítulo
"Seguridad", en "Anticensura". Un país que bloquee todo tráfico
desconocido en la frontera puede, sin embargo, detener también Cleona.

### "¿Es Cleona gratuito?"

Sí. Cleona se puede usar de forma gratuita y sin publicidad. Como no hay
ningún servidor central, tampoco se producen costes de servidor para el
funcionamiento. En los ajustes, en "Apoya a Cleona" -> "Donar", puedes
apoyar el desarrollo de forma voluntaria.

### "Mi mensaje tiene solo una palomita -- ¿qué significa?"

El mensaje está en camino, pero tu interlocutor aún no ha confirmado la
recepción -- la mayoría de las veces porque está desconectado en este
momento. Eso no es un error: el mensaje espera hasta 7 días en el
buzón. En cuanto lo recoge, ves dos palomitas. Un reloj significa que
aún ningún camino ha llevado el mensaje -- sale por sí solo en cuanto hay
uno; un signo de advertencia, que durante 14 días no ha encontrado ningún
camino y puedes reenviarlo.

### "¿Por qué llegan tarde los mensajes en mi iPhone?"

iOS no deja que las apps se ejecuten permanentemente en segundo plano.
Cleona solo se despierta brevemente de vez en cuando; cuándo, lo decide
iOS. Entonces lo recoge todo. En cuanto abras la app, Cleona recoge lo que
se guardó para ti.

### "¿Puedo cambiar de WhatsApp a Cleona?"

Sí, pero no puedes transferir tus chats de WhatsApp. Cleona y WhatsApp
son sistemas fundamentalmente distintos. Tienes que añadir tus contactos
uno a uno en Cleona. Lo más sencillo es enviar la línea de texto de tu
invitación a tus contactos. Cada petición que llegue así la confirmas tú
mismo en "Peticiones".

### "¿Puedo usar Cleona en varios dispositivos a la vez?"

Todavía no. Un segundo dispositivo para la misma identidad llegará con
una versión posterior (capítulo 11). En varios dispositivos puedes usar
hoy identidades distintas.

### "¿Cómo obtengo actualizaciones si la tienda de apps está bloqueada?"

Cleona puede obtener actualizaciones directamente por la red, sin
depender de una tienda de apps, un sitio web o un servidor de descarga.
Si otro dispositivo en la red tiene la versión más reciente, tu
dispositivo puede cargar la actualización desde allí. La autenticidad se
verifica mediante una firma digital del desarrollador. Alternativamente,
un contacto puede pasarte la app mediante un enlace de invitación o una
memoria USB. Más sobre esto en el capítulo "Actualizaciones de software".

---

## Ayuda y contacto

Si tienes preguntas o te encuentras con un problema, encuentras
información actualizada en el sitio web de Cleona y en GitHub. Como
Cleona es un proyecto descentralizado, no hay soporte al cliente clásico
-- pero sí una comunidad activa que ayuda con gusto.

---

*Este manual describe Cleona Chat versión 4.2. Funciones individuales
pueden cambiar o ampliarse en versiones más recientes.*