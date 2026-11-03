#!/usr/bin/env bash
# O ralph vive no repo proprio (codigo, testes e docs): este arquivo so delega,
# para nao existirem duas copias divergindo. Local do checkout: RALPH_HOME
# (default ~/Projects/ralph).
R="${RALPH_HOME:-$HOME/Projects/ralph}/ralph-watch.sh"
if [ ! -x "$R" ]; then
  echo "ralph-watch.sh nao encontrado em $R — clone o ralph ou defina RALPH_HOME." >&2
  exit 1
fi
exec "$R" "$@"
