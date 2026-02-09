{ system
, inputs
, ...
}:

let
  eval = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      inputs.self.nixosModules.wsl
      {
        # This forces evaluation of all types/descriptions in all modules
        documentation.nixos.includeAllModules = true;
      }
    ];
  };
in
# Return the options JSON derivation.
  # If any option type has a circular reference or missing attribute,
  # evaluation will fail here.
eval.config.system.build.manual.optionsJSON
