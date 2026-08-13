#!/bin/bash
# Xcode Run Script build-phase wrapper around bin/gen_test: generates one
# framework's CxxTest runner into $DERIVED_FILE_DIR before Compile Sources,
# so the `sources: { path: $(DERIVED_FILE_DIR)/_T<name>.cc, optional: true }`
# entry rave2yaml emits for a `<name>_test` target has something to compile.
#
# Mirrors build.ninja's `GenTest` rule -- same program, same sorted
# `tests/t_*.cc` input, same atomic `$out~ && mv $out~ $out` write -- rather
# than reinventing the CxxTest generation step:
#
#   rule GenTest
#     command = bin/gen_test $in > $out~ && mv $out~ $out
#
# Usage (from a project.yml preBuildScripts `script:`):
#   "$SRCROOT/Xcode/scripts/gen_test.sh" <framework-name>
set -euo pipefail

name="${1:?usage: gen_test.sh <framework-name>}"
: "${SRCROOT:?gen_test.sh must run as an Xcode build-phase script}"
: "${DERIVED_FILE_DIR:?gen_test.sh must run as an Xcode build-phase script}"

out="$DERIVED_FILE_DIR/_T${name}.cc"
tests=("$SRCROOT"/Frameworks/"$name"/tests/t_*.cc)

"$SRCROOT/bin/gen_test" "${tests[@]}" > "$out~"
mv "$out~" "$out"
