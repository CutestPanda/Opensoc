/************************************************************************************************************************
APB-TIMER输出比较示例代码
@brief  基于APB-TIMER实现呼吸灯
@attention 请根据硬件平台更换与延迟(delay)相关的API
					 假设APB-TIMER的时钟为25MHz, 16位定时器
					 使用通道0作为输出比较通道
@date   2024/09/21
@author 陈家耀
@eidt   2024/09/21 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_timer.h"

#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_TIMER 0x40000000 // APB-TIMER外设基地址

#define TIMER_PSC 25 // 定时器预分频系数
#define TIMER_ATL 1000 // 定时器自动装载值

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbTimer timer; // APB-TIMER外设结构体

static uint32_t now_cmp = 0; // 当前的比较值
static uint8_t to_incr_cmp = 1; // 增加/减小比较值(标志)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_timer_pwm_example(void){
	// 初始化APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(初始化配置结构体)
	
	timer_config.prescale = TIMER_PSC - 1; // 预分频系数 - 1
	timer_config.auto_load = TIMER_ATL - 1; // 自动装载值 - 1
	timer_config.chn_n = 1; // 通道数
	timer_config.cap_cmp_sel = CMP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // 捕获/比较选择
	// 比较值
	timer_config.cmp[0] = 0;
	timer_config.cmp[1] = 0;
	timer_config.cmp[2] = 0;
	timer_config.cmp[3] = 0;
	// 边沿检测类型
	timer_config.edge_detect_type[0] = CAP_POS_EDGE;
	timer_config.edge_detect_type[1] = CAP_POS_EDGE;
	timer_config.edge_detect_type[2] = CAP_POS_EDGE;
	timer_config.edge_detect_type[3] = CAP_POS_EDGE;
	// 边沿滤波阈值
	timer_config.edge_filter_th[0] = 0;
	timer_config.edge_filter_th[1] = 0;
	timer_config.edge_filter_th[2] = 0;
	timer_config.edge_filter_th[3] = 0;
	
	init_apb_timer(&timer, BASEADDR_TIMER, &timer_config);
	
	// 启动定时器
	__apb_timer_set_cnt(&timer, TIMER_ATL - 1);
	__apb_timer_start(&timer);
	
	while(1){
		apb_timer_set_cmp(&timer, APB_TIMER_CH0, now_cmp);
		
		if(to_incr_cmp){
			if(now_cmp == 1000){
				to_incr_cmp = 0;
			}else{
				now_cmp += 100;
			}
		}else{
			if(now_cmp == 0){
				to_incr_cmp = 1;
			}else{
				now_cmp -= 100;
			}
		}
		
		delay_ms(100);
	}
}
