---
layout: post
title: "Kiroku y mi intento de implementar un sistema Zero Knowledge"
tags: dev security
---

## .::0x00::Contexto::.

Kiroku partió como un proyecto personal. Nunca pretendió transformarse en el
producto en el que se está transformando ahora. Nació porque yo necesitaba una
forma más estructurada de documentar mis rutinas de mentalismo. Grabarme,
transcribir lo que decía, insertar fotos de momentos clave y ordenar ideas que
surgían naturalmente en el momento. Durante mucho tiempo fue eso, una
herramienta interna que me permitía convertir una grabación en un guión usable,
con un PDF listo para imprimir.

El problema apareció cuando dejé de pensarla como algo solo para mí y cuando
empecé a mostrársela a mis colegas. Recuerdo perfectamente que cuando se volvió
una posibilidad real que otros performers la usaran, hubo una pregunta que no
pude ignorar: ¿por qué alguien confiaría en una herramienta cuyo contenido es
accesible por mí como administrador del sistema? Como performer, entiendo que
un guión puede contener información de caracter sensible. Información que
honestamente no me gustaría compartir con nadie. Y por otro lado, como hacker,
empatizo con la idea de no querer guardar mis guiones en un ambiente no
controlado por mí. Si la arquitectura de mi aplicación me permite ver los
guiones de otros, entonces la confianza depende únicamente de mi buena
voluntad, y eso, desde cualquier perspectiva de seguridad, es un diseño débil.

Ese fue el punto de inflexión. Cuando me di cuenta de que bajo la arquitectura
que tenía, yo mismo era un insider threat perfectamente válido. Y si yo podía
leer los artefactos finales en texto plano, entonces cualquier persona que
comprometiera el backend también podría hacerlo. A partir de ahí, la seguridad
dejó de ser un detalle técnico y se volvió una condición estructural del
proyecto.


## .::0x01::Cómo funciona Kiroku::.

Antes de hablar de seguridad, es importante entender cómo funciona el sistema
en términos funcionales, porque la arquitectura de seguridad que terminé
implementando está completamente condicionada por el flujo de datos.

Un "proyecto" en Kiroku comienza cuando el usuario inicia una grabación desde
el cliente web. El frontend abre un WebSocket hacia el backend y empieza a
enviar chunks de audio cada diez segundos. Esos chunks no son archivos válidos
por sí mismos, son bloques de bytes que luego deben ser reconstruidos. Si
durante la grabación el usuario toma fotos, estas también se envían junto con
un timestamp que indica el momento exacto en que fueron capturadas. Esa
relación temporal es relevante, porque más adelante determina dónde se
insertarán en el guión final.

Este el flujo con muchas simplificaciones.

{% asciiart left %}
+---------+     +------------------+     +-----------------+     +----------+     +------------------+
| Usuario |     | Frontend (React) |     | Backend (Flask) |     | Postgres |     | Redis (RQ Queue) |
+----+----+     +---------+--------+     +--------+--------+     +-----+----+     +---------+--------+
     |                    |                       |                    |                    |
     | 1. Empezar grabación                       |                    |                    |
     +------------------->|                       |                    |                    |
     |                    | 2. POST /api/project/start                 |                    |
     |                    +---------------------->|                    |                    |
     |                    | 3. WS open /ws/audio  |                    |                    |
     |                    +---------------------->|                    |                    |
     |                    | 4. WS audio_chunk_n (bytes)                |                    |
     |                    +---------------------->|                    |                    |
     |                    |                       | 5. Guarda chunk temporal                |
     |                    |                       +------.             |                    |
     |                    |                       |<-----´             |                    |
     | 6. Toma foto       |                       |                    |                    |
     +------------------->|                       |                    |                    |
     |                    | 7. POST /api/photo (image_bytes + timestamp_ms)                 |
     |                    +---------------------->|                    |                    |
     |                    |                       | 8. Guarda imagen temporal (storage temp/)
     |                    |                       +------.             |                    |
     |                    |                       |<-----´             |                    |
     |                    |                       | 9. INSERT photo(project_id, timestamp)  |
     |                    |                       +------------------->|                    |
     | 10. Detener grabación                      |                    |                    |
     +------------------->|                       |                    |                    |
     |                    | 11. POST /api/project/stop                 |                    |
     |                    +---------------------->|                    |                    |
     |                    |                       | 12. enqueue prepare_project(project_id) |
     |                    |                       +---------------------------------------->|
     |                    |                       |                    |                    |
