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
