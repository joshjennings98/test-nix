final: pre: 

{
  st = pre.st.overrideAttrs (oldAttrs: {
    patches = [
      ../../st/st-no-wheel-ctrl.diff
      ../../st/glyth-wide-support.diff
      ../../st/undercurl.diff
      ../../st/shift-enter.diff
      ../../st/gruvbox.diff
      ../../st/boxdraw.diff
      ../../st/urls.diff
      ../../st/blinking-cursor.diff
      ../../st/scrollback.diff
    ];
  });
}
