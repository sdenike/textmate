#!/bin/bash
# Xcode Run Script build-phase wrapper around ragel: compiles one framework's
# Ragel state-machine sources (Frameworks/<name>/src/*.rl) into $DERIVED_FILE_DIR
# before Compile Sources, so the `sources: { path:
# $(DERIVED_FILE_DIR)/_R<name>_<basename>.cc, optional: true }` entries
# rave2yaml emits for that framework have something to compile.
#
# Mirrors build.ninja's CompileRagel rule -- same program, same output
# extension (bin/rave:635-636: `transforms '.rl' => '.cc'`) -- rather than
# reinventing Ragel invocation:
#
#   rule CompileRagel
#     command = ragel -o $out $flags $in
#
# Only one framework in this tree has a .rl source today
# (Frameworks/plist/src/ascii.rl, which declares no `add FLAGS`/`add
# RAGEL_FLAGS` of its own, so $flags is empty here too), but this loops over
# whatever *.rl files a framework actually has rather than assuming exactly
# one, so a second Ragel source anywhere else would work without changes to
# this script.
#
# Usage (from a project.yml preBuildScripts `script:`):
#   "$SRCROOT/Xcode/scripts/gen_ragel.sh" <framework-name>
set -euo pipefail

name="${1:?usage: gen_ragel.sh <framework-name>}"
: "${SRCROOT:?gen_ragel.sh must run as an Xcode build-phase script}"
: "${DERIVED_FILE_DIR:?gen_ragel.sh must run as an Xcode build-phase script}"

shopt -s nullglob
for rl in "$SRCROOT"/Frameworks/"$name"/src/*.rl; do
  base="$(basename "$rl" .rl)"
  out="$DERIVED_FILE_DIR/_R${name}_${base}.cc"
  ragel -o "$out~" "$rl"
  mv "$out~" "$out"
done
