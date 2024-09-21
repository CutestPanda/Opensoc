/**************************************************************************
库简介：
此库用于红外遥控操作

使用方法：
(1)在remote_ctrl_options.h中配置参数
(2)包含remote_ctrl_interface.h
(3)在main.c的main函数的while循环之前调用初始化函数(remote_ctrl_init)
(4)在定时器计数溢出回调函数中调用逻辑控制函数(remote_ctrl_timer_execute)
(5)在定时器输入捕获回调函数中调用处理函数(remote_ctrl_IC_execute)
(6)重定义遥控器输入处理回调函数(remote_ctrl_dispose)

说明：
(1)请尽量让定时器分频后时钟频率为1MHz

作者：
陈家耀

日期：
2021/3/21
**************************************************************************/


#include "remote_ctrl_options.h"
#include "remote_ctrl_interface.h"

#define PIN_WIDTH 200 // 高电平宽度数组的长度

__weak void remote_ctrl_dispose(uint8_t number); // 遥控器输入处理函数

typedef struct{
	int cp; // 该捕获对应的计数周期值
	int tim_v; // 该捕获对应的计数值
}capture;

static const uint8_t binary_weights[8] = {128, 64, 32, 16, 8, 4, 2, 1}; // 8位二进制数的各位权值

static uint8_t capture_flag = 0; // 0->正在捕获上升沿, 1->正在捕获下降沿
static int capture_period = 0; // 当前的计时周期(从捕获到第一个上升沿开始)
static int capture_timer = 0; // 检测阈值
static capture c_rising,c_falling; // 上升沿&下降沿 信息
static uint32_t p_width = 0; // 高电平宽度数组 待写入元素的索引
static int pin_width[PIN_WIDTH]; // 高电平宽度数组
static uint8_t capture_dispose = 0; // 是否已经处理了本次输入捕获事件

/**
@brief 初始化函数
@param  timer APB-TIMER(结构体指针)
**/
void remote_ctrl_init(ApbTimer* timer){
	apb_timer_set_cap_config(timer, REMOTE_CTRL_CHANNEL, CAP_POS_EDGE, 10); // 设置捕获配置
	apb_timer_enable_itr(timer, ITR_TIMER_ELAPSED_MASK | ITR_INPUT_CAP_CHN0_MASK); // 使能中断
	
	// 启动timer
	__apb_timer_set_cnt(timer, REMOTE_CONTROL_COUNTER - 1);
	__apb_timer_start(timer);
}

/**
@brief 定时器计数溢出操作函数
**/
void remote_ctrl_timer_execute(void){
	if(capture_timer > 0){
		capture_period++;
		capture_timer--;
		
		if(p_width >= 33 && (!capture_dispose)){
			// 对pin_width数组处理
			uint8_t input = 0;
			uint8_t vld = 1;
			
			for(int i = 17;i <= 24;i++){
				if(pin_width[i] == -1){
					vld = 0;
					
					break;
				}else if(pin_width[i])
					input |= binary_weights[i - 17];
			}
			
			#ifdef NEED_C
			uint8_t input_t = 0;
			
			for(int i = 25;i <= 32;i++){
				if(pin_width[i] == -1){
					vld = 0;
					
					break;
				}else if(pin_width[i])
					input_t |= binary_weights[i - 25];
			}
			
			if(vld && ((input + input_t) == 0xFF)){
				remote_ctrl_dispose(input);
			}
			#else
			if(vld){
				remote_ctrl_dispose(input);
			}
			#endif
			capture_dispose = 1;
		}
		
		if(capture_timer == 0){
			capture_flag = 0;
			capture_period = 0;
			p_width = 0;
			capture_dispose = 0;
		}
	}
}

/**
@brief 边沿捕获操作函数
@param  timer APB-TIMER(结构体指针)
**/
void remote_ctrl_IC_execute(ApbTimer* timer){
	// 只要捕获到信号，就使倒计时为timeout值
	capture_timer = CAPTURE_TIMEOUT;
	uint32_t capture_value = apb_timer_get_cap(timer, REMOTE_CTRL_CHANNEL);
	
	if(capture_flag){
		// 捕获到了下降沿
		apb_timer_set_cap_config(timer, REMOTE_CTRL_CHANNEL, CAP_POS_EDGE, 10);
		
		c_falling.cp = capture_period;
		c_falling.tim_v = capture_value;
		
		if(p_width <= PIN_WIDTH - 1){
			int t = (c_falling.cp - c_rising.cp) * REMOTE_CONTROL_COUNTER + (c_rising.tim_v - c_falling.tim_v);
			
			if((t > (560 - CAPTURE_ERR_TH)) && (t < (560 + CAPTURE_ERR_TH))){
				t = 0;
			}else if((t > (1690 - CAPTURE_ERR_TH)) && (t < (1690 + CAPTURE_ERR_TH))){
				t = 1;
			}else{
				t = -1;
			}
			
			pin_width[p_width++] = t;
		}
	}else{
		// 捕获到了上升沿
		apb_timer_set_cap_config(timer, REMOTE_CTRL_CHANNEL, CAP_NEG_EDGE, 10);
		
		c_rising.cp = capture_period;
		c_rising.tim_v = capture_value;
	}
	
	capture_flag = !capture_flag;
}

/**
@brief 遥控器输入处理函数
@param number 按键编号
**/
__weak void remote_ctrl_dispose(uint8_t number){}
