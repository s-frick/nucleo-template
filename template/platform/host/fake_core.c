/*
 * State of the host fake core (see core_cm4.h in this directory).
 * Linked into every host test; tests reset it in setUp().
 */
#include "core_cm4.h"

uint32_t fake_primask;
