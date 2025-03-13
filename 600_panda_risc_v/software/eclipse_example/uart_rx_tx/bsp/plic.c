#include <stdint.h>

#include "../include/plic.h"
#include "../include/utils.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define PLIC_PRIORITY_OFFSET 0x0000
#define PLIC_PRIORITY_SHIFT_PER_SOURCE 2

#define PLIC_ENABLE_OFFSET 0x2000
#define PLIC_ENABLE_SHIFT_PER_TARGET 7

#define PLIC_THRESHOLD_OFFSET 0x200000
#define PLIC_CLAIM_OFFSET 0x200004
#define PLIC_THRESHOLD_SHIFT_PER_TARGET 12
#define PLIC_CLAIM_SHIFT_PER_TARGET 12

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化PLIC
@param  plic PLIC(结构体指针)
        base_addr PLIC基地址
@return none
*************************/
void plic_init(PLIC* plic, uint32_t base_addr){
	plic->base_addr = base_addr;
}

/*************************
@cfg
@public
@brief  配置PLIC中断阈值
@param  plic PLIC(结构体指针)
        threshold 中断阈值
@return none
*************************/
void plic_set_threshold(PLIC* plic, uint32_t threshold){
	unsigned long hart_id = read_csr(mhartid);
	volatile uint32_t* threshold_ptr = (volatile uint32_t*)(plic->base_addr + 
		PLIC_THRESHOLD_OFFSET + (hart_id << PLIC_THRESHOLD_SHIFT_PER_TARGET));
	
	*threshold_ptr = threshold;
}

/*************************
@cfg
@public
@brief  使能PLIC中断源
@param  plic PLIC(结构体指针)
        source 中断源编号
@return none
*************************/
void plic_enable_interrupt(PLIC* plic, uint32_t source){
	unsigned long hart_id = read_csr(mhartid);
	volatile uint8_t* current_ptr = (volatile uint8_t*)(plic->base_addr + 
		PLIC_ENABLE_OFFSET + (hart_id << PLIC_ENABLE_SHIFT_PER_TARGET) + (source >> 3));
	
	uint8_t current = *current_ptr;
	
	current = current | ( 1 << (source & 0x7));
	
	*current_ptr = current;
}

/*************************
@cfg
@public
@brief  除能PLIC中断源
@param  plic PLIC(结构体指针)
        source 中断源编号
@return none
*************************/
void plic_disable_interrupt(PLIC * plic, uint32_t source){
	unsigned long hart_id = read_csr(mhartid);
	volatile uint8_t * current_ptr = (volatile uint8_t*)(plic->base_addr + 
		PLIC_ENABLE_OFFSET + (hart_id << PLIC_ENABLE_SHIFT_PER_TARGET) + (source >> 3));
	
	uint8_t current = *current_ptr;
	
	current = current & ~(( 1 << (source & 0x7)));
	
	*current_ptr = current;
}

/*************************
@cfg
@public
@brief  PLIC设置中断优先级
@param  plic PLIC(结构体指针)
        source 中断源编号
		priority 中断优先级
@attention priority数值越大, 中断优先级越高, 数值0不可用
@return none
*************************/
void plic_set_priority(PLIC * plic, uint32_t source, uint32_t priority){
    volatile uint32_t* priority_ptr = (volatile uint32_t*)(plic->base_addr + 
		PLIC_PRIORITY_OFFSET + (source << PLIC_PRIORITY_SHIFT_PER_SOURCE));
	
    *priority_ptr = priority;
}

/*************************
@sts
@public
@brief  PLIC获取中断源
@param  plic PLIC(结构体指针)
@return 中断源编号
*************************/
uint32_t plic_claim_interrupt(PLIC* plic){
	unsigned long hart_id = read_csr(mhartid);
	
	volatile uint32_t* claim_addr = (volatile uint32_t*)(plic->base_addr + 
		PLIC_CLAIM_OFFSET + (hart_id << PLIC_CLAIM_SHIFT_PER_TARGET));
	
	return *claim_addr;
}

/*************************
@ctrl
@public
@brief  PLIC完成中断
@param  plic PLIC(结构体指针)
		source 中断源编号
@return none
*************************/
void plic_complete_interrupt(PLIC* plic, uint32_t source){
	unsigned long hart_id = read_csr(mhartid);
	volatile uint32_t* claim_addr = (volatile uint32_t*)(plic->base_addr +
		PLIC_CLAIM_OFFSET + (hart_id << PLIC_CLAIM_SHIFT_PER_TARGET));
	
	*claim_addr = source;
}
