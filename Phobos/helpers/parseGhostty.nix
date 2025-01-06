{ lib }:

let 
  parseGhosttyConfig = filepath:
    let
      allLines = lib.strings.splitString "\n" (builtins.readFile filepath);
      lines = builtins.filter (line: (lib.trim line) != "") allLines;
      parseLine = acc: line:
        let
          parts = lib.strings.splitString "=" line;
          key = lib.trim (lib.head parts);
          val = lib.trim (lib.strings.concatStrings (lib.drop 1 parts));
        in
          if builtins.hasAttr key acc then
            let
             existing = acc.${key};
            in
              if builtins.isList existing then
                acc // { ${key} = existing ++ [ val ]; }
              else
                acc // { ${key} = [existing val]; }
          else
            acc // { ${key} = val; };
    in
      builtins.foldl' parseLine {} lines;
in
  parseGhosttyConfig
