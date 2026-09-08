#!/usr/bin/env bash
#
# Borra los ConfigMaps generados por kustomize que ya no usa NADIE.
#
# Por qué hace falta
# ------------------
# `configMapGenerator` le pone a cada ConfigMap un sufijo con el hash de su
# contenido, para que un cambio de configuración fuerce el reinicio de los pods.
# El efecto secundario es que cada cambio deja atrás el ConfigMap anterior, y
# Kubernetes no recoge esa basura solo.
#
# En des y pre los limpia Argo, que tiene `prune: true`. En PRODUCCIÓN el purgado
# está DESACTIVADO a propósito, y conviene que siga así: Argo compara contra el
# repositorio, no contra el historial de reversión, así que con `prune: true`
# borraría también los ConfigMaps que necesitan los ReplicaSets antiguos — y un
# `kubectl rollout undo` levantaría pods que no arrancan (CreateContainerConfigError).
# Es decir: el purgado automático sería PEOR que el problema.
#
# Este script hace lo que Argo no puede: mira el estado REAL del clúster —incluidos
# los ReplicaSets parados que guardan el historial— y solo borra lo que no
# referencia nadie.
#
# Uso
# ---
#   ./limpia-configmaps-huerfanos.sh                      # simulacro de los tres entornos
#   ./limpia-configmaps-huerfanos.sh --borrar             # borra de verdad
#   ./limpia-configmaps-huerfanos.sh --borrar nexadrop-pro
#
# Se ejecuta EN EL NODO (necesita kubectl con permisos sobre los namespaces).
set -euo pipefail

BORRAR=0
NAMESPACES=()
for arg in "$@"; do
  case "$arg" in
    --borrar) BORRAR=1 ;;
    -*) echo "opción desconocida: $arg" >&2; exit 2 ;;
    *) NAMESPACES+=("$arg") ;;
  esac
done
[ ${#NAMESPACES[@]} -eq 0 ] && NAMESPACES=(nexadrop-des nexadrop-pre nexadrop-pro)

RESPALDO="/root/respaldo-cm/$(date -u +%Y%m%dT%H%M%SZ)"

for NS in "${NAMESPACES[@]}"; do
  echo "=== $NS ==="

  # Todo lo que puede nombrar un ConfigMap. Los ReplicaSets son IMPRESCINDIBLES
  # aquí: son los que guardan el historial de reversión, y son justo los que Argo
  # no mira.
  ESTADO=$(kubectl get all,replicaset,cronjob,job,statefulset,daemonset -n "$NS" -o yaml 2>/dev/null || true)
  if [ -z "$ESTADO" ]; then
    echo "  no se pudo leer el namespace, se salta"
    continue
  fi

  GENERADOS=$(kubectl get cm -n "$NS" -o name 2>/dev/null | sed 's|configmap/||' | grep -E -- '-[bcdfghjklmnpqrstvwxz2456789]{10}$' || true)
  if [ -z "$GENERADOS" ]; then
    echo "  sin ConfigMaps generados"
    continue
  fi

  HUERFANOS=()
  for CM in $GENERADOS; do
    N=$(printf '%s' "$ESTADO" | grep -c -- "$CM" || true)
    if [ "$N" -eq 0 ]; then
      echo "  HUÉRFANO  $CM"
      HUERFANOS+=("$CM")
    else
      echo "  en uso    $CM  ($N referencias)"
    fi
  done

  if [ ${#HUERFANOS[@]} -eq 0 ]; then
    echo "  nada que limpiar"
    continue
  fi

  if [ "$BORRAR" -eq 0 ]; then
    echo "  SIMULACRO: se borrarían ${#HUERFANOS[@]}. Añade --borrar para hacerlo."
    continue
  fi

  # Copia antes de borrar: cuesta nada y convierte un error en un incidente sin
  # consecuencias.
  mkdir -p "$RESPALDO/$NS"
  for CM in "${HUERFANOS[@]}"; do
    kubectl get cm -n "$NS" "$CM" -o yaml > "$RESPALDO/$NS/$CM.yaml"
  done
  echo "  copia en $RESPALDO/$NS"
  kubectl delete cm -n "$NS" "${HUERFANOS[@]}"
done
