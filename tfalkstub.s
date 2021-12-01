/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * tfalkstub - stub layer to use 32-bit LK with Trusted Firmware-ARM on MSM8916
 * Based on qhystub: https://github.com/msm8916-mainline/qhypstub
 * Copyright (C) 2021 Stephan Gerhold
 *
 * Based on the "ARM Architecture Reference Manual for Armv8-A"
 * and EL2/EL1 initialization sequences adapted from Linux and U-Boot.
 */
.cpu	cortex-a53

/* The address of LK to jump to in aarch32 state */
.equ	ABOOT_ENTRY_ADDRESS,	0x8f600000

/* Hypervisor Configuration Register (EL2) */
.equ	HCR_EL2_TSC,		1 << 19	/* trap SMC instructions */

/* Saved Program Status Register (EL2) */
.equ	SPSR_EL2_A,		1 << 8	/* SError interrupt mask */
.equ	SPSR_EL2_I,		1 << 7	/* IRQ interrupt mask */
.equ	SPSR_EL2_F,		1 << 6	/* FIQ interrupt mask */
.equ	SPSR_EL2_AIF,		SPSR_EL2_A | SPSR_EL2_I | SPSR_EL2_F
.equ	SPSR_EL2_AARCH32_SVC,	0b10011		/* aarch32 supervisor mode */

/* Counter-Timer Hypervisor Control Register (EL2) */
.equ	CNTHCTL_EL2_EL1PCEN,	1 << 1	/* allow EL0/EL1 timer access */
.equ	CNTHCTL_EL2_EL1PCTEN,	1 << 0	/* allow EL0/EL1 counter access */

/* Architectural Feature Trap Register (EL2) */
.equ	CPTR_EL2_RES1,		1 << 13 | 1 << 12 | 1 << 9 | 1 << 8 | 0xff

/* System Control Register (EL1) */
.equ	SCTLR_EL1_AARCH32_RES1_MSB,	1 << 23 | 1 << 22
.equ	SCTLR_EL1_AARCH32_RES1_LSB,	1 << 11 | 1 << 4 | 1 << 3
.equ	SCTLR_EL1_CP15BEN,		1 << 5	/* enable CP15 barrier */

/* SMC Calling Convention bits */
.equ	SMCCC_OEN_SHIFT,		24
.equ	SMCCC_OEN_MASK,			0x3f
.equ	SMCCC_OEN_SIP,			2
.equ	SMCCC_OEN_FUNC_MASK,		0xffff

/* SMC Calling Convention return codes */
.equ	SMCCC_NOT_SUPPORTED,		-1
.equ	SMCCC_INVALID_PARAMETER,	-3

.global _start
_start:
	/* Set exception vector table for initial execution state switch */
	adr	x0, el2_vector_table
	msr	vbar_el2, x0

	/*
	 * aarch32 EL1 setup
	 *
	 * First, initialize SCTLR_EL1. On aarch64 this should usually happen by
	 * the bootloader or kernel in EL1 because the reset value is generally
	 * "architecturally UNKNOWN". However, for aarch32 there is a clear reset
	 * value. At least Linux depends on having CP15BEN set, otherwise it will
	 * crash very early during a CP15 barrier shortly before enabling the MMU.
	 */
	mov	x0, SCTLR_EL1_AARCH32_RES1_MSB
	movk	x0, SCTLR_EL1_AARCH32_RES1_LSB | SCTLR_EL1_CP15BEN
	msr	sctlr_el1, x0

	/* Trap SMC to hypervisor so we can emulate some strange calls */
	mov	x0, HCR_EL2_TSC
	msr	hcr_el2, x0

	mov	x0, SPSR_EL2_AIF | SPSR_EL2_AARCH32_SVC
	msr	spsr_el2, x0

	/* Allow EL1 to access timer/counter */
	mov	x0, CNTHCTL_EL2_EL1PCEN | CNTHCTL_EL2_EL1PCTEN
	msr	cnthctl_el2, x0
	msr	cntvoff_el2, xzr	/* clear virtual offset */

	/* Disable coprocessor traps */
	mov	x0, CPTR_EL2_RES1
	msr	cptr_el2, x0
	msr	hstr_el2, xzr

	/* Configure EL1 return address and return! */
	mov	x0, ABOOT_ENTRY_ADDRESS
	msr	elr_el2, x0
	mov	x0, xzr
	mov	x1, xzr
	eret

panic:
	b	panic

smc32:
	/*
	 * Increment return address to return after the trapped SMC instruction.
	 * Note: this assumes A32 (not T32/thumb) for now
	 */
	mrs	x15, elr_el2
	add	x15, x15, 4
	msr	elr_el2, x15

	lsr	w15, w0, SMCCC_OEN_SHIFT
	and	w15, w15, SMCCC_OEN_MASK
	cmp	w15, SMCCC_OEN_SIP
	beq	smc32_sip

	/* Try forwarding to TZ */
	smc	0
	eret

