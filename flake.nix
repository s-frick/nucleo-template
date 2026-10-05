{
  description = "Project templates for bare-metal STM32 Nucleo firmware";

  outputs = { self }: {
    templates = {
      nucleo-f4 = {
        path = ./template;
        description = "STM32 Nucleo-F401RE/F411RE firmware: Makefile, drivers, host tests, Renode simulation";
        welcomeText = ''
          Firmware project created. Next: `git init && git add -A`, `direnv allow` (or `nix develop`),
          then `make test`, `make`, `make sim-ui`. See README.md.
        '';
      };
      default = self.templates.nucleo-f4;
    };
  };
}
