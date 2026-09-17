# nexadrop-deploy

Estado deseado de la infraestructura de NX036. Argo CD reconcilia el clúster contra este
repositorio: **lo que no está aquí, no existe en producción**.

## Tres reglas

1. **Nadie aplica nada a mano contra el clúster.** El único camino es un commit aquí. Lo que se
   toque por fuera, Argo lo revierte en la siguiente reconciliación.
2. **El tag de imagen es siempre el SHA del commit que la construyó.** Nunca `latest`. Así este
   repositorio dice exactamente qué binario está corriendo, y volver atrás es revertir un commit
   de una línea.
3. **`overlays/pre/` lo escribe la integración continua; `overlays/pro/` solo se toca por pull
   request con revisión.** Promocionar a producción es copiar a `pro` un tag ya validado en `pre`,
   sin reconstruir nada: a los clientes llega bit a bit la imagen que se probó.

## Qué hay aquí

| Directorio | Contenido |
|---|---|
| `apps/` | Aplicaciones de Argo CD (app-of-apps): Argo se gestiona a sí mismo desde Git |
| `base/` | Manifiestos comunes: backend y frontend |
| `overlays/pre/` | Preproducción. El tag candidato lo escribe el CI |
| `overlays/pro/` | Producción. Requiere revisión de CODEOWNERS |
| `platform/` | Traefik, cert-manager, External Secrets, monitorización |
| `datos/` | Servicios con estado (Postgres, Redis, Redpanda, OpenSearch, MinIO, Harbor), en Compose sobre el host |

## Qué se despliega

| Imagen | Repositorio | Qué es |
|---|---|---|
| `nexadrop/backend` | `mic-dropshipping` | Spring Boot |
| `nexadrop/frontend` | `front-nx036` | Escaparate y panel, Angular con salida ESTÁTICA: las páginas públicas se escriben al construir la imagen y las sirve nginx |

El escaparate de **React (`frontend/`) ya no se despliega en ningún entorno**. Se sustituyó por
`front-nx036` en des, pre y pro; en el clúster no queda ni una referencia a él. El repositorio sigue
existiendo como referencia de la migración —la batería de paridad de `front-nx036` compara contra él—,
pero no construye imagen ni tiene sitio en estos manifiestos.

La diferencia que se nota en los manifiestos: aquel escaparate se pintaba en SERVIDOR, así que su pod
llevaba dos contenedores (un proceso Node por página y un nginx delante), un initContainer para
copiarle la configuración, memoria de V8 que dimensionar y sondas que renderizaban la portada entera.
El de ahora es un solo nginx entregando ficheros.

## Secretos

**Aquí no hay ni un valor de secreto.** Los manifiestos declaran `ExternalSecret`, que referencian
la bóveda; el operador los materializa en el clúster. Lo que sale del repositorio es el valor, no
la declaración.

La única credencial que se crea a mano en el clúster es la del propio operador contra la bóveda:
el huevo y la gallina inevitable, reducido a una sola pieza.

### `CDN_SHARED_SECRET` — CONFIGURADO en des, pre y producción (17-sep-2026)

El backend solo se cree la geolocalización por IP —`CF-IPCountry` y equivalentes— cuando la petición
demuestra haber pasado por el CDN, presentando este secreto en la cabecera `X-Nexadrop-Edge`.

**Por qué hace falta**: el origen responde 200 si se le llama directamente con `--resolve` y el `Host`
correcto, saltándose Cloudflare por completo. Sin el secreto, esa cabecera es una más y cualquiera se
declara del país que le convenga; el país decide el margen y los costes de aduana, y en el alta social
decide el país que queda GRABADO en la ficha.

Dos pasos, y hacen falta LOS DOS. **Ambos hechos el 17-sep-2026**:

1. **En Cloudflare**, dos reglas de transformación de petición en la fase `http_request_late_transform`
   de la zona `nx036.com`, una por entorno porque el valor es DISTINTO en cada uno:
   - `(http.host eq "nx036.com") or (http.host eq "api.nx036.com")` → producción
   - `(http.host eq "pre.nx036.com") or (http.host eq "api-pre.nx036.com")` → pre
   - `(http.host eq "dev.nx036.com") or (http.host eq "api-dev.nx036.com")` → des
2. **En la bóveda**, `CDN_SHARED_SECRET=<el mismo valor>`, que llega al backend por `backend-secretos`.

**Los DOS dominios de cada entorno, no solo el de la API.** La tienda pide `/api/` a su PROPIO dominio
—`apiBase: ''` en la configuración del front— y es el nginx del front quien hace de proxy al backend.
Una regla solo sobre `api.` habría dejado sin cabecera todo el tráfico del escaparate, que es la
mayoría. `api.` sigue haciendo falta aparte porque por ahí entran la aplicación móvil y los socios.

**Al añadir una regla, van TODAS.** El `PUT` sobre
`/rulesets/phases/http_request_late_transform/entrypoint` reemplaza el conjunto entero: mandar solo la
nueva borra las demás sin avisar.

Comprobado al aplicarlo: con Cloudflare delante, `/api/geo` resuelve país en los tres dominios;
llamando al origen con `--resolve` e inventando `CF-IPCountry`, devuelve `null` — y también con la
cabecera `X-Nexadrop-Edge` falsificada, que se compara en tiempo constante.

