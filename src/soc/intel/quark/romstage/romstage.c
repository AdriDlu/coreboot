/*
 * This file is part of the coreboot project.
 *
 * Copyright (C) 2013 Google Inc.
 * Copyright (C) 2015-2016 Intel Corp.
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
#define __SIMPLE_DEVICE__

#include <arch/early_variables.h>
#include <console/console.h>
#include <cbfs.h>
#include "../chip.h"
#include <device/pci_def.h>
#include <fsp/car.h>
#include <fsp/util.h>
#include <lib.h>
#include <soc/intel/common/util.h>
#include <soc/iomap.h>
#include <soc/pci_devs.h>
#include <soc/pm.h>
#include <soc/romstage.h>
#include <soc/reg_access.h>
#include <string.h>

static const struct reg_script clear_smi_and_wake_events[] = {
	/* Clear any SMI or wake events */
	REG_GPE0_READ(R_QNC_GPE0BLK_GPE0S),
	REG_GPE0_READ(R_QNC_GPE0BLK_SMIS),
	REG_GPE0_OR(R_QNC_GPE0BLK_GPE0S, B_QNC_GPE0BLK_GPE0S_ALL),
	REG_GPE0_OR(R_QNC_GPE0BLK_SMIS, B_QNC_GPE0BLK_SMIS_ALL),
	REG_SCRIPT_END
};

static const struct reg_script legacy_gpio_init[] = {
	/* Temporarily enable the legacy GPIO controller */
	REG_PCI_WRITE32(R_QNC_LPC_GBA_BASE, IO_ADDRESS_VALID
		| LEGACY_GPIO_BASE_ADDRESS),
	/* Temporarily enable the GPE controller */
	REG_PCI_WRITE32(R_QNC_LPC_GPE0BLK, IO_ADDRESS_VALID
		| GPE0_BASE_ADDRESS),
	REG_PCI_OR8(PCI_COMMAND, PCI_COMMAND_IO),
	REG_SCRIPT_END
};

static const struct reg_script i2c_gpio_controller_init[] = {
	/* Temporarily enable the GPIO controller */
	REG_PCI_WRITE32(PCI_BASE_ADDRESS_0, I2C_BASE_ADDRESS),
	REG_PCI_WRITE32(PCI_BASE_ADDRESS_1, GPIO_BASE_ADDRESS),
	REG_PCI_OR8(PCI_COMMAND, PCI_COMMAND_MEMORY),
	REG_SCRIPT_END
};

static const struct reg_script hsuart_init[] = {
	/* Enable the HSUART */
	REG_PCI_WRITE32(PCI_BASE_ADDRESS_0, UART_BASE_ADDRESS),
	REG_PCI_OR8(PCI_COMMAND, PCI_COMMAND_MEMORY),
	REG_SCRIPT_END
};

asmlinkage void *car_state_c_entry(void)
{
	post_code(0x20);
	if (IS_ENABLED(CONFIG_PLATFORM_USES_FSP1_1)) {
		FSP_INFO_HEADER *fih;
		struct cache_as_ram_params car_params = {0};
		void *top_of_stack;

		/* Copy the FSP binary into ESRAM */
		memcpy((void *)CONFIG_FSP_ESRAM_LOC, (void *)CONFIG_FSP_LOC,
			0x00040000);

		/* Locate the FSP header in ESRAM */
		fih = find_fsp(CONFIG_FSP_ESRAM_LOC);

		/* Start the early verstage/romstage code */
		post_code(0x2A);
		car_params.fih = fih;
		top_of_stack = cache_as_ram_main(&car_params);

		/* Initialize MTRRs and switch stacks after RAM initialized */
		return top_of_stack;
	}

	return NULL;
}

void car_soc_pre_console_init(void)
{
	/* Initialize the controllers */
	reg_script_run_on_dev(I2CGPIO_BDF, i2c_gpio_controller_init);
	reg_script_run_on_dev(LPC_BDF, legacy_gpio_init);

	/* Enable the HSUART */
	if (IS_ENABLED(CONFIG_ENABLE_BUILTIN_HSUART0))
		reg_script_run_on_dev(HSUART0_BDF, hsuart_init);
	if (IS_ENABLED(CONFIG_ENABLE_BUILTIN_HSUART1))
		reg_script_run_on_dev(HSUART1_BDF, hsuart_init);
}

