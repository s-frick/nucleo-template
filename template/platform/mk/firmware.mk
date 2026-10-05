# Build rules for firmware, host tests, flashing and simulation.
#
# The project Makefile sets:
#   TARGET     name of the firmware image
#   SRCS       sources for the firmware (.c/.cpp/.s), relative to the project dir
#   UNIT_SRCS  sources compiled into the host unit tests (hardware-independent code)
#   TESTS      host test files, one executable each (test/test_*.c or test/test_*.cpp)
#              C tests link UNIT_SRCS; C++ tests check header-only code and link only Unity + fake core
#   BOARD      f401 (default) or f411; override per call: make BOARD=f411 flash
#   OPT        optimization level for the firmware, default -Og; e.g. make OPT=-O2
# and then: include platform/mk/firmware.mk

PLATFORM_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

ifndef CMSIS_DEVICE_F4
$(error CMSIS_DEVICE_F4 not set - run nix develop (or direnv allow) first)
endif

BOARD ?= f401
ifeq ($(BOARD),f401)
  DEVICE   := STM32F401xE
  STARTUP  := startup_stm32f401xe.s
  LDSCRIPT := $(PLATFORM_DIR)/ld/stm32f401xe.ld
else ifeq ($(BOARD),f411)
  DEVICE   := STM32F411xE
  STARTUP  := startup_stm32f411xe.s
  LDSCRIPT := $(PLATFORM_DIR)/ld/stm32f411xe.ld
else
  $(error unknown BOARD '$(BOARD)' - use f401 or f411)
endif

OPT ?= -Og

BUILD     := build
# Non-default OPT builds go to their own dir (build/f401-O2), so switching never mixes objects.
TGT_BUILD := $(BUILD)/$(BOARD)$(if $(filter-out -Og,$(OPT)),$(OPT))
HOST_BUILD := $(BUILD)/host

# ---------- target (ARM) ----------
PREFIX  := arm-none-eabi-
CC      := $(PREFIX)gcc
CXX     := $(PREFIX)g++
AS      := $(PREFIX)gcc -x assembler-with-cpp
OBJCOPY := $(PREFIX)objcopy
OBJDUMP := $(PREFIX)objdump
SIZE    := $(PREFIX)size
GDB     := $(PREFIX)gdb

CPU      := -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard
INCLUDES := -Iinclude -I$(CMSIS_DEVICE_F4)/Include -I$(CMSIS_CORE)
WARN     := -Wall -Wextra -Wshadow -Wconversion -Wno-sign-conversion
COMMON_FLAGS := $(CPU) -D$(DEVICE) $(INCLUDES) $(WARN) $(OPT) -g3 \
                -ffunction-sections -fdata-sections -MMD -MP
CFLAGS   := $(COMMON_FLAGS) -std=c11
CXXFLAGS := $(COMMON_FLAGS) -std=c++23 -fno-exceptions -fno-rtti \
            -fno-threadsafe-statics -fno-use-cxa-atexit
LDFLAGS  := $(CPU) -T$(LDSCRIPT) -L$(PLATFORM_DIR)/ld \
            -nostartfiles --specs=nano.specs --specs=nosys.specs \
            -Wl,--gc-sections -Wl,--no-warn-rwx-segments -Wl,-Map=$(TGT_BUILD)/$(TARGET).map -Wl,--print-memory-usage

VENDOR_SRCS := $(CMSIS_DEVICE_F4)/Source/Templates/gcc/$(STARTUP) \
               $(CMSIS_DEVICE_F4)/Source/Templates/system_stm32f4xx.c
VENDOR_OBJS := $(TGT_BUILD)/vendor/startup.o $(TGT_BUILD)/vendor/system_stm32f4xx.o \
               $(TGT_BUILD)/vendor/init_stubs.o

