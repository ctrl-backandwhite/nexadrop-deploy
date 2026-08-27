# Harbor · registry.nx036.com

Harbor 2.15.2 en Compose sobre el host, en `/opt/harbor`.

## Dos decisiones que parecen detalles y no lo son

**1. Sin proxy de Cloudflare, a propósito.** `registry.nx036.com` apunta directo a
la IP del VPS (nube gris). El proxy corta las peticiones a **100 MB** en el plan
gratuito, y una capa de imagen Docker pasa de ahí sin esfuerzo: con el proxy
puesto, `docker push` falla a mitad con un 413 que no menciona a Cloudflare por
ningún lado. Lo protegen el TLS y la autenticación de Harbor.

**2. El TLS lo termina Traefik, no Harbor.** Traefik ya ocupa los puertos 80 y 443
de la máquina, así que Harbor escucha en HTTP por el 8080 y Traefik le pone
delante el certificado de Let's Encrypt, que cert-manager renueva solo. Para que
el clúster pueda enrutar hacia un servicio que vive fuera de él hay un `Service`
sin selector con su `EndpointSlice` escrito a mano apuntando a `172.17.0.1:8080`.

Y lleva un *middleware* que quita el límite de tamaño del cuerpo: sin él, Traefik
corta las subidas y `docker push` falla con una imagen de tamaño corriente.

## Cuentas

| Quién | Para qué |
|---|---|
| `admin` | administración · contraseña en `/root/.harbor-admin` |
| `robot$nexadrop+ci` | las cadenas de entrega · secreto en `/root/.harbor-robot` |

La cuenta robot solo puede subir y bajar del proyecto `nexadrop`. Si se filtra, no
administra nada y se revoca sin tocar el resto.

## Retención

Las **10 últimas imágenes** por repositorio; se purga los domingos a las 3. Sin
esto, cada entrega deja una imagen y el disco se come los 600 GB en meses. Lo
desplegado no se pierde: su tag sigue referenciado.

El análisis con Trivy se dispara automáticamente al subir.

## Comprobado el 27-ago-2026

Acceso, subida, descarga de vuelta y artefacto visible en la interfaz, todo desde
internet y con certificado válido de Let's Encrypt.