+----+----+     +---------+--------+     +--------+--------+     +-----+----+     +---------+--------+
| Usuario |     | Frontend (React) |     | Backend (Flask) |     | Postgres |     | Redis (RQ Queue) |
+---------+     +------------------+     +-----------------+     +----------+     +------------------+
{% endasciiart %}

Una vez que el usuario termina la grabación, entra en juego un pipeline de
workers. Hay un worker que actúa como orquestador y coordina el resto del
proceso. Otro worker reconstruye los chunks en un archivo de audio válido.
Luego ese audio se segmenta en fragmentos más pequeños y cada segmento se envía
a un worker de transcripción que utiliza la API de OpenAI. Si el usuario tiene
habilitada la estilización de imágenes, cada foto se encola para ser procesada
mediante la API de Gemini, con un prompt específico que transforma la imagen en
un estilo más cercano a las fotos que siempre se usan en los libros de magia.

El worker de finalización toma las transcripciones, las fotos procesadas (o
originales si no se estilizaron), ordena todo según los timestamps y genera un
archivo Markdown que representa el guión completo. A partir de ese Markdown se
genera un HTML con imágenes embebidas en base64 y, posteriormente, un PDF y un
DOCX. Esos son los artefactos finales que sobreviven. Los datos efímeros, como
los chunks originales o las transcripciones intermedias, se eliminan una vez
que el proyecto queda finalizado.

A nivel de infraestructura, el sistema está compuesto por un frontend en React,
un backend en Flask, workers en Python usando RQ, Postgres como base de datos,
un Redis para sesiones y otro para colas de trabajo, y un object storage
compatible con S3, en mi caso MinIO. En desarrollo puedo usar disco local por
comodidad, pero en producción la abstracción de storage apunta a un backend
S3-compatible.

Todo lo anterior describe cómo fluye la información desde la grabación hasta el
artefacto final. Y bajo la primera arquitectura que implementé, esos artefactos
terminaban almacenados en texto plano en el mismo entorno al que el backend
tenía acceso directo.


## .::0x02::La arquitectura que tenía::.

La primera versión era funcional y sencilla. El backend y los workers
compartían acceso al mismo storage, inicialmente un volumen montado en Docker.
Los workers generaban los artefactos finales en ese volumen y el backend los
servía cuando el usuario los solicitaba. Desde el punto de vista del
desarrollo, era cómodo y fácil de depurar.

El problema es que esa comodidad se traduce directamente en superficie de
ataque. Si un atacante logra ejecución remota en el backend, obtiene acceso al
entorno del proceso. Puede leer variables de entorno, puede conectarse a
Postgres usando las credenciales disponibles, puede leer Redis y puede
inspeccionar el sistema de archivos al que el backend tiene acceso. En esa
arquitectura, eso se traduce en tener los artefactos finales en texto plano.

## .::0x03::Mi intento de threat model::.

Con esa arquitectura en mente, decidí formalizar el threat model (no formal
formal, pero lo explicité al menos).

El atacante que asumo es alguien que logra ejecución de código en el backend
Flask. Puede leer el código del backend, las variables de entorno, las
credenciales de base de datos y de Redis. Puede interactuar con Postgres, leer
metadata de proyectos, consultar tablas de artefactos finales y obtener las
rutas de almacenamiento. Además, puede encolar jobs usando la misma interfaz
que el backend utiliza. No asumo que tenga root sobre el host ni que pueda
modificar el código en ejecución, pero sí que puede leer todo lo que el backend
puede leer.

No intento proteger el caso en que el cliente esté comprometido. Si el
navegador del usuario está infectado o el frontend es manipulado, el modelo que
estoy armando se cae por definición. Tampoco intento resolver la recuperación
de contraseña sin pérdida de datos, porque eso es incompatible con el objetivo
principal. Además, asumo que los workers están razonablemente hardenizados ya
que su código es simple y no pueden ejecutar código arbitrario fuera de una
lista blanca de tareas permitidas, aunque soy consciente de que eso es más una
suposición que una garantía.

