{
  programs.git = {
    enable = true;
    extraConfig = {
      init.defaultBranch = "main";
      merge.conflictStyle = "diff3";
    };
    signing = {
      key = null;
      signByDefault = true;
    };
  };
}
