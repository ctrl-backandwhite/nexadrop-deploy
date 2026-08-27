# Servicios con dato

Postgres, Redis, OpenSearch, Redpanda y MinIO, uno de cada por entorno.

## Por qué no están en Kubernetes

El clúster tiene **un solo nodo**. Meter aquí una base de datos no da alta
disponibilidad —no hay a dónde reprogramar el pod— y sí añade formas nuevas de
que se caiga: un desalojo por presión de memoria reinicia Postgres, y el
almacenamiento local de k3s no sobrevive a recrear el pod en otro sitio.

Además no hay artefacto nuestro que desplegar: son imágenes oficiales de
terceros, con versión fijada. El registry existe para lo que construimos
nosotros (backend, frontend, crawler); estas no pasan por ahí porque no las
construimos.

Cuando haya un segundo nodo, la conversación cambia: entonces sí compensa un
operador con réplicas y conmutación por error.

## Dónde escuchan

En `172.17.0.1`, la interfaz interna de Docker. **Los pods del clúster llegan;
internet no.** No es una preferencia: es lo que sustituye a la contraseña en
OpenSearch, que va con la seguridad del complemento desactivada.

Comprobado el 27-ago-2026: los cinco puertos responden desde un pod y ninguno
desde fuera del host.

| Servicio | PRE | PRO |
|---|---|---|
| Postgres | 5432 | 5442 |
| Redis | 6379 | 6389 |
| OpenSearch | 9200 | 9210 |
| Redpanda (Kafka) | 9092 | 9102 |
| MinIO | 9000 / 9001 | 9010 / 9011 |

## Dos trampas que ya costaron un arranque

- **PostgreSQL 18 cambió dónde guarda los datos.** El volumen va montado en
  `/var/lib/postgresql`, **no** en `/var/lib/postgresql/data`: la imagen coloca
  los datos en `/var/lib/postgresql/18/docker` para que `pg_upgrade --link`
  funcione entre versiones mayores. Con la ruta antigua —la correcta hasta la
  17, y la que sigue usando el Compose local— el contenedor se niega a arrancar
  en bucle.
- **Redpanda no tiene `--mode=production`.** El único modo con nombre es
  `dev-container`, que desactiva el fsync. Producción es no pasar el flag.

## Uso

```bash
cd /opt/nexadrop/datos
docker compose --env-file pre/.env up -d      # o pro/.env
docker compose --env-file pre/.env ps
```

Las contraseñas viven en `/opt/nexadrop/datos/<entorno>/.env`, con permisos 600,
**generadas en el servidor**: nunca han pasado por un repositorio ni por una
conversación. Este directorio no las contiene ni debe contenerlas.