El objetivo que me impuse fue concreto: un compromiso del backend no debe
permitir el acceso en texto plano a los artefactos finales de los usuarios. Si
el atacante logra exfiltrar información, quiero que lo que obtenga sea texto
cifrado, no guiones legibles.


## .::0x04::Zero Knowledge::.

En este punto entendí que cifrar archivos en el servidor era la solución, pero
tampoco era tan simple. La única forma de cumplir el objetivo era
adoptar un modelo de conocimiento cero. Es el único modelo que protegía
eficientemente el threat model que diseñé.

Para entender cómo hacerlo correctamente, leí los whitepapers de Bitwarden y
Mega para entender su principio estructural: el servidor no debe tener material
suficiente para descifrar los datos del usuario. Eso implica que la derivación
de llaves debe ocurrir en el cliente y que las llaves privadas nunca deben
existir en texto plano en el backend.

### 0x04.1 Identidad criptográfica del usuario

En el primer login real, cuando el usuario cambia su contraseña temporal, el
cliente genera un par de llaves **RSA-OAEP** de 2048 bits con **SHA-256** usando
WebCrypto. Elegí **RSA-OAEP** por su soporte amplio y maduro en navegadores y
librerías backend. Podría haber usado curvas elípticas, pero **RSA-OAEP** con
parámetros estándar simplifica interoperabilidad y evita ciertas complejidades
adicionales en esta etapa del proyecto (complejidades que tuve, por cierto).

La llave pública `U_pub` se envía al backend y se almacena asociada al usuario.
La llave privada `U_priv` no se almacena en texto claro. En su lugar, se deriva
una `KEK` desde la contraseña usando **Argon2id** en el cliente, con parámetros
configurables de memoria y tiempo. Esa `KEK` se usa para cifrar `U_priv` con
**AES-GCM**, generando `U_priv_enc`.

Pseudocódigo simplificado del proceso:

```python
# En el cliente
U_pub, U_priv = generate_rsa_keypair()
KEK = argon2id(password, salt, params)
U_priv_enc = aes_gcm_encrypt(KEK, U_priv)
send_to_backend(U_pub, U_priv_enc, kdf_params)
```

En el backend solo se almacena `U_pub`, `U_priv_enc` y los parámetros del KDF. La
contraseña nunca se envía en texto plano **fuera del contexto normal de
autenticación**.

Durante el login normal, el backend devuelve  `U_priv_enc` y los parámetros
KDF. El cliente deriva nuevamente la `KEK`, descifra `U_priv` y la mantiene
cifrada en **IndexedDB** envuelta con una session key (`SK`) generada al inicio
de la sesión. Esa `SK` es **AES-GCM-256** y reduce el tiempo durante el cual la
privada existe en memoria en texto plano.

### 0x04.2 Cifrado por artefacto

Cada artefacto final se cifra con una `DEK` independiente de 32 bytes generada
aleatoriamente por el worker finalizador. El algoritmo es **AES-GCM** con nonce
de 12 bytes.

```python
# En el worker
DEK = secure_random(32)
nonce = secure_random(12)
ciphertext = aes_gcm_encrypt(DEK, file_bytes, nonce)
DEK_enc = rsa_oaep_encrypt(U_pub, DEK)
store_blob(nonce + ciphertext)
store_metadata(DEK_enc, algorithm="AES-GCM", ...)
```

La `DEK` se envuelve usando la llave pública del usuario mediante **RSA-OAEP**.
En la base de datos solo se guarda `DEK_enc` junto con metadata del artefacto.
El backend jamás posee la `DEK` en texto plano después de que el worker termina
el proceso.

### 0x04.3 Descifrado en el cliente

Cuando el usuario solicita un artefacto (Markdown, PDF, etc.), el backend
devuelve el blob cifrado, el nonce, la DEK envuelta (`DEK_env`) y metadata. El
cliente descifra `U_priv` usando la session key (`SK`), luego descifra la `DEK`
con **RSA-OAEP** y finalmente descifra el artefacto con **AES-GCM**.

```python
# En el cliente
U_priv = aes_gcm_decrypt(SK, U_priv_enc)
DEK = rsa_oaep_decrypt(U_priv, DEK_enc)
file_bytes = aes_gcm_decrypt(DEK, ciphertext, nonce)
```

