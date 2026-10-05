# nucleo-template

Nix-Flake-Template für Bare-Metal-Firmware auf STM32 Nucleo-F401RE / F411RE:
arm-none-eabi-Toolchain, CMSIS von ST, Blinky als Startpunkt,
Host-Unit-Tests (Unity, ASan/UBSan), Flashen per OpenOCD, Simulation in Renode.

## Neues Projekt

```sh
mkdir mein-projekt && cd mein-projekt
nix flake init -t ~/git/private/nucleo-template      # lokal
# nix flake init -t github:<user>/nucleo-template     # nach dem Push
git init && git add -A
direnv allow                                          # oder: nix develop
make test && make && make sim-ui
```

Inhalt und Bedienung des erzeugten Projekts: [template/README.md](template/README.md).

## Template pflegen

Alles unter `template/` wird 1:1 kopiert. Toolchain-Stände aktualisieren:
`cd template && nix flake update`.
