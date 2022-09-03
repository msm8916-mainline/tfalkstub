/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * tfalkstub - stub layer to use 32-bit LK with Trusted Firmware-ARM on MSM8916
 * Based on qhystub: https://github.com/msm8916-mainline/qhypstub
 * Copyright (C) 2021-2022 Stephan Gerhold
 */
.cpu	cortex-a7

/* The address of LK to jump to in aarch32 state */
.equ	ABOOT_ENTRY_ADDRESS,	0x8f600000

/* Hypervisor Configuration Register (EL2) */
.equ	HCR_TSC,		1 << 19	/* trap SMC instructions */

/* Saved Program Status Register */
.equ	SPSR_A,			1 << 8		/* SError interrupt mask */
.equ	SPSR_I,			1 << 7		/* IRQ interrupt mask */
.equ	SPSR_F,			1 << 6		/* FIQ interrupt mask */
.equ	SPSR_M,			0b11111		/* mode mask */
.equ	SPSR_SVC,		0b10011		/* supervisor mode */
.equ	SPSR_HYP,		0b11010		/* hypervisor mode */

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
	b	start
	b	panic		/* undefined instruction from hyp mode */
	b	panic		/* hypervisor call from hyp mode */
	b	panic		/* prefetch abort from hyp mode */
	b	panic		/* data abort from hyp mode */
	b	hyp_trap	/* hyp trap / entry */
	b	panic		/* IRQ */
	b	panic		/* FIQ */

start:
	/* Set exception vector table for initial execution state switch */
	adr	r0, _start
	mcr	p15, 4, r0, c12, c0, 0	/* HVBAR */

	/* Trap SMC to hypervisor so we can emulate some strange calls */
	mov	r0, #HCR_TSC
	mcr	p15, 4, r0, c1, c1, 0	/* HCR */

	mov	r0, #(SPSR_A | SPSR_I | SPSR_F | SPSR_SVC)
	msr	spsr_cxsf, r0

	/* Configure SVC return address and return! */
	ldr	r0, =#ABOOT_ENTRY_ADDRESS
	msr	elr_hyp, r0
	mov	r0, #0
	eret

panic:
	b	panic

hyp_trap:
	mrc	p15, 4, sp, c5, c2, 0	/* HSR */
	lsr	sp, sp, #26
	cmp	sp, #0x13	/* Trapped SMC? */
	beq	smc32
	cmp	sp, #0x12	/* HVC? */
	beq	eret_not_supported
	b	panic

smc32:
	/* Increment address to return after the trapped SMC instruction */
	mrs	sp, elr_hyp
	add	sp, sp, #4
	msr	elr_hyp, sp

	lsr	sp, r0, #SMCCC_OEN_SHIFT
	and	sp, sp, #SMCCC_OEN_MASK
	cmp	sp, #SMCCC_OEN_SIP
	beq	smc32_sip

	/* Try forwarding to TZ */
	smc	#0
	eret

smc32_sip:
	lsl	r0, r0, #16	/* cut of top 16 bits */
	lsr	r0, r0, #16

	/* Emulate some SMC/SCM calls that are used by LK */
	ldr	sp, =#0x0109
	cmp	r0, sp
	beq	smc_dummy_ok	/* smc_wdog_debug_disable */
	ldr	sp, =#0x0501
	cmp	r0, sp
	beq	smc_secure_io_read
	ldr	sp, =#0x0502
	cmp	r0, sp
	beq	smc_secure_io_write
	ldr	sp, =#0x0601
	cmp	r0, sp
	beq	smc_is_call_avail
	ldr	sp, =#0x0603
	cmp	r0, sp
	beq	smc_dummy_ok	/* smc_get_feature_id */
	ldr	sp, =#0x0604
	cmp	r0, sp
	beq	smc_is_secure_boot_enabled
	ldr	sp, =#0x0c02
	cmp	r0, sp
	beq	smc_dummy_ok	/* smc_restore_secure_cfg */

	ldr	sp, =#0x0142	/* Custom SMC that switches to HYP mode */
	cmp	r0, sp
	beq	smc_switch

eret_not_supported:
	mov	r0, #SMCCC_NOT_SUPPORTED
	eret

smc_is_call_avail:
	cmp	r1, #0x1		/* MAKE_SCM_ARGS(0x1) */
	bne	smc_invalid

	/* Only IS_CALL_AVAIL(IS_CALL_AVAIL) returns true for now */
	orr	sp, sp, #(SMCCC_OEN_SIP << SMCCC_OEN_SHIFT)
	cmp	r2, sp
	/*moveq	r1, #1 - already in register, see cmp above */
	movne	r1, #0
	mov	r0, #0
	eret

smc_dummy_ok:
	mov	r0, #0
	mov	r1, #0
	eret

smc_is_secure_boot_enabled:
	/* Clearly secure boot is disabled if we can run this */
	mov	r0, #0
	mov	r1, #~0	/* For some reason this means secure boot disabled */
	eret

/* There is no protected memory so this is pretty pointless but okay */
smc_secure_io_read:
	cmp	r1, #0x1		/* MAKE_SCM_ARGS(0x1) */
	bne	smc_invalid
	ldr	r1, [r2]
	mov	r0, #0
	eret

smc_secure_io_write:
	cmp	r1, #0x2		/* MAKE_SCM_ARGS(0x2) */
	bne	smc_invalid
	str	r3, [r2]
	mov	r0, #0
	eret

smc_switch:
	/* Make sure this is executed from SVC mode */
	mrs	r0, spsr
	and	sp, r0, #SPSR_M
	cmp	sp, #SPSR_SVC
	bne	smc_invalid

	/* Return in HYP mode and load banked stack pointer */
	and	r0, r0, #~SPSR_M
	orr	r0, r0, #SPSR_HYP
	msr	spsr_cxsf, r0
	mrs	sp, sp_svc

	/* Cleanup before returning */
	mov	r0, #0
	mcr	p15, 4, r0, c1, c1, 0	/* HCR */
	mcr	p15, 4, r0, c12, c0, 0	/* HVBAR */
	eret

smc_invalid:
	mov	r0, #SMCCC_INVALID_PARAMETER
	eret

.section .rodata
.align	3
.ascii	"tfalkstub32"
