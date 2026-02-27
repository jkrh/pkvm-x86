{ lib }:
src:
let
  makefile = builtins.readFile "${src}/Makefile";
  makefileLines = lib.strings.splitString "\n" makefile;
  getNum =
    key:
    let
      line =
        lib.findFirst
          (l: builtins.match "^${key}[[:space:]]*=[[:space:]]*([0-9]+).*$" l != null)
          null
          makefileLines;
      m = if line == null then null else builtins.match "^${key}[[:space:]]*=[[:space:]]*([0-9]+).*$" line;
    in
    if m == null then
      throw "Could not parse ${key} from ${src}/Makefile"
    else
      builtins.elemAt m 0;
in
"${getNum "VERSION"}.${getNum "PATCHLEVEL"}.${getNum "SUBLEVEL"}"
