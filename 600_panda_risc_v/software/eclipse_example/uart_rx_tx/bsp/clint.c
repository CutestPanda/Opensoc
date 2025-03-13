#include <stdint.h>

#include "../include/clint.h"
#include "../include/utils.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define CLINT_MSIP 0x00000000
#define CLINT_MSIP_size 0x4
#define CLINT_MTIMECMP 0x00000010
#define CLINT_MTIMECMP_size 0x8
#define CLINT_MTIME 0x00000018
#define CLINT_MTIME_size 0x8

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化CLINT
@param  clint CLINT(结构体指针)
        base_addr CLINT基地址
@return none
*************************/
void clint_init(CLINT* clint, uint32_t base_addr){
	clint->base_addr = base_addr;
}

/*************************
@set
@public
@brief  触发软件中断
@param  clint CLINT(结构体指针)
@return none
*************************/
void clint_trigger_sw_intr(CLINT* clint){
	volatile uint32_t* msip = (uint32_t*)(clint->base_addr + CLINT_MSIP);
	
	*msip = 0x00000001;
}

/*************************
@get
@public
@brief  获取RTC计数值
@param  clint CLINT(结构体指针)
@return RTC计数值
*************************/
uint64_t clint_get_mtime(CLINT* clint){
	volatile uint64_t* mtime = (uint64_t*)(clint->base_addr + CLINT_MTIME);
	
	return *mtime;
}

/*************************
@set
@public
@brief  设置RTC计数值
@param  clint CLINT(结构体指针)
		time_v RTC计数值
@return none
*************************/
void clint_set_mtime(CLINT* clint, uint64_t time_v){
	volatile uint64_t* mtime = (uint64_t*)(clint->base_addr + CLINT_MTIME);
	
	*mtime = time_v;
}

/*************************
@get
@public
@brief  获取RTC比较值
@param  clint CLINT(结构体指针)
@return RTC比较值
*************************/
uint64_t clint_get_mtimecmp(CLINT* clint){
	volatile uint64_t* mtimecmp = (uint64_t*)(clint->base_addr + CLINT_MTIMECMP);
	
	return *mtimecmp;
}

/*************************
@set
@public
@brief  设置RTC比较值
@param  clint CLINT(结构体指针)
		time_cmp_v RTC比较值
@return none
*************************/
void clint_set_mtimecmp(CLINT* clint, uint64_t time_cmp_v){
	volatile uint64_t* mtimecmp = (uint64_t*)(clint->base_addr + CLINT_MTIMECMP);
	
	*mtimecmp = time_cmp_v;
}
