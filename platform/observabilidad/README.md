# Observabilidad

Loki para los registros, Prometheus para las métricas, Grafana para mirarlos.

## Qué se recoge

**Las dos capas, no solo el clúster.** Alloy corre como DaemonSet y lee dos
fuentes: la API de Kubernetes para los pods y el socket de Docker para los
contenedores de Compose. Sin lo segundo, Postgres, OpenSearch, Redpanda y MinIO
quedarían a oscuras justo donde vive el dato.

Etiquetas útiles al consultar:

| Etiqueta | Valores | De dónde sale |
|---|---|---|
| `origen` | `kubernetes`, `compose` | qué capa |
| `entorno` | `pre`, `pro` | del nombre del contenedor de Compose |
| `servicio` | `postgres`, `redis`, `opensearch`, `redpanda`, `minio` | idem |
| `namespace`, `pod`, `contenedor` | — | metadatos de Kubernetes |

Ejemplos:

```logql
{entorno="pro", servicio="postgres"} |= "ERROR"
{origen="kubernetes", namespace="nexadrop-pro"} |= "Exception"
sum by (origen) (count_over_time({origen=~"compose|kubernetes"}[1h]))
```

## Por qué Alloy y no Promtail

Promtail llegó a su **fin de vida en marzo de 2026**. No es una preferencia de
estilo: ya no recibe parches de seguridad. Alloy es su sustituto oficial.

## Decisiones que conviene no deshacer sin pensarlo

- **Las sondas de salud se descartan antes de escribirlas.** Generan una línea por
  segundo y por servicio y no dicen nada: serían el grueso del volumen y cero de
  la información.
- **Retención de 30 días, con tope de tamaño además del de tiempo.** La retención
  por tiempo sola no impide que un pod en bucle llene el disco en una tarde, y
  quedarse sin disco apaga la observabilidad justo cuando hace falta.
- **Hay límite de ingestión** (16 MB/s). Un servicio enloquecido no puede tumbar a
  Loki para todos los demás.
- **`kubeControllerManager`, `kubeScheduler`, `kubeProxy` y `kubeEtcd` están
  desactivados.** k3s no los expone como un Kubernetes tradicional, y dejarlos
  activos produce alertas de "objetivo caído" permanentes que enseñan a ignorar
  las alertas de verdad.
- **Nada está publicado en internet.** Se accede por túnel con
  `infra/vps/grafana.sh`. Un panel de observabilidad abierto enseña la forma
  entera del sistema. Cuando haya DNS, llevará Ingress con certificado y
  autenticación delante.

## Lo que falta

Las métricas de los servicios de Compose (Postgres, Redis, OpenSearch) todavía no
llegan a Prometheus: hacen falta sus *exporters*. Los registros sí llegan.
