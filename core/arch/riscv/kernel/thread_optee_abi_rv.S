/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Copyright 2023 NXP
 */

#include <asm.S>
#include <generated/asm-defines.h>
#include <keep.h>
#include <kernel/thread.h>
#include <kernel/thread_private.h>
#include <riscv.h>
#include <riscv_macros.S>
#include <tee/optee_abi.h>
#include <tee/teeabi_opteed.h>
#include <tee/teeabi_opteed_macros.h>

/*
 * Implement based on the transport method used to communicate between
 * untrusted domain and trusted domain. It could be an SBI/ECALL-based to
 * a security monitor running in M-Mode and panic or messaging-based across
 * domains where we return to a messaging callback which parses and handles
 * messages.
 */
LOCAL_FUNC thread_return_from_nsec_call , :
	/* Implement */
	j	.
END_FUNC thread_return_from_nsec_call

FUNC thread_std_abi_entry , :
	jal	__thread_std_abi_entry

	/* Save return value */
	mv	s0, a0

	/* Disable all interrupts */
	csrc	CSR_XSTATUS, CSR_XSTATUS_IE

	/* Switch to temporary stack */
	jal	thread_get_tmp_sp
	mv	sp, a0

	/*
	 * We are returning from thread_alloc_and_run()
	 * set thread state as free
	 */
	jal	thread_state_free

	/* Restore __thread_std_abi_entry() return value */
	mv	a1, s0
	li	a2, 0
	li	a3, 0
	li	a4, 0
	li	a0, TEEABI_OPTEED_RETURN_CALL_DONE

	/* Return to untrusted domain */
	jal	thread_return_from_nsec_call
END_FUNC thread_std_abi_entry

/* void thread_rpc(uint32_t rv[THREAD_RPC_NUM_ARGS]) */
FUNC thread_rpc , :
	 /* Use stack for temporary storage */
	addi	sp, sp, -REGOFF(4)

	/* Read xSTATUS */
	csrr	a1, CSR_XSTATUS

	/* Mask all maskable exceptions before switching to temporary stack */
	csrc	CSR_XSTATUS, CSR_XSTATUS_IE

	/* Save return address xSTATUS and pointer to rv */
	STR	a0, REGOFF(0)(sp)
	STR	a1, REGOFF(1)(sp)
	STR	s0, REGOFF(2)(sp)
	STR	ra, REGOFF(3)(sp)
	addi	s0, sp, REGOFF(4)

	/* Save thread state */
	jal	thread_get_ctx_regs
	store_xregs a0, THREAD_CTX_REG_SP, REG_SP
	store_xregs a0, THREAD_CTX_REG_S0, REG_S0, REG_S1
	store_xregs a0, THREAD_CTX_REG_S2, REG_S2, REG_S11

	/* Get to tmp stack */
	jal	thread_get_tmp_sp

	/* Get pointer to rv */
	LDR	s1, REGOFF(0)(sp)

	/* xSTATUS to restore */
	LDR	a1, REGOFF(1)(sp)
	/* Switch to tmp stack */
	mv	sp, a0

	/* Early load rv[] into s2-s4 */
	lw	s2, 0(s1)
	lw	s3, 4(s1)
	lw	s4, 8(s1)

	li	a0, THREAD_FLAGS_COPY_ARGS_ON_RETURN
	la	a2, .thread_rpc_return
	jal	thread_state_suspend

	mv	a4, a0	/* thread index */
	mv	a1, s2	/* rv[0] */
	mv	a2, s3	/* rv[1] */
	mv	a3, s4	/* rv[2] */
	li	a0, TEEABI_OPTEED_RETURN_CALL_DONE

	/* Return to untrusted domain */
	jal	thread_return_from_nsec_call
.thread_rpc_return:
	/*
	 * Jumps here from thread_resume() above when RPC has returned.
	 * At this point has the stack pointer been restored to the value
	 * stored in THREAD_CTX above.
	 */

	/* Get pointer to rv[] */
	LDR	a4, REGOFF(0)(sp)

	/* Store a0-a3 into rv[] */
	sw	a0, 0(a4)
	sw	a1, 4(a4)
	sw	a2, 8(a4)
	sw	a3, 12(a4)

	/* Pop saved XSTATUS from stack */
	LDR	s0, REGOFF(1)(sp)
	csrw	CSR_XSTATUS, s0

	/* Pop return address and s0 from stack */
	LDR	ra, REGOFF(3)(sp)
	LDR	s0, REGOFF(2)(sp)

	addi	sp, sp, REGOFF(4)
	ret
END_FUNC thread_rpc