/**************************************************************************
���飺
�˿����ں���ң�ز���

ʹ�÷�����
(1)��remote_ctrl_options.h�����ò���
(2)����remote_ctrl_interface.h
(3)��main.c��main������whileѭ��֮ǰ���ó�ʼ������(remote_ctrl_init)
(4)�ڶ�ʱ����������ص������е����߼����ƺ���(remote_ctrl_timer_execute)
(5)�ڶ�ʱ�����벶��ص������е��ô�����(remote_ctrl_IC_execute)
(6)�ض���ң�������봦��ص�����(remote_ctrl_dispose)

˵����
(1)�뾡���ö�ʱ����Ƶ��ʱ��Ƶ��Ϊ1MHz

���ߣ�
�¼�ҫ

���ڣ�
2021/3/21
**************************************************************************/


#include "remote_ctrl_options.h"
#include "remote_ctrl_interface.h"

#define PIN_WIDTH 200 // �ߵ�ƽ�������ĳ���

__weak void remote_ctrl_dispose(uint8_t number); // ң�������봦����

typedef struct{
	int cp; // �ò����Ӧ�ļ�������ֵ
	int tim_v; // �ò����Ӧ�ļ���ֵ
}capture;

static const uint8_t binary_weights[8] = {128, 64, 32, 16, 8, 4, 2, 1}; // 8λ���������ĸ�λȨֵ

static uint8_t capture_flag = 0; // 0->���ڲ���������, 1->���ڲ����½���
static int capture_period = 0; // ��ǰ�ļ�ʱ����(�Ӳ��񵽵�һ�������ؿ�ʼ)
static int capture_timer = 0; // �����ֵ
static capture c_rising,c_falling; // ������&�½��� ��Ϣ
static uint32_t p_width = 0; // �ߵ�ƽ������� ��д��Ԫ�ص�����
static int pin_width[PIN_WIDTH]; // �ߵ�ƽ�������
static uint8_t capture_dispose = 0; // �Ƿ��Ѿ������˱������벶���¼�

/**
@brief ��ʼ������
@param  timer APB-TIMER(�ṹ��ָ��)
**/
void remote_ctrl_init(ApbTimer* timer){
	apb_timer_set_cap_config(timer, REMOTE_CTRL_CHANNEL, CAP_POS_EDGE, 10); // ���ò�������
	apb_timer_enable_itr(timer, ITR_TIMER_ELAPSED_MASK | ITR_INPUT_CAP_CHN0_MASK); // ʹ���ж�
	
	// ����timer
	__apb_timer_set_cnt(timer, REMOTE_CONTROL_COUNTER - 1);
	__apb_timer_start(timer);
}

/**
@brief ��ʱ�����������������
**/
void remote_ctrl_timer_execute(void){
	if(capture_timer > 0){
		capture_period++;
		capture_timer--;
		
		if(p_width >= 33 && (!capture_dispose)){
			// ��pin_width���鴦��
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
@brief ���ز����������
@param  timer APB-TIMER(�ṹ��ָ��)
**/
void remote_ctrl_IC_execute(ApbTimer* timer){
	// ֻҪ�����źţ���ʹ����ʱΪtimeoutֵ
	capture_timer = CAPTURE_TIMEOUT;
	uint32_t capture_value = apb_timer_get_cap(timer, REMOTE_CTRL_CHANNEL);
	
	if(capture_flag){
		// �������½���
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
		// ������������
		apb_timer_set_cap_config(timer, REMOTE_CTRL_CHANNEL, CAP_NEG_EDGE, 10);
		
		c_rising.cp = capture_period;
		c_rising.tim_v = capture_value;
	}
	
	capture_flag = !capture_flag;
}

/**
@brief ң�������봦����
@param number �������
**/
__weak void remote_ctrl_dispose(uint8_t number){}
