/* This file was generated by getpir.c, do not modify! 
   (but if you do, please run checkpir on it to verify)
   Contains the IRQ Routing Table dumped directly from your memory , wich BIOS sets up

   Documentation at : http://www.microsoft.com/hwdev/busbios/PCIIRQ.HTM
*/

#include <arch/pirq_routing.h>

const struct irq_routing_table intel_irq_routing_table = {
	PIRQ_SIGNATURE, /* u32 signature */
	PIRQ_VERSION,   /* u16 version   */
	32+16*6,        /* there can be total 6 devices on the bus */
	0,           /* Where the interrupt router lies (bus) */
	0x38,           /* Where the interrupt router lies (dev) */
	0,         /* IRQs devoted exclusively to PCI usage */
	0x10b9,         /* Vendor */
	0x1533,         /* Device */
	0,         /* Crap (miniport) */
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }, /* u8 rfu[11] */
	0xe0,         /*  u8 checksum , this hase to set to some value that would give 0 after the sum of all bytes for this structure (including checksum) */
	{
		{0,0xa0, {{0x1, 0xdef8}, {0x4, 0xdef8}, {0x1, 0xdef8}, {0x4, 0xdef8}}, 0, 0},
		{0,0xc0, {{0, 0xc840}, {0, 0xc840}, {0, 0xc840}, {0, 0xc840}}, 0, 0},
		{0,0x48, {{0x2, 0x800}, {0, 0xc840}, {0, 0xc840}, {0, 0xc840}}, 0, 0},
		{0,0x50, {{0x3, 0x400}, {0, 0xc840}, {0, 0xc840}, {0, 0xc840}}, 0, 0},
		{0,0x58, {{0x4, 0x80}, {0, 0xc840}, {0, 0xc840}, {0, 0xc840}}, 0, 0},
		{0,0x78, {{0, 0xc840}, {0, 0xc840}, {0, 0xc840}, {0, 0xc840}}, 0, 0},
	}
};