El HTML de previsualización se renderiza después de descifrar en el cliente.
Los PDFs y DOCX se descifran antes de descargarse.

El trade-off de este tipo de implementación es siempre el mismo: si el usuario
pierde su contraseña, pierde acceso a sus datos. No hay mecanismo de
recuperación porque eso implicaría que el servidor tenga información suficiente
para descifrar.


## .::0x05::El problema que quedó::.

Aún con este modelo, me incomodaba algo. Si un atacante compromete el backend,
aunque no pueda descifrar los artefactos, podría exfiltrar masivamente todos
los blobs cifrados del bucket. Es cierto que sin la llave privada no puede
leerlos, pero un dump completo habilita ataques offline y, sobre todo, reduce
mi capacidad de controlar el impacto.

No era suficiente que los datos estuvieran cifrados. También quería reducir la
facilidad de extracción masiva.


## .::0x06::Object Storage y permisos por rol::.

Decidí mover los artefactos finales a un object storage compatible con S3, en
mi caso MinIO, y definir credenciales separadas por servicio con permisos
mínimos por prefijo. El backend no tiene acceso directo de lectura al prefijo
donde viven los artefactos finales, solo tiene permisos de escritura al prefijo
donde se almacenan los archivos temporales (chunks de audio, fotos, etc). Los
workers tienen acceso según su rol, y el servicio que finalmente puede leer los
artefactos finales es un componente adicional, con permisos read-only
estrictamente limitados.

Nuevamente, simplificando muchos detalles, estas son las políticas IAM:

- Backend (Flask)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::kiroku/ingest/*"
    }
  ]
}
```

- Workers
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::kiroku"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::kiroku/*"
    }
  ]
}
```

Esta separación no elimina la posibilidad de exfiltración de datos, puesto que
un atacante aún podría abusar de este último servicio para descargar blobs
cifrados, pero reduce significativamente la superficie y permite aplicar
controles más finos sobre qué componente puede leer qué.


## .::0x07::Export Service::.

Al quitarle al backend acceso directo al bucket final, apareció un problema
obvio (no tan obvio cuando lo estaba implementando al parecer): el backend ya
no podía servir los artefactos.

La solución fue implementar un **Export Service** interno que tiene permisos
read-only al prefijo final del storage. El backend, cuando necesita entregar un
artefacto, genera un token firmado con **HMAC SHA-256** que incluye el path
exacto del artefacto, el project_id, el content-type, el filename, un TTL y un
KID para rotación.

El **Export Service** por su lado valida la firma, el TTL y que el path
corresponda exactamente al solicitado, y luego streamea el blob cifrado desde
el storage. El backend no ve el texto plano en ningún momento.

El token **HMAC** no impide que un atacante con RCE en el backend lo abuse,
porque también puede firmar tokens. Su objetivo es reducir exposición adicional
del **Export Service** como endpoint independiente y permitir controles de
expiración y rotación. Es una capa más solamente.

La política IAM del **Export Service** es algo así:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::kiroku/final/v1/*"
    }
  ]
}
```

## .::0x08::Ventanas inevitables::.

Hay ventanas de exposición que asumo conscientemente.
- Durante el procesamiento, los workers manejan datos en texto plano dentro de su sistema de archivos aislado.
- El cliente descifra artefactos en su entorno local.
- Metadata como fechas de creación o cantidad de fotos permanece en texto plano en la base de datos.
- Si el frontend o el navegador están comprometidos, el modelo zero knowledge deja de proteger.

## .::0x09::Estado actual::.

Este diseño no es perfecto ni pretende serlo. No es una implementación
enterprise auditada por terceros, ni una solución definitiva a todos los
problemas de seguridad posibles. Es mi intento consciente de llevar Kiroku a un
modelo donde la confianza no dependa de mi buena voluntad como administrador.

Todavía hay mejoras pendientes en el **Export Service**, validaciones más
estrictas que implementar y muchos puntos que endurecer. Pero hoy, si alguien
compromete el backend, no obtiene guiones en texto plano, obtiene
infraestructura, metadata y blobs cifrados que no puede descifrar sin la llave
privada del usuario.

Para mí, eso cambia completamente el punto de partida Y el proyecto seguirá
evolucionando desde acá. Lo más probable es que vaya actualizando este post a
medida que la infraestructura cambie y mejore, así que antentos :)
