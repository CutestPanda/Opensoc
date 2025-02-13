#include "encoding.h"

#define HARTID 0

#define HALTED 0xFFFFFA00
#define RESUMING 0xFFFFFA04
#define GOING 0xFFFFFA08
#define RESUME_REQ 0xFFFFFA0C

#define PROGBUF_BASE 0xFFFFF900

        .option norvc
        .global entry

entry:
       jal zero, _entry
       nop

_entry:
        fence
        csrw CSR_DSCRATCH0, s0

entry_loop:
        addi s0, zero, HARTID
        sw   s0, HALTED(zero)
        lbu  s0, GOING(zero)
        andi s0, s0, (1 << HARTID)
        bnez s0, going
        lbu  s0, RESUME_REQ(zero)
        andi s0, s0, (1 << HARTID)
        bnez s0, resume
        jal  zero, entry_loop

going:
        sw zero, GOING(zero)
        csrr s0, CSR_DSCRATCH0
        jalr zero, PROGBUF_BASE(zero)
resume:
        addi s0, zero, HARTID
        sw   s0, RESUMING(zero)
        csrr s0, CSR_DSCRATCH0
        dret
