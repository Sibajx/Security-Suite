#!/usr/bin/env python3
"""Imprime solo los chequeos de SecurityChecks.md que le tocan a un agente (o los que pidas).

SecurityChecks.md sigue siendo la fuente única; esto evita que cada agente lea los 32 chequeos para usar 8.

  python3 chequeos.py acceso            # severidades + los chequeos de la tabla «Reparto» para ese agente
  python3 chequeos.py 6 11 X10          # chequeos sueltos
  python3 chequeos.py --lista           # id y título de todos (una línea cada uno)
"""
import os, re, sys

RUTA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "SecurityChecks.md")
INICIO = re.compile(r"^\*\*(X?\d+)\. ")


def partir(texto):
    preambulo = texto.split("## Reparto")[0].strip()
    reparto, bloques, actual = {}, {}, None
    for fila in re.findall(r"^\| `([\w-]+)` \| ([^|]+) \|", texto, re.M):
        reparto[fila[0]] = re.findall(r"\bX?\d+\b", fila[1].split("herramientas")[0].split("dueño")[0])
    for linea in texto.split("---", 1)[-1].splitlines():
        m = INICIO.match(linea)
        if m:
            actual = m.group(1)
            bloques[actual] = [linea]
        elif linea.startswith("## "):
            actual = None
        elif actual:
            bloques[actual].append(linea)
    return preambulo, reparto, {k: "\n".join(v).strip() for k, v in bloques.items()}


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help"):
        print(__doc__); sys.exit(0)
    preambulo, reparto, bloques = partir(open(RUTA).read())
    if args[0] == "--lista":
        for k, v in bloques.items():
            print(re.sub(r"\*\*", "", v.splitlines()[0])[:110])
        return
    if args[0] in reparto:
        ids = reparto[args[0]]
        titulo = f"Chequeos del agente `{args[0]}`: {', '.join(ids)}"
    else:
        ids = [a.upper() if a.lower().startswith("x") else a for a in args]
        titulo = "Chequeos: " + ", ".join(ids)
    faltan = [i for i in ids if i not in bloques]
    if faltan:
        print(f"No existen en SecurityChecks.md: {', '.join(faltan)} (agentes: {', '.join(reparto)})", file=sys.stderr)
        sys.exit(2)
    print(f"{preambulo}\n\n## {titulo}\n")
    print("\n\n".join(bloques[i] for i in ids))


if __name__ == "__main__":
    main()
