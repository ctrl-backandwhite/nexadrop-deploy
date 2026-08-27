# Entrada: Traefik, Cloudflare y el registro

## Traefik confía en Cloudflare (y por qué importa al negocio)

Traefik lleva los 22 rangos publicados de Cloudflare como `trustedIPs`. Sin eso,
el backend vería siempre la IP del proxy en lugar de la del comprador, **se
perdería la cabecera `CF-IPCountry` y el margen se calcularía con el país
equivocado**. No es una preferencia de red: es el dato del que depende el precio.

La configuración vive en `/var/lib/rancher/k3s/server/manifests/traefik-config.yaml`,
que k3s reaplica en cada arranque, así que sobrevive a reinicios y a
actualizaciones del chart.

> **Trampa:** el fichero `https://www.cloudflare.com/ips-v4` **no termina en salto
> de línea**. Concatenarlo directamente con el de IPv6 pega `131.0.72.0/22` con
> `2400:cb00::/32` y Traefik muere al arrancar con «invalid CIDR address». Hay que
> forzar el salto y validar cada rango antes de escribirlo.

## Por qué el registro no se puede cerrar por IP

Se estudió permitir solo a GitHub Actions. **No es viable**: publica 7.280 rangos
(5.645 en IPv4) y son de Azure, así que permitirlos equivale a abrir el registro a
media nube pública. Además cambian constantemente.

Lo que protege al registro es la autenticación de Harbor, con el proyecto en
privado y una cuenta robot de permisos mínimos. Encima lleva un límite de 100
peticiones por minuto para que nadie pueda atacar esa autenticación a base de
intentos.

## Y por qué tampoco se puede ocultar la IP

`registry.nx036.com` va sin el proxy de Cloudflare porque el proxy corta a 100 MB
y **nuestra capa base pesa 201 MB** (`eclipse-temurin:25-jre`). Ni el plan
Business, que sube el límite a 200 MB, daría para esa capa; solo Enterprise.

Ocultar la IP tampoco sería una defensa real: el certificado de Let's Encrypt se
publica en los registros de transparencia, y los escáneres masivos encuentran
cualquier IP con el 443 abierto en horas. La defensa es el blindaje del servidor,
no el desconocimiento de su dirección.

Los demás dominios (`pre`, `argo`, `grafana`) sí van tras el proxy, y su
*middleware* `solo-cloudflare` rechaza cualquier petición que no venga de esos 22
rangos: aunque se sepa la IP, no se les llega por la puerta de atrás.

## El clúster no sale a internet para bajar sus propias imágenes

`/etc/rancher/k3s/registries.yaml` apunta `registry.nx036.com` a
`http://172.17.0.1:8080`. Sin eso, cada pod saldría a Cloudflare y volvería para
bajar una imagen que está en la misma máquina: más lento, y la aplicación
dependería de que internet funcione para poder arrancar.

Medido: 1,28 s para bajar una imagen del registro propio.
