final: pre: 

{
  dmenu = pre.dmenu.overrideAttrs (oldAttrs: { # https://news.ycombinator.com/item?id=30069486
    patches = [
      ../../dmenu/fuzzymatch.diff
      ../../dmenu/highlight.diff
    ];
    # as of 16/01/2025 the package needs the '-lm' flags set but hasn't done it upstream
    NIX_LDFLAGS = "${oldAttrs.NIX_LDFLAGS or ""} -lm";
  });
}
