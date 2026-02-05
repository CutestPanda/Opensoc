#include <stdint.h>

#include "../include/utils.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

extern void trap_entry();

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void pre_init(){
	// 设置中断入口函数
	// 链接模式 = DIRECT
    write_csr(mtvec, &trap_entry);
	
    // 使能CPU全局中断
    // MIE = 1, MPIE = 1, MPP = 11
    write_csr(mstatus, 0x00001888);

    write_csr(mcycle, 0x00000000);
    write_csr(mcycleh, 0x00000000);
    write_csr(minstret, 0x00000000);
    write_csr(minstreth, 0x00000000);
}
