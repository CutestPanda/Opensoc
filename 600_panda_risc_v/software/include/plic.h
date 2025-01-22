/************************************************************************************************************************
PLIC驱动(接口头文件)
@brief  PLIC驱动
@date   2025/01/22
@author 陈家耀
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __PLIC_H
#define __PLIC_H

typedef struct{
	uint32_t base_addr; // PLIC基地址
}PLIC;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void plic_init(PLIC* plic, uint32_t base_addr); // 初始化PLIC

void plic_set_threshold(PLIC* plic, uint32_t threshold); // 配置PLIC中断阈值
void plic_enable_interrupt(PLIC* plic, uint32_t source); // 使能PLIC中断源
void plic_disable_interrupt(PLIC * plic, uint32_t source); // 除能PLIC中断源
void plic_set_priority(PLIC * plic, uint32_t source, uint32_t priority); // PLIC设置中断优先级
uint32_t plic_claim_interrupt(PLIC* plic); // PLIC获取中断源
void plic_complete_interrupt(PLIC* plic, uint32_t source); // PLIC完成中断