OBJS := $(addprefix $(TGT_BUILD)/,$(addsuffix .o,$(basename $(SRCS)))) $(VENDOR_OBJS)
LD   := $(if $(filter %.cpp,$(SRCS)),$(CXX),$(CC))
ELF  := $(TGT_BUILD)/$(TARGET).elf

.PHONY: all test flash flash-stlink gdbserver gdb term sim sim-ui sim-gdb sim-term disasm compdb clean help
.DEFAULT_GOAL := all

all: $(ELF) $(TGT_BUILD)/$(TARGET).bin

$(ELF): $(OBJS) $(LDSCRIPT)
	$(LD) $(LDFLAGS) $(OBJS) -o $@
	$(SIZE) $@

%.bin: %.elf
	$(OBJCOPY) -O binary $< $@

$(TGT_BUILD)/%.o: %.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(TGT_BUILD)/%.o: %.cpp
	@mkdir -p $(dir $@)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(TGT_BUILD)/%.o: %.s
	@mkdir -p $(dir $@)
	$(AS) $(CPU) -c $< -o $@

$(TGT_BUILD)/vendor/startup.o: $(CMSIS_DEVICE_F4)/Source/Templates/gcc/$(STARTUP)
	@mkdir -p $(dir $@)
	$(AS) $(CPU) -c $< -o $@

$(TGT_BUILD)/vendor/system_stm32f4xx.o: $(CMSIS_DEVICE_F4)/Source/Templates/system_stm32f4xx.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -w -c $< -o $@

$(TGT_BUILD)/vendor/init_stubs.o: $(PLATFORM_DIR)/src/init_stubs.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

# ---------- host unit tests ----------
HOST_CC     := clang
HOST_CFLAGS := -std=c11 -g -Og -Wall -Wextra -DUNIT_TEST -D$(DEVICE) \
               -Iinclude -I$(PLATFORM_DIR)/host -I$(CMSIS_DEVICE_F4)/Include -I$(UNITY_SRC) \
               -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
TEST_BINS   := $(addprefix $(HOST_BUILD)/,$(basename $(notdir $(TESTS))))

test: $(TEST_BINS)
	@if [ -z "$(TEST_BINS)" ]; then echo "keine Tests: test/test_*.c oder test/test_*.cpp anlegen (Unity, siehe README)"; exit 0; fi; \
	fail=0; for t in $(TEST_BINS); do echo "== $$t"; ./$$t || fail=1; done; \
	if [ $$fail = 0 ]; then printf "\n✔ alle Tests grün - jetzt: make flash (ohne Board: make sim)\n"; else printf "\n✘ Tests rot - Meldungen oben lesen\n"; exit 1; fi

$(HOST_BUILD)/%: test/%.c $(UNIT_SRCS) $(PLATFORM_DIR)/host/fake_core.c $(UNITY_SRC)/unity.c
	@mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CFLAGS) $^ -o $@

# C++ tests: Unity and the fake core stay C (compiled once to objects), the test itself is C++.
HOST_CXX      := clang++
HOST_CXXFLAGS := $(filter-out -std=c11,$(HOST_CFLAGS)) -std=c++23 -fno-exceptions -fno-rtti
HOST_C_OBJS   := $(HOST_BUILD)/obj/unity.o $(HOST_BUILD)/obj/fake_core.o

$(HOST_BUILD)/obj/unity.o: $(UNITY_SRC)/unity.c
	@mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@

$(HOST_BUILD)/obj/fake_core.o: $(PLATFORM_DIR)/host/fake_core.c
	@mkdir -p $(dir $@)
	$(HOST_CC) $(HOST_CFLAGS) -c $< -o $@