void car_soc_post_console_init(void)
{
	report_platform_info();
};

static struct chipset_power_state power_state CAR_GLOBAL;

struct chipset_power_state *fill_power_state(void)
{
	struct chipset_power_state *ps = car_get_var_ptr(&power_state);

	ps->prev_sleep_state = 0;
	printk(BIOS_DEBUG, "prev_sleep_state %d\n", ps->prev_sleep_state);
	return ps;
}

/* Initialize the UPD parameters for MemoryInit */
void soc_memory_init_params(struct romstage_params *params,
			    MEMORY_INIT_UPD *upd)
{
	const struct device *dev;
	char *pdat_file;
	size_t pdat_file_len;
	const struct soc_intel_quark_config *config;
	struct chipset_power_state *ps = car_get_var_ptr(&power_state);

	/* Locate the pdat.bin file */
	pdat_file = cbfs_boot_map_with_leak("pdat.bin", CBFS_TYPE_RAW,
		&pdat_file_len);
	if (!pdat_file) {
		printk(BIOS_DEBUG,
			"Platform configuration file (pdat.bin) not found.");
		pdat_file_len = 0;
	}

	/* Locate the configuration data from devicetree.cb */
	dev = dev_find_slot(0, LPC_DEV_FUNC);
	if (!dev) {
		printk(BIOS_ERR,
			"Error! Device (PCI:0:%02x.%01x) not found, "
			"soc_memory_init_params!\n", PCI_DEVICE_NUMBER_QNC_LPC,
			PCI_FUNCTION_NUMBER_QNC_LPC);
		return;
	}
	config = dev->chip_info;

	/* Display the ROM shadow data */
	hexdump((void *)0x000ffff0, 0x10);

	/* Clear SMI and wake events */
	if (ps->prev_sleep_state != 3) {
		printk(BIOS_SPEW, "Clearing SMI interrupts and wake events\n");
		reg_script_run_on_dev(LPC_BDF, clear_smi_and_wake_events);
	}

	/* Update the UPD data for MemoryInit */
	printk(BIOS_DEBUG, "Updating UPD values for MemoryInit: 0x%p\n", upd);
	upd->PcdSerialRegisterBase = UART_BASE_ADDRESS;
	upd->PcdSmmTsegSize = IS_ENABLED(CONFIG_HAVE_SMI_HANDLER) ?
		config->PcdSmmTsegSize : 0;
}

void soc_display_memory_init_params(const MEMORY_INIT_UPD *old,
	MEMORY_INIT_UPD *new)
{
	/* Display the parameters for MemoryInit */
	printk(BIOS_SPEW, "UPD values for MemoryInit at: 0x%p\n", new);
	fsp_display_upd_value("PcdSerialRegisterBase",
		sizeof(old->PcdSerialRegisterBase),
		old->PcdSerialRegisterBase, new->PcdSerialRegisterBase);
	fsp_display_upd_value("PcdSmmTsegSize", sizeof(old->PcdSmmTsegSize),
		old->PcdSmmTsegSize, new->PcdSmmTsegSize);
}

void soc_after_ram_init(struct romstage_params *params)
{
	uint32_t data;

	/* Determine if the shadow ROM is enabled */
	data = port_reg_read(QUARK_NC_HOST_BRIDGE_SB_PORT_ID,
				QNC_MSG_FSBIC_REG_HMISC);
	printk(BIOS_DEBUG, "0x%08x: HMISC\n", data);
	if ((data & (ESEG_RD_DRAM | FSEG_RD_DRAM))
		!= (ESEG_RD_DRAM | FSEG_RD_DRAM)) {

		/* Disable the ROM shadow 0x000e0000 - 0x000fffff */
		data |= ESEG_RD_DRAM | FSEG_RD_DRAM;
		port_reg_write(QUARK_NC_HOST_BRIDGE_SB_PORT_ID,
			QNC_MSG_FSBIC_REG_HMISC, data);
	}

	/* Display the DRAM data */
	hexdump((void *)0x000ffff0, 0x10);

	/* Initialize the PCIe bridges */
	pcie_init();
}
