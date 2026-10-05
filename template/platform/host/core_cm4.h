/*
 * Host stand-in for CMSIS core_cm4.h, used only by unit tests on the PC.
 *
 * The real header pulls in ARM intrinsics (arm_acle.h, inline asm) that do not
 * exist on x86. The ST device header (stm32f401xe.h) only needs the access
 * qualifiers below to define the peripheral structs, so tests use the genuine
 * GPIO_TypeDef/EXTI_TypeDef layouts with plain RAM instead of hardware.
 * Core functions and registers get fakes here as code needs them (state in fake_core.c).
 */
#ifndef HOST_CORE_CM4_H
#define HOST_CORE_CM4_H

#include <stdint.h>

#define __I   volatile const
#define __O   volatile
#define __IO  volatile
#define __IM  volatile const
#define __OM  volatile
#define __IOM volatile

#ifdef __cplusplus /* C++ tests link the C fake core, its symbols must keep their C names */
extern "C" {
#endif

/*
 * Fake PRIMASK (PM0214, core registers): bit 0 = 1 blocks all configurable interrupts.
 * Same names and semantics as the CMSIS intrinsics (cpsid/cpsie, mrs/msr primask),
 * but backed by a plain variable that tests can set and inspect.
 */
extern uint32_t fake_primask;

static inline void __disable_irq(void) { fake_primask = 1u; }
static inline void __enable_irq(void) { fake_primask = 0u; }
static inline uint32_t __get_PRIMASK(void) { return fake_primask; }
static inline void __set_PRIMASK(uint32_t primask) { fake_primask = primask & 1u; }

/*
 * SysTick register block (PM0214 §4.5), same layout and mask names as CMSIS.
 * Tests pass a SysTick_Type in RAM; there is no SysTick base address on the host.
 */
typedef struct {
    __IOM uint32_t CTRL;  /* 0x00 control and status */
    __IOM uint32_t LOAD;  /* 0x04 reload value */
    __IOM uint32_t VAL;   /* 0x08 current value */
    __IM uint32_t CALIB;  /* 0x0C calibration */
} SysTick_Type;

#define SysTick_CTRL_ENABLE_Msk    (1UL << 0)
#define SysTick_CTRL_TICKINT_Msk   (1UL << 1)
#define SysTick_CTRL_CLKSOURCE_Msk (1UL << 2)
#define SysTick_CTRL_COUNTFLAG_Msk (1UL << 16)
#define SysTick_LOAD_RELOAD_Msk    (0xFFFFFFUL)

#ifdef __cplusplus
}
#endif

#endif /* HOST_CORE_CM4_H */
