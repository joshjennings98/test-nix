final: pre: 

{
    dmenu = pre.dmenu.override {
      patches = [
        ../../dmenu/fuzzymatch.diff
        ../../dmenu/highlight.diff
      ];
    };
  }
