/*
 * Blinky: LD2 (PA5, high = on, UM1724 §6.4) toggles every 500 ms, timed by SysTick.
 */
#include <stdint.h>

#include "stm32f4xx.h"

#define LED_PIN   5u
#define TICK_HZ   1000u /* 1 tick = 1 ms */
#define PERIOD_MS 500u

static volatile uint32_t ticks_ms; /* written only by SysTick_Handler */

void SysTick_Handler(void) { ticks_ms++; }

int main(void)
{
    RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
    (void)RCC->AHB1ENR; /* wait until the clock is on */

    GPIOA->MODER = (GPIOA->MODER & ~(3u << (2u * LED_PIN))) | (1u << (2u * LED_PIN)); /* output */

    /* SystemCoreClock = 16 MHz after reset (HSI, system_stm32f4xx.c) */
    SysTick_Config(SystemCoreClock / TICK_HZ);

    uint32_t last = ticks_ms;
    for (;;) {
        if (ticks_ms - last >= PERIOD_MS) { /* unsigned difference: correct across wrap */
            last += PERIOD_MS;
            GPIOA->ODR ^= 1u << LED_PIN;
        }
        __WFI(); /* sleep until the next tick */
    }
}