**Vacío = se confía en la cabecera**, que es el comportamiento anterior. Es lo que necesita el
desarrollo local, y es también la razón de que olvidarse del paso 2 no rompa nada de forma visible:
el hueco simplemente sigue abierto. Si se pone el secreto en la bóveda pero NO la regla en Cloudflare,
el efecto es el contrario y sí se nota: nadie tendrá país por IP y los visitantes sin sesión verán los
precios sin país.

Descartado y no repetir: la lista blanca con los rangos de Cloudflare (`ipAllowList` de Traefik) no
sirve —Traefik ya ha traducido a la IP real del comprador, así que responde 403 a todo el mundo—, y los
pull certificados con mTLS devolvían 520.

### `CAPTCHA_HMAC_KEY` — CONFIGURADO en des, pre y producción (17-sep-2026)

Firma los retos del CAPTCHA (registro, contacto, restablecimiento y boletín). Sin clave, **cada réplica
genera la suya**: el reto se firma en un pod y se verifica en otro, y esos cuatro formularios fallan de
forma intermitente para una parte de la gente sin nada en el registro que lo explique. Con autoescalado
de 2 a 6 réplicas en producción, eso es la mayoría de los intentos.

Un valor por entorno, el mismo para todas sus réplicas: `openssl rand -hex 32`.

En `des` no lo exige el validador —solo aborta con perfil `pro` o `pre`—, pero está puesto igual: sin
él ese entorno seguiría creyéndose `CF-IPCountry` a pelo, y lo que se prueba en des tiene que
comportarse como lo que se despliega.

**Aborta el arranque si falta**, igual que `CDN_SHARED_SECRET`. Y esa es la historia de por qué se
documenta aquí: al añadir esas dos comprobaciones al validador, el backend nuevo dejó de arrancar en
pre y en producción. No se vio como un fallo —la cadena de CI en verde, la etiqueta escrita y la tienda
respondiendo— porque `maxUnavailable: 0` mantiene sirviendo al pod anterior. PRE estuvo cuatro horas y
media dándose por desplegado con la versión vieja, acumulando 30 reinicios. Antes de añadir una
comprobación que falla cerrado al arrancar, hay que dejar su requisito puesto en cada entorno.

### `RATELIMIT_BUILD_TOKEN` — puesto en la bóveda, pero NO casa con el de la CI

**Comprobado el 17-sep-2026.** La clave existe con valor en `nexadrop-pre` y `nexadrop-pro` —y ambos
entornos comparten el MISMO valor—, pero es distinto del `NEXADROP_PRERENDER_TOKEN` con el que la CI
construye la imagen del front. O sea: el cupo alto NUNCA llega a aplicarse en esas construcciones.

Hoy da igual, y por eso no se ha tocado: desde que la ficha exige cuenta no se prerenderiza ninguna
(`NEXADROP_FICHAS_PRERENDERIZADAS=0` en el flujo de trabajo), así que la construcción hace pocas
peticiones y le sobra con el cupo del escaparate. El día que se vuelvan a prerenderizar fichas hay que
igualar los dos valores ANTES, o volverán a salir con una página de error dentro.

El backend limita el escaparate público a **100 peticiones por minuto y por IP** (regla
`storefront.web`): su defensa contra el volcado masivo del catálogo. Prerenderizar fichas del front es,
visto desde ahí, exactamente eso —el compilador pide las fichas tan deprisa como puede—, así que en ese
cupo solo caben unas **quince**. Medido: de 300 fichas, **278 se escribieron con una página de error
dentro** y la compilación terminó en verde.

Con el testigo, esas peticiones caen en la regla `build.prerender` (1.200/min). Lo que concede es un
**cupo más alto, no la ausencia de límite**, y con tres cerrojos: solo si está configurado, solo para
`GET`, y solo en los caminos del catálogo público. El día que se filtre, quien lo tenga podrá leer más
deprisa; no vaciar la tienda ni tocar la autenticación.

Dos pasos, y hacen falta LOS DOS con **el mismo valor**:

1. **En la bóveda**, `RATELIMIT_BUILD_TOKEN=<valor>`, que llega al backend por `backend-secretos`.
2. **En la compilación del front**, `NEXADROP_PRERENDER_TOKEN=<el mismo valor>` como argumento de
   construcción de la imagen; viaja en la cabecera `X-Prerender-Token`.

**Vacío = apagado**, que es el comportamiento anterior y lo correcto en cualquier entorno donde no se
compile el front. Olvidarse de un paso **no rompe nada visible**: el build vuelve al cupo del escaparate
y las fichas salen con página de error. Lo único que lo caza es la puerta `npm run verifica:prerender`,
que corre dentro del Dockerfile. Si no se va a configurar, hay que bajar
`NEXADROP_FICHAS_PRERENDERIZADAS` a 15.

Genera el valor con `openssl rand -hex 32`. En local ya está puesto, en las dos claves, en
`infra/docker/.env`.

## Cómo se despliega algo

```
push al repo de la aplicación
   → CI: pruebas → imagen a registry.nx036.com con tag sha-XXXXXXX
   → commit automático aquí en overlays/pre/kustomization.yaml
   → Argo sincroniza PRE
   → humo verde → PR copiando ese mismo tag a overlays/pro/
```

## Diseño y plan

- Diseño: `docs/superpowers/specs/2026-08-26-gitops-vps-k3s-argocd-design.md` (repo raíz)
- Plan de la fase 0: `docs/superpowers/plans/2026-08-26-gitops-fase0-registro-y-pipelines.md`
