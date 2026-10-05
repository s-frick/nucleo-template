TARGET := firmware

# Every .c/.cpp/.s in src/ goes into the firmware; everything but main.c also into the host tests.
# One test executable per test/test_*.c or test/test_*.cpp. New files need no Makefile change.
SRCS      := $(wildcard src/*.c src/*.cpp src/*.s)
UNIT_SRCS := $(filter-out src/main.c,$(filter %.c,$(SRCS)))
TESTS     := $(wildcard test/test_*.c test/test_*.cpp)

include platform/mk/firmware.mk
