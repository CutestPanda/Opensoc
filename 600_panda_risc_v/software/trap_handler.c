#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断原因代码
#define INTR_CODE_M_SW (0x00000003 | 0x80000000)
#define INTR_CODE_M_TMR (0x00000007 | 0x80000000)
#define INTR_CODE_M_EXT (0x0000000B | 0x80000000)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断服务函数
extern void sw_irq_handler() __attribute__((weak));
extern void tmr_irq_handler() __attribute__((weak));
extern void ext_irq_handler() __attribute__((weak));

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void trap_handler(uint32_t mcause, uint32_t mepc){
    switch(mcause){
		case INTR_CODE_M_SW:
			sw_irq_handler();
			break;
		case INTR_CODE_M_TMR:
			tmr_irq_handler();
			break;
		case INTR_CODE_M_EXT:
			ext_irq_handler();
			break;
		default:
			break;
	}
}

void serr_handler(uint32_t mcause, uint32_t mepc){
	while(1);
}
