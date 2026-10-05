/*
 * We link with -nostartfiles because ST's startup file replaces the toolchain's crt0
 * (which would drag in exit(), stdio and malloc). newlib's __libc_init_array, called
 * by the startup code, still calls the legacy hooks _init/_fini, so provide empty ones.
 * Static constructors (C++ globals) run via .init_array and are unaffected.
 */
void _init(void) {}
void _fini(void) {}
