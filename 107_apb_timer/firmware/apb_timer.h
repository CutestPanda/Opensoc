/************************************************************************************************************************
APB-TIMER驱动(接口头文件)
@brief  APB-TIMER驱动
@date   2024/09/21
@author 陈家耀
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 通道编号
#define APB_TIMER_CH0 0x00 // 通道0
#define APB_TIMER_CH1 0x01 // 通道1
#define APB_TIMER_CH2 0x02 // 通道2
#define APB_TIMER_CH3 0x03 // 通道3

// 捕获/比较选择
#define CAP_SEL_CHN0 0x00 // 通道0设为捕获模式
#define CMP_SEL_CHN0 0x01 // 通道0设为比较模式
#define CAP_SEL_CHN1 0x00 // 通道1设为捕获模式
#define CMP_SEL_CHN1 0x02 // 通道1设为比较模式
#define CAP_SEL_CHN2 0x00 // 通道2设为捕获模式
#define CMP_SEL_CHN2 0x04 // 通道2设为比较模式
#define CAP_SEL_CHN3 0x00 // 通道3设为捕获模式
#define CMP_SEL_CHN3 0x08 // 通道3设为比较模式

// 比较输出模式
#define OC_MODE_GEQ_HIGH 0x00 // 计数值>=比较值时输出高电平
#define OC_MODE_LT_HIGH 0x01 // 计数值<比较值时输出高电平

// 输入捕获边沿检测类型
#define CAP_POS_EDGE 0x00 // 捕获上升沿
#define CAP_NEG_EDGE 0x01 // 捕获下降沿
#define CAP_BOTH_EDGE 0x02 // 捕获双沿

// 中断类型掩码
#define ITR_TIMER_ALL_MASK 0x1F // 所有中断
#define ITR_TIMER_ELAPSED_MASK 0x01 // 计数溢出中断
#define ITR_INPUT_CAP_CHN0_MASK 0x02 // 通道0输入捕获中断
#define ITR_INPUT_CAP_CHN1_MASK 0x04 // 通道1输入捕获中断
#define ITR_INPUT_CAP_CHN2_MASK 0x08 // 通道2输入捕获中断
#define ITR_INPUT_CAP_CHN3_MASK 0x10 // 通道3输入捕获中断

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_TIMER_H
#define __APB_TIMER_H

// APB-TIMER捕获/比较通道(寄存器映射结构体)
typedef struct{
	uint32_t cap_cmp; // 捕获/比较值
	uint32_t cap_config; // 捕获配置
}ApbTimerChnHd;

// APB-TIMER(寄存器映射结构体)
typedef struct{
	uint32_t prescale; // 预分频系数 - 1
	uint32_t auto_load; // 自动装载值 - 1
	uint32_t count; // 定时器计数值
	uint32_t ctrl; // 定时器开关, 捕获/比较选择, 比较输出使能, 版本号
	uint32_t itr_en; // 中断使能
	uint32_t itr_flag; // 中断标志
	ApbTimerChnHd chn_hd[4]; // 捕获/比较通道(寄存器区)
}ApbTimerHd;

// APB-TIMER(外设结构体)
typedef struct{
	ApbTimerHd* hardware; // APB-TIMER寄存器接口(结构体指针)
	uint8_t chn_n; // 捕获/比较通道数
}ApbTimer;

// APB-TIMER(初始化配置结构体)
typedef struct{
	uint8_t cap_cmp_sel; // 捕获/比较选择
	uint8_t chn_n; // 通道数
	uint32_t prescale; // 预分频系数 - 1
	uint32_t auto_load; // 自动装载值 - 1
	uint32_t cmp[4]; // 比较值
	uint8_t oc_mode[4]; // 比较输出模式
	uint8_t edge_detect_type[4]; // 边沿检测类型
	uint8_t edge_filter_th[4]; // 边沿滤波阈值
}ApbTimerConfig;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// APB-TIMER获取硬件版本号
#define __apb_timer_get_hw_version(timer) ((uint8_t)(((timer)->hardware->ctrl) >> 16))

// APB-TIMER启动定时器
#define __apb_timer_start(timer) (timer)->hardware->ctrl = ((timer)->hardware->ctrl) | 0x00000001
// APB-TIMER暂停定时器
#define __apb_timer_stop(timer) (timer)->hardware->ctrl = ((timer)->hardware->ctrl) & 0xFFFFFFFE
// APB-TIMER重置定时器
#define __apb_timer_reset(timer) (timer)->hardware->count = (timer)->hardware->auto_load

// APB-TIMER设置计数值
#define __apb_timer_set_cnt(timer, cnt) (timer)->hardware->count = cnt

// APB-TIMER获取预分频系数
#define __apb_timer_get_prescale(timer) ((timer)->hardware->prescale)
// APB-TIMER获取自动装载值
#define __apb_timer_get_autoload(timer) ((timer)->hardware->auto_load)
// APB-TIMER获取计数值
#define __apb_timer_get_cnt(timer) ((timer)->hardware->count)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int init_apb_timer(ApbTimer* timer, uint32_t base_addr, const ApbTimerConfig* config); // 初始化APB-TIMER

void apb_timer_enable_itr(ApbTimer* timer, uint8_t itr_en); // APB-TIMER使能中断
void apb_timer_disable_itr(ApbTimer* timer); // APB-TIMER除能中断
uint8_t apb_timer_get_itr_status(ApbTimer* timer); // APB-TIMER获取中断状态
void apb_timer_clear_itr_flag(ApbTimer* timer); // APB-TIMER清除中断标志

void apb_timer_start(ApbTimer* timer); // APB-TIMER启动定时器
void apb_timer_stop(ApbTimer* timer); // APB-TIMER暂停定时器
void apb_timer_reset(ApbTimer* timer); // APB-TIMER重置定时器

void apb_timer_set_prescale(ApbTimer* timer, uint32_t prescale); // APB-TIMER设置预分频系数
void apb_timer_set_autoload(ApbTimer* timer, uint32_t auto_load); // APB-TIMER设置自动装载值
void apb_timer_set_cnt(ApbTimer* timer, uint32_t cnt); // APB-TIMER设置计数值

int apb_timer_start_oc(ApbTimer* timer, uint8_t chn_id); // APB-TIMER启动某个通道的比较输出
int apb_timer_stop_oc(ApbTimer* timer, uint8_t chn_id); // APB-TIMER停止某个通道的比较输出
int apb_timer_set_oc_mode(ApbTimer* timer, uint8_t chn_id, uint8_t oc_mode); // APB-TIMER设置某个通道的比较输出模式
int apb_timer_set_cmp(ApbTimer* timer, uint8_t chn_id, uint32_t cmp); // APB-TIMER设置某个通道的比较值
int apb_timer_set_cap_config(ApbTimer* timer, uint8_t chn_id, 
	uint8_t edge_detect_type, uint8_t edge_filter_th); // APB-TIMER设置某个通道的捕获配置

uint32_t apb_timer_get_prescale(ApbTimer* timer); // APB-TIMER获取预分频系数
uint32_t apb_timer_get_autoload(ApbTimer* timer); // APB-TIMER获取自动装载值
uint32_t apb_timer_get_cnt(ApbTimer* timer); // APB-TIMER获取计数值
uint32_t apb_timer_get_cap(ApbTimer* timer, uint8_t chn_id); // APB-TIMER获取某个通道的捕获值
