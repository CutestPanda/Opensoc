/************************************************************************************************************************
APB-TIMER输入捕获示例代码
@brief  基于APB-TIMER实现红外遥控
        红外遥控NEC协议(请参见https://www.cnblogs.com/adylee/p/6030779.html)
@attention 请根据硬件平台更换与全局中断控制器相关的API
					 假设APB-TIMER的时钟为25MHz, 32位定时器
					 使用通道0作为输入捕获通道
@date   2024/09/21
@author 陈家耀
@eidt   2024/09/21 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_timer.h"
#include "../apb_gpio.h"

#include "remote_ctrl_interface.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_TIMER 0x40000000 // APB-TIMER外设基地址

#define TIMER_ITR_ID 3 // APB-TIMER中断号

#define TIMER_PSC 25 // 定时器预分频系数
#define TIMER_ATL 1000000 // 定时器自动装载值

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbTimer timer; // APB-TIMER外设结构体

static int remote_ctrl_key_id = -1; // 红外遥控当前检测到的按键号

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@callback
@private
@brief  红外遥控按键检测回调函数(示例)
@param  number 按键编号
@return none
*************************/
void remote_ctrl_dispose(uint8_t number){
	remote_ctrl_key_id = number;
}

/*************************
@itr_handler
@private
@brief  APB-TIMER中断服务程序(示例)
@param  none
@return none
*************************/
void apb_timer_itr_handler(void){
	uint8_t itr_sts = apb_timer_get_itr_status(&timer); // 获取中断标志向量
	
	if(itr_sts & ITR_TIMER_ELAPSED_MASK){ // 计数溢出中断
		remote_ctrl_timer_execute(); // 处理红外遥控
	}
	
	if(itr_sts & ITR_INPUT_CAP_CHN0_MASK){ // 通道0输入捕获中断
		remote_ctrl_IC_execute(&timer); // 处理红外遥控
	}
	
	apb_timer_clear_itr_flag(&timer); // 清除中断标志
}

void apb_timer_input_cap_example(void){
	// 初始化APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(初始化配置结构体)
	
	timer_config.is_encoder_mode = 0; // 是否使用编码器模式
	timer_config.prescale = TIMER_PSC - 1; // 预分频系数 - 1
	timer_config.auto_load = TIMER_ATL - 1; // 自动装载值 - 1
	timer_config.chn_n = 1; // 通道数(硬件版本号>=2时无需指定)
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
	
	NVIC_SetPriority((IRQn_Type)TIMER_ITR_ID, 0x03); // NVIC设置3号中断优先级
	NVIC_EnableIRQ((IRQn_Type)TIMER_ITR_ID); // NVIC使能3号中断
	
	remote_ctrl_init(&timer);
	
	while(1){
		if(remote_ctrl_key_id != -1){
			// 处理红外遥控按键按下...
			
			remote_ctrl_key_id = -1;
		}
	}
}
