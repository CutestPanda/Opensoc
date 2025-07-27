/************************************************************************************************************************
APB-TIMER时钟基准示例代码
@brief  基于APB-TIMER产生0.5s的时基, 实现LED灯每隔0.5s闪烁
@attention 请根据硬件平台更换与全局中断控制器相关的API
					 假设APB-TIMER的时钟为25MHz, 16位定时器
@date   2024/09/21
@author 陈家耀
@eidt   2024/09/21 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_timer.h"
#include "apb_gpio.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_TIMER 0x40000000 // APB-TIMER外设基地址
#define BASEADDR_GPIO 0x40001000 // APB-GPIO外设基地址

#define GPIO_LED_MASK 0x00000001 // LED灯GPIO掩码

#define TIMER_ITR_ID 3 // APB-TIMER中断号

#define TIMER_PSC 2500 // 定时器预分频系数
#define TIMER_ATL 5000 // 定时器自动装载值

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbGPIO gpio; // APB-GPIO外设结构体
static ApbTimer timer; // APB-TIMER外设结构体

static uint8_t led_out = 0; // 当前的led输出电平

static uint8_t timer_period_elapsed = 0; // TIMER计数溢出标志

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@itr_handler
@private
@brief  APB-TIMER中断服务程序(示例)
@param  none
@return none
*************************/
void USER_TIMER0_Handler(void){
	uint8_t itr_sts = apb_timer_get_itr_status(&timer); // 获取中断标志向量
	
	if(itr_sts & ITR_TIMER_ELAPSED_MASK){ // 计数溢出中断
		timer_period_elapsed = 1;
	}
	
	apb_timer_clear_itr_flag(&timer); // 清除中断标志
}

void apb_timer_timebase_example(void){
	// 初始化APB-GPIO
	apb_gpio_init(&gpio, BASEADDR_GPIO);
	
	// 初始化APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(初始化配置结构体)
	
	timer_config.prescale = TIMER_PSC - 1; // 预分频系数 - 1
	timer_config.auto_load = TIMER_ATL - 1; // 自动装载值 - 1
	timer_config.chn_n = 0; // 通道数
	timer_config.cap_cmp_sel = CAP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // 捕获/比较选择
	// 比较值
	timer_config.cmp[0] = 0;
	timer_config.cmp[1] = 0;
	timer_config.cmp[2] = 0;
	timer_config.cmp[3] = 0;
	// 比较输出模式
	timer_config.oc_mode[0] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[1] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[2] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[3] = OC_MODE_GEQ_HIGH;
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
	
	// 使能APB-TIMER计数溢出中断
	NVIC_SetPriority((IRQn_Type)TIMER_ITR_ID, 0x03); // NVIC设置3号中断优先级
	NVIC_EnableIRQ((IRQn_Type)TIMER_ITR_ID); // NVIC使能3号中断
	
	apb_timer_enable_itr(&timer, ITR_TIMER_ELAPSED_MASK);
	
	// 启动定时器
	__apb_timer_set_cnt(&timer, TIMER_ATL - 1);
	__apb_timer_start(&timer);
	
	while(1){
		if(timer_period_elapsed){
			apb_gpio_write_pin(&gpio, GPIO_LED_MASK, (uint32_t)led_out);
			
			led_out = !led_out;
			
			timer_period_elapsed = 0;
		}
	}
}