smc32_sip:
	/* Emulate some SMC/SCM calls that are used by LK */
	and	w15, w0, SMCCC_OEN_FUNC_MASK
	cmp	w15, 0x0109
	beq	smc_dummy_ok	/* smc_wdog_debug_disable */
	cmp	w15, 0x010f
	beq	smc_switch_aarch64
	cmp	w15, 0x0501
	beq	smc_secure_io_read
	cmp	w15, 0x0502
	beq	smc_secure_io_write
	cmp	w15, 0x0601
	beq	smc_is_call_avail
	cmp	w15, 0x0603
	beq	smc_dummy_ok	/* smc_get_feature_id */
	cmp	w15, 0x0604
	beq	smc_is_secure_boot_enabled
	cmp	w15, 0x0c02
	beq	smc_dummy_ok	/* smc_restore_secure_cfg */

eret_not_supported:
	mov	w0, SMCCC_NOT_SUPPORTED
	eret

smc_is_call_avail:
	cmp	w1, 0x1		/* MAKE_SCM_ARGS(0x1) */
	bne	smc_invalid

	/* Only IS_CALL_AVAIL(IS_CALL_AVAIL) returns true for now */
	orr	w15, w15, (SMCCC_OEN_SIP << SMCCC_OEN_SHIFT)
	cmp	w2, w15
	cset	x1, eq
	mov	x0, 0
	eret

smc_dummy_ok:
	mov	x0, 0
	mov	x1, 0
	eret

smc_is_secure_boot_enabled:
	/* Clearly secure boot is disabled if we can run this */
	mov	x0, 0
	mov	x1, ~0	/* For some reason this means secure boot disabled */
	eret

/* There is no protected memory so this is pretty pointless but okay */
smc_secure_io_read:
	cmp	w1, 0x1		/* MAKE_SCM_ARGS(0x1) */
	bne	smc_invalid
	and	x2, x2, 0xffffffff
	ldr	w1, [x2]
	mov	x0, 0
	eret

smc_secure_io_write:
	cmp	w1, 0x2		/* MAKE_SCM_ARGS(0x2) */
	bne	smc_invalid
	and	x2, x2, 0xffffffff
	str	w3, [x2]
	mov	x0, 0
	eret

smc_switch_aarch64:
	cmp	w1, 0x12	/* MAKE_SCM_ARGS(0x2, SMC_PARAM_TYPE_BUFFER_READ) */
	bne	smc_invalid
	cmp	w3, (10 * 8)	/* x0-x7 + lr, 64-bit each */
	bne	smc_invalid

	/*
	 * First, cleanup some EL2 configuration registers. This should not
	 * be necessary since the next bootloader/kernel/... should re-initialize
	 * these. However, not clearing HCR_EL2 causes reboots with U-Boot
	 * at least for some weird reason. I guess it doesn't hurt :)
	 */
	msr	hcr_el2, xzr
	msr	vbar_el2, xzr

	/* Apply all registers and jump */
	mov	w8, w2
	ldp	x0, x1, [x8], 16
	ldp	x2, x3, [x8], 16
	ldp	x4, x5, [x8], 16
	ldp	x6, x7, [x8], 16
	ldp	x8, lr, [x8]
	ret

smc_invalid:
	mov	x0, SMCCC_INVALID_PARAMETER
	eret

/* EL2 exception vectors (written to VBAR_EL2) */
.section .text.vectab
.macro excvec label
	/* Each exception vector is 32 instructions long, so 32*4 = 2^7 bytes */
	.align 7
\label:
.endm

el2_vector_table:
	excvec	el2_sp0_sync
	b	panic
	excvec	el2_sp0_irq
	b	panic
	excvec	el2_sp0_fiq
	b	panic
	excvec	el2_sp0_serror
	b	panic

	excvec	el2_sp2_sync
	b	panic
	excvec	el2_sp2_irq
	b	panic
	excvec	el2_sp2_fiq
	b	panic
	excvec	el2_sp2_serror
	b	panic

	excvec	el1_aarch64_sync
	b	panic
	excvec	el1_aarch64_irq
	b	panic
	excvec	el1_aarch64_fiq
	b	panic
	excvec	el1_aarch64_serror
	b	panic

	excvec	el1_aarch32_sync
	mrs	x15, esr_el2
	lsr	x15, x15, 26	/* shift to exception class */
	cmp	x15, 0b010011	/* trapped SMC instruction (aarch32)? */
	beq	smc32
	cmp	x15, 0b010010	/* HVC instruction (aarch32) */
	beq	eret_not_supported
	b	panic
	excvec	el1_aarch32_irq
	b	panic
	excvec	el1_aarch32_fiq
	b	panic
	excvec	el1_aarch32_serror
	b	panic

	excvec	el2_vector_table_end

.section .rodata
.align	3
.ascii	"tfalkstub"
