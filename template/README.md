# Firmware-Projekt (STM32 Nucleo-F401RE / F411RE)

Bare-Metal C (C11, C++20 möglich) ohne HAL: CMSIS-Header von ST, eigene Treiber,
Unit-Tests auf dem PC, Simulation in Renode. Toolchain komplett über Nix.

## Start

```sh
direnv allow          # oder: nix develop
make test             # Host-Tests (clang, ASan/UBSan, Unity)
make                  # Firmware bauen → build/f401/firmware.elf
make sim-ui           # ohne Board: Renode + Fenster mit LD2 und B1
make flash            # mit Board: per OpenOCD/ST-Link flashen
make term             # serielle Konsole (115200 8N1)
make help             # alles weitere
```

`src/main.c` ist ein Blinky: LD2 toggelt alle 500 ms (SysTick). Ab hier eigener Code.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `src/`, `include/` | Anwendung (`include/` bei Bedarf anlegen, ist im Include-Pfad) |
| `test/test_*.c`, `test/test_*.cpp` | Host-Tests (bei Bedarf anlegen), je Datei ein Testprogramm; C++-Tests linken nur Unity + Fake-Core |
| `Makefile` | Projekt: `TARGET`, Quellen per Wildcard |
| `platform/mk/firmware.mk` | Build-, Test-, Flash-, Sim-Regeln |
| `platform/ld/` | Linker-Skripte F401RE / F411RE |
| `platform/host/` | Fake `core_cm4.h` für Host-Tests (PRIMASK, SysTick) |
| `platform/renode/` | Board-Beschreibung, Startskript, GUI (`sim_ui.py`) |
| `flake.nix` | Toolchain + CMSIS + Unity, gepinnt in `flake.lock` |

Neue Datei in `src/` → landet automatisch in Firmware und (außer `main.c`) in den Tests.
Neue `test/test_foo.c` → eigenes Testprogramm. Hardwarezugriff immer über
übergebene Register-Pointer (`GPIO_TypeDef *` usw.), dann ist der Code testbar.

Minimaler Test (`test/test_foo.c`, Unity):

```c
#include "unity.h"
#include "foo.h"

void setUp(void) {}
void tearDown(void) {}

static void test_something(void) { TEST_ASSERT_EQUAL_UINT32(42u, foo()); }

int main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_something);
    return UNITY_END();
}
```

## Varianten

- `make BOARD=f411 …` für Nucleo-F411RE
- `make OPT=-O2 …` andere Optimierung (eigenes Build-Verzeichnis)
- `make compdb` → `compile_commands.json` für clangd
- `nix flake update` → neue Toolchain/CMSIS/Unity-Stände
