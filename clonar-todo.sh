#!/usr/bin/env bash
# Clona los otros 5 repositorios junto a comedor-infra (en la carpeta padre).
set -euo pipefail
cd "$(dirname "$0")/.."
for r in menu-inventario-service comensales-reservas-service pagos-tickets-service ia-ml-service comedor-clientes; do
  if [ -d "$r" ]; then echo "ya existe: $r"; else git clone https://github.com/JulioCesarTA/$r; fi
done
