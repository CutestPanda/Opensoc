/************************************************************************************************************************
CLINT驱动(接口头文件)
@brief  CLINT驱动
@date   2025/02/01
@author 陈家耀
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __CLINT_H
#define __CLINT_H

typedef struct{
	uint32_t base_addr; // CLINT基地址
}CLINT;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void clint_init(CLINT* clint, uint32_t base_addr); // 初始化CLINT

void clint_trigger_sw_intr(CLINT* clint); // 触发软件中断
uint64_t clint_get_mtime(CLINT* clint); // 获取RTC计数值
void clint_set_mtime(CLINT* clint, uint64_t time_v); // 设置RTC计数值
uint64_t clint_get_mtimecmp(CLINT* clint); // 获取RTC比较值
void clint_set_mtimecmp(CLINT* clint, uint64_t time_cmp_v); // 设置RTC比较值
