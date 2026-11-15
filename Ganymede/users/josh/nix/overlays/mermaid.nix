final: prev: {
  mermaid-cli = prev.mermaid-cli.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/mermaid-cli-containment.patch ];
    passthru = (old.passthru or { }) // {
      tests = (old.passthru.tests or { }) // {
        containment = final.runCommand "mermaid-cli-containment-test" {
          nativeBuildInputs = [ final.nodejs ];
          MERMAID_INTERCEPTOR = "${final.mermaid-cli}/lib/node_modules/@mermaid-js/mermaid-cli/src/puppeteerIntercept.js";
        } ''
          node ${./tests/mermaid-cli.mjs}
          touch "$out"
        '';
      };
    };
  });

  emacsPackagesFor = emacs:
    (prev.emacsPackagesFor emacs).overrideScope (efinal: eprev: {
      ob-mermaid = eprev.ob-mermaid.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/ob-mermaid-arguments.patch ];
        passthru = (old.passthru or { }) // {
          tests = (old.passthru.tests or { }) // {
            arguments = final.runCommand "ob-mermaid-arguments-test" {
              nativeBuildInputs = [ emacs ];
            } ''
              export OB_MERMAID_FILE=$(find ${efinal.ob-mermaid} -name ob-mermaid.el -print -quit)
              emacs -Q --batch -l ${./tests/ob-mermaid.el}
              touch "$out"
            '';
          };
        };
      });
    });
}
