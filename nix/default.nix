{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
}:
let
  defaultSourcePaths = import ./sources.nix { inherit pkgs; };

  # use our own nixpkgs if it exists in our sources,
  # otherwise use iohkNix default nixpkgs.
  defaultNixpkgs = if (defaultSourcePaths ? nixpkgs)
    then defaultSourcePaths.nixpkgs
    else (import defaultSourcePaths.iohk-nix {}).nixpkgs;

  sourcesOverride = let sourcesFile = ((import defaultNixpkgs { overlays = globals; }).globals).sourcesJsonOverride; in
    if (builtins.pathExists sourcesFile)
    then import ./sources.nix { inherit pkgs sourcesFile; }
    else {};

  sourcePaths = defaultSourcePaths // sourcesOverride;

  iohkNix = import sourcePaths.iohk-nix {};

  nixpkgs = if (sourcesOverride ? nixpkgs) then sourcesOverride.nixpkgs else defaultNixpkgs;

  # overlays from ops-lib (include ops-lib sourcePaths):
  ops-lib-overlays = (import sourcePaths.ops-lib {}).overlays;
  nginx-explorer-overlay = self: super: let
    acceptLanguage = {
      src = self.fetchFromGitHub {
        name = "nginx_accept_language_module";
        owner = "giom";
        repo = "nginx_accept_language_module";
        rev = "2f69842f83dac77f7d98b41a2b31b13b87aeaba7";
        sha256 = "1hjysrl15kh5233w7apq298cc2bp4q1z5mvaqcka9pdl90m0vhbw";
      };
    };
  in {
    nginxExplorer = super.nginxStable.override (oldAttrs: {
      modules = oldAttrs.modules ++ [
        #self.nginxModules.vts
        acceptLanguage
      ];
    });
  };

  # our own overlays:
  local-overlays = [
    (import ./cardano.nix)
    (import ./benchmarking.nix)
    (import ./packages.nix)
  ];

  globals =
    if builtins.pathExists ../globals.nix
    then [(self: _: {
      globals = import ../globals-defaults.nix self // import ../globals.nix self;
    })]
    else builtins.trace "globals.nix missing, please add symlink" [(self: _: {
      globals = import ../globals-defaults.nix self;
    })];

  # merge upstream sources with our own:
  upstream-overlay = self: super: {
      inherit iohkNix;
    cardano-ops = {
      inherit overlays;
      modules = self.importWithPkgs ../modules;
      roles = self.importWithPkgs ../roles;
    };
    sourcePaths = (super.sourcePaths or {}) // sourcePaths;
  };

  overlays =
    ops-lib-overlays ++
    local-overlays ++
    globals ++
    [
      upstream-overlay
      nginx-explorer-overlay
    ];

  pkgs = import nixpkgs {
    inherit overlays system crossSystem config;
  };
in
  pkgs
