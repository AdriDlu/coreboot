/*
 * This file is part of the coreboot project.
 *
 * Copyright 2014 Google Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; version 2 of the License.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

#include <boardid.h>
#include <boot/coreboot_tables.h>
#include <console/console.h>
#include <ec/google/chromeec/ec.h>
#include <ec/google/chromeec/ec_commands.h>
#include <string.h>
#include <vendorcode/google/chromeos/chromeos.h>

#include "gpio.h"

static inline uint32_t get_pwr_btn_polarity(void)
{
	if (board_id() < BOARD_ID_PROTO_3)
		return ACTIVE_HIGH;

	return ACTIVE_LOW;
}

void fill_lb_gpios(struct lb_gpios *gpios)
{
	struct lb_gpio chromeos_gpios[] = {
		{WRITE_PROTECT_L, ACTIVE_LOW, gpio_get(WRITE_PROTECT_L),
		 "write protect"},
		{-1, ACTIVE_HIGH, get_recovery_mode_switch(), "recovery"},
		/* TODO(adurbin): add lid switch */
		{POWER_BUTTON, get_pwr_btn_polarity(), -1, "power"},
		{-1, ACTIVE_HIGH, get_developer_mode_switch(), "developer"},
		{EC_IN_RW, ACTIVE_HIGH, -1, "EC in RW"},
		{AP_SYS_RESET_L, ACTIVE_LOW, -1, "reset"},
	};

	lb_add_gpios(gpios, chromeos_gpios, ARRAY_SIZE(chromeos_gpios));
}

int get_developer_mode_switch(void)
{
	return 0;
}

int get_recovery_mode_switch(void)
{
	uint32_t ec_events;

	ec_events = google_chromeec_get_events_b();
	return !!(ec_events &
		  EC_HOST_EVENT_MASK(EC_HOST_EVENT_KEYBOARD_RECOVERY));
}

int get_write_protect_state(void)
{
	return !gpio_get(WRITE_PROTECT_L);
}