$(HOST_BUILD)/%: test/%.cpp $(HOST_C_OBJS) $(wildcard include/*.hpp)
	@mkdir -p $(dir $@)
	$(HOST_CXX) $(HOST_CXXFLAGS) $< $(HOST_C_OBJS) -o $@

# ---------- flashing & debugging (on-board ST-Link) ----------
OPENOCD := openocd -f board/st_nucleo_f4.cfg

flash: $(ELF)
	$(OPENOCD) -c "program $(ELF) verify reset exit"

flash-stlink: $(TGT_BUILD)/$(TARGET).bin
	st-flash --reset write $< 0x08000000

gdbserver:
	$(OPENOCD)

gdb: $(ELF)
	$(GDB) $(ELF) -ex "target extended-remote :3333" -ex "monitor reset halt" -ex "load"

# Serial console on the ST-Link virtual COM port (USART2). Quit picocom with Ctrl-A Ctrl-X.
TTY  ?= /dev/ttyACM0
BAUD ?= 115200
term:
	picocom -b $(BAUD) $(TTY)

# ---------- simulation (Renode, no board needed) ----------
RENODE := renode --disable-gui --console

sim: $(ELF)
	$(RENODE) -e '$$elf=@$(abspath $(ELF))' -e '$$platform=@$(PLATFORM_DIR)/renode/nucleo_f401re.repl' -e 'include @$(PLATFORM_DIR)/renode/nucleo.resc'

# Same simulation plus a window with LD2, its LEDs and B1 (platform/renode/sim_ui.py).
# Renode listens on SIM_PORT for monitor commands; make sim-gdb works as with make sim.
SIM_PORT ?= 1234
sim-ui: $(ELF)
	python3 $(PLATFORM_DIR)/renode/sim_ui.py --port $(SIM_PORT) --elf $(abspath $(ELF)) \
		--repl $(PLATFORM_DIR)/renode/nucleo_f401re.repl --resc $(PLATFORM_DIR)/renode/nucleo.resc

# Renode is not OpenOCD: no "monitor reset halt", no "load" (make sim already loaded the ELF).
sim-gdb: $(ELF)
	$(GDB) $(ELF) -ex "target remote :3333"

# Terminal on the simulated USART2 (TCP socket from nucleo.resc). Raw mode like a serial terminal, quit with Ctrl-].
SIM_UART_PORT := 3456
sim-term:
	socat -,rawer,escape=0x1d TCP:localhost:$(SIM_UART_PORT)

# ---------- tooling ----------
disasm: $(ELF)
	$(OBJDUMP) -d -S -C $(ELF) > $(TGT_BUILD)/$(TARGET).lst
	@echo "→ $(TGT_BUILD)/$(TARGET).lst"

compdb: clean
	rm -f compile_commands.json  # bear 4 does not truncate an existing file
	bear -- $(MAKE) -k all $(TEST_BINS) || true

clean:
	rm -rf $(BUILD)

help:
	@echo "make            firmware bauen ($(BOARD), $(DEVICE))"
	@echo "make test       Unit-Tests auf dem PC ausführen"
	@echo "make flash      per OpenOCD flashen (alternativ: make flash-stlink)"
	@echo "make gdbserver  OpenOCD als GDB-Server; dann in 2. Terminal: make gdb"
	@echo "make term       serielle Konsole am Board (picocom, $(TTY), Ende: Ctrl-A Ctrl-X)"
	@echo "make sim        ohne Board: Firmware in Renode starten (B1/LD2 per Befehl)"
	@echo "make sim-ui     wie make sim, plus Fenster mit LEDs und B1-Taster"
	@echo "make sim-gdb    GDB an die laufende Simulation hängen (2. Terminal)"
	@echo "make sim-term   serielle Konsole der Simulation (2. Terminal, Ende: Ctrl-])"
	@echo "make disasm     Disassembly mit Quelltext nach $(TGT_BUILD)/$(TARGET).lst"
	@echo "make compdb     compile_commands.json für clangd erzeugen"
	@echo "make BOARD=f411 ...  für Nucleo-F411RE"
	@echo "make OPT=-O2 ...     andere Optimierungsstufe (Standard -Og), baut nach build/f401-O2"

-include $(OBJS:.o=.d)
