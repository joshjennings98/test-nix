final: prev: {
  brrrr = final.buildGo127Module {
    pname = "brrrr";
    version = "unstable";

    src = final.fetchgit {
      url = "https://github.com/joshjennings98/brrrr.git";
      rev = "refs/heads/main";
      hash = "sha256-9RS+sh65mmzyldxAqnl6IIQ9IooaQhJcRO1nor+N5RI=";
    };

    vendorHash = "sha256-ykWz+R37EtymRrqYXhlBBDPSVf266u3mL+a1AFSOl+s=";

    meta = {
      description = "A simple tool for commenting on GitHub PRs";
      homepage = "https://github.com/joshjennings98/brrrr";
    };
  };
}
