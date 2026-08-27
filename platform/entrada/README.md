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

## El filtro por IP y la IP real no pueden convivir

Se intentó que los dominios con proxy rechazaran lo que no viniera de Cloudflare,
con un `ipAllowList` sobre sus 22 rangos. **No funciona, y el motivo importa:**
Traefik confía en esos mismos rangos para recuperar la IP real del comprador —de
la que depende el cálculo del margen—, así que para cuando el filtro mira, la IP
de origen ya es la del visitante y no la de Cloudflare. Resultado: rechaza a
todo el mundo, aplicación móvil incluida.

Se comprobó el 27-ago-2026 con la tienda entera devolviendo 403. Entre saber el
país del comprador y filtrar por IP, manda lo primero: sin país, el precio sale
mal. Lo que protege a las consolas de administración es su autenticación, no el
origen de la petición.

## El clúster no sale a internet para bajar sus propias imágenes

`/etc/rancher/k3s/registries.yaml` apunta `registry.nx036.com` a
`http://172.17.0.1:8080`. Sin eso, cada pod saldría a Cloudflare y volvería para
bajar una imagen que está en la misma máquina: más lento, y la aplicación
dependería de que internet funcione para poder arrancar.

Medido: 1,28 s para bajar una imagen del registro propio.

## PENDIENTE Y SERIO: el origen es alcanzable saltándose Cloudflare

**Comprobado el 27-ago-2026.** Con `--resolve` a la IP del VPS y la cabecera
`Host`, el origen responde 200. Cualquiera que averigüe la IP —y se averigua:
el certificado de `registry.nx036.com` la publica en los registros de
transparencia— puede:

- **Inventarse `CF-IPCountry` y comprar con el precio de otro país.** Es el
  riesgo grave: el margen se calcula con esa cabecera.
- Saltarse el límite de peticiones y el bloqueo de enlazado ajeno.
- Saltarse el cortafuegos de aplicación de Cloudflare.

**Filtrar por IP no sirve** y ya se probó: Traefik traduce la IP a la del
comprador para poder calcular el margen, así que un `ipAllowList` sobre los
rangos de Cloudflare rechaza a todo el mundo, aplicación móvil incluida.

**Lo intentado:** exigir el certificado de cliente de Cloudflare (*Authenticated
Origin Pulls*). El `TLSOption` y el secreto con la CA están creados y
`origin_tls_client_auth` activado en la zona, pero al exigirlo **Cloudflare
tampoco pasa: devuelve 520**. Se revirtió para no dejar el servicio caído.
Queda por averiguar si es propagación, si la CA descargada no es la que esta
zona presenta, o si Traefik necesita el secreto de otra forma.

**Mientras tanto, la mitigación que menos depende de todo esto:** que el backend
NO se fíe de `CF-IPCountry` sin más. Si la petición no trae certificado de
Cloudflare ni viene de sus rangos, esa cabecera hay que descartarla y resolver el
país por otra vía. Es donde está el dinero, y se arregla en el código en lugar de
en la red.
