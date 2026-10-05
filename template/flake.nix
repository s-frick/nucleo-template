{
  description = "STM32 Nucleo-F401RE/F411RE firmware project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ST's CMSIS device headers (stm32f401xe.h, startup_*.s, system_stm32f4xx.c)
    cmsis-device-f4 = {
      url = "github:STMicroelectronics/cmsis-device-f4";
      flake = false;
    };
    # CMSIS-Core (core_cm4.h, cmsis_gcc.h) in the version ST pairs with its device headers
    cmsis-core = {
      url = "github:STMicroelectronics/cmsis_core";
      flake = false;
    };
    # Unity: C unit-test framework for host-side tests
    unity = {
      url = "github:ThrowTheSwitch/Unity";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, cmsis-device-f4, cmsis-core, unity }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            gcc-arm-embedded # arm-none-eabi-gcc/g++/gdb/objdump/size, newlib
            gnumake
            openocd          # flash + GDB server via on-board ST-Link
            stlink           # st-flash, st-info
            clang            # host compiler for unit tests (its UBSan also flags signed-shift UB in C)
            clang-tools      # clangd, clang-format, clang-tidy
            bear             # generates compile_commands.json for clangd
            usbutils         # lsusb
            picocom          # make term: serial console on the ST-Link virtual COM port
            socat            # make sim-term: terminal on the simulated UART (TCP)
          ] ++ lib.optionals stdenv.hostPlatform.isLinux [
            renode           # emulator: run the firmware without a board (make sim)
            (python3.withPackages (ps: [ ps.tkinter ])) # GUI for make sim-ui
          ];

          # nixpkgs hardening adds -fno-strict-overflow (makes signed overflow defined,
          # so UBSan stays silent) and _FORTIFY_SOURCE. For learning we want UB to show up.
          hardeningDisable = [ "all" ];

          CMSIS_DEVICE_F4 = "${cmsis-device-f4}";
          CMSIS_CORE = "${cmsis-core}/CMSIS/Core/Include";
          UNITY_SRC = "${unity}/src";

          shellHook = ''
            echo "toolchain: $(arm-none-eabi-gcc -dumpversion) · make help"
          '';
        };
      });
    };
}
