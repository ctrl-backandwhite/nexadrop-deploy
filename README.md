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
| `base/` | Manifiestos comunes: backend, frontend, crawler |
| `overlays/pre/` | Preproducción. El tag candidato lo escribe el CI |
| `overlays/pro/` | Producción. Requiere revisión de CODEOWNERS |
| `platform/` | Traefik, cert-manager, External Secrets, monitorización |
| `datos/` | Servicios con estado (Postgres, Redis, Redpanda, OpenSearch, MinIO, Harbor), en Compose sobre el host |

## Secretos

**Aquí no hay ni un valor de secreto.** Los manifiestos declaran `ExternalSecret`, que referencian
la bóveda; el operador los materializa en el clúster. Lo que sale del repositorio es el valor, no
la declaración.

La única credencial que se crea a mano en el clúster es la del propio operador contra la bóveda:
el huevo y la gallina inevitable, reducido a una sola pieza.

### `CDN_SHARED_SECRET` — pendiente de configurar en pre y producción

El backend solo se cree la geolocalización por IP —`CF-IPCountry` y equivalentes— cuando la petición
demuestra haber pasado por el CDN, presentando este secreto en la cabecera `X-Nexadrop-Edge`.

**Por qué hace falta**: el origen responde 200 si se le llama directamente con `--resolve` y el `Host`
correcto, saltándose Cloudflare por completo. Sin el secreto, esa cabecera es una más y cualquiera se
declara del país que le convenga; el país decide el margen y los costes de aduana, y en el alta social
decide el país que queda GRABADO en la ficha.

Dos pasos, y hacen falta LOS DOS:

1. **En Cloudflare**, una regla de transformación de cabeceras de petición que añada
   `X-Nexadrop-Edge: <valor>` a todo el tráfico del dominio.
2. **En la bóveda**, `CDN_SHARED_SECRET=<el mismo valor>`, que llega al backend por `backend-secretos`.

**Vacío = se confía en la cabecera**, que es el comportamiento anterior. Es lo que necesita el
desarrollo local, y es también la razón de que olvidarse del paso 2 no rompa nada de forma visible:
el hueco simplemente sigue abierto. Si se pone el secreto en la bóveda pero NO la regla en Cloudflare,
el efecto es el contrario y sí se nota: nadie tendrá país por IP y los visitantes sin sesión verán los
precios sin país.

Descartado y no repetir: la lista blanca con los rangos de Cloudflare (`ipAllowList` de Traefik) no
sirve —Traefik ya ha traducido a la IP real del comprador, así que responde 403 a todo el mundo—, y los
pull certificados con mTLS devolvían 520.

### `RATELIMIT_BUILD_TOKEN` — pendiente de configurar en pre y producción

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
