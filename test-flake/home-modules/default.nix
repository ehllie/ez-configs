# This is the default home manager module.
# It will be included with any user configuration that has `importDefault = true`, which is the default
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
