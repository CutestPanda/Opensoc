/************************************************************************************************************************
APB-TIMER���벶��ʾ������
@brief  ����APB-TIMERʵ�ֺ���ң��
        ����ң��NECЭ��(��μ�https://www.cnblogs.com/adylee/p/6030779.html)
@attention �����Ӳ��ƽ̨������ȫ���жϿ�������ص�API
					 ����APB-TIMER��ʱ��Ϊ25MHz, 32λ��ʱ��
					 ʹ��ͨ��0��Ϊ���벶��ͨ��
@date   2024/09/21
@author �¼�ҫ
@eidt   2024/09/21 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_timer.h"
#include "../apb_gpio.h"

#include "remote_ctrl_interface.h"

#include "CMSDK_CM0.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_TIMER 0x40000000 // APB-TIMER�������ַ

#define TIMER_ITR_ID 3 // APB-TIMER�жϺ�

#define TIMER_PSC 25 // ��ʱ��Ԥ��Ƶϵ��
#define TIMER_ATL 1000000 // ��ʱ���Զ�װ��ֵ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbTimer timer; // APB-TIMER����ṹ��

static int remote_ctrl_key_id = -1; // ����ң�ص�ǰ��⵽�İ�����

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@callback
@private
@brief  ����ң�ذ������ص�����(ʾ��)
@param  number �������
@return none
*************************/
void remote_ctrl_dispose(uint8_t number){
	remote_ctrl_key_id = number;
}

/*************************
@itr_handler
@private
@brief  APB-TIMER�жϷ������(ʾ��)
@param  none
@return none
*************************/
void apb_timer_itr_handler(void){
	uint8_t itr_sts = apb_timer_get_itr_status(&timer); // ��ȡ�жϱ�־����
	
	if(itr_sts & ITR_TIMER_ELAPSED_MASK){ // ��������ж�
		remote_ctrl_timer_execute(); // �������ң��
	}
	
	if(itr_sts & ITR_INPUT_CAP_CHN0_MASK){ // ͨ��0���벶���ж�
		remote_ctrl_IC_execute(&timer); // �������ң��
	}
	
	apb_timer_clear_itr_flag(&timer); // ����жϱ�־
}

void apb_timer_input_cap_example(void){
	// ��ʼ��APB-TIMER
	ApbTimerConfig timer_config; // APB-TIMER(��ʼ�����ýṹ��)
	
	timer_config.is_encoder_mode = 0; // �Ƿ�ʹ�ñ�����ģʽ
	timer_config.prescale = TIMER_PSC - 1; // Ԥ��Ƶϵ�� - 1
	timer_config.auto_load = TIMER_ATL - 1; // �Զ�װ��ֵ - 1
	timer_config.chn_n = 1; // ͨ����(Ӳ���汾��>=2ʱ����ָ��)
	timer_config.cap_cmp_sel = CAP_SEL_CHN0 | CAP_SEL_CHN1 | CAP_SEL_CHN2 | CAP_SEL_CHN3; // ����/�Ƚ�ѡ��
	// �Ƚ�ֵ
	timer_config.cmp[0] = 0;
	timer_config.cmp[1] = 0;
	timer_config.cmp[2] = 0;
	timer_config.cmp[3] = 0;
	// �Ƚ����ģʽ
	timer_config.oc_mode[0] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[1] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[2] = OC_MODE_GEQ_HIGH;
	timer_config.oc_mode[3] = OC_MODE_GEQ_HIGH;
	// ���ؼ������
	timer_config.edge_detect_type[0] = CAP_POS_EDGE;
	timer_config.edge_detect_type[1] = CAP_POS_EDGE;
	timer_config.edge_detect_type[2] = CAP_POS_EDGE;
	timer_config.edge_detect_type[3] = CAP_POS_EDGE;
	// �����˲���ֵ
	timer_config.edge_filter_th[0] = 0;
	timer_config.edge_filter_th[1] = 0;
	timer_config.edge_filter_th[2] = 0;
	timer_config.edge_filter_th[3] = 0;
	
	init_apb_timer(&timer, BASEADDR_TIMER, &timer_config);
	
	NVIC_SetPriority((IRQn_Type)TIMER_ITR_ID, 0x03); // NVIC����3���ж����ȼ�
	NVIC_EnableIRQ((IRQn_Type)TIMER_ITR_ID); // NVICʹ��3���ж�
	
	remote_ctrl_init(&timer);
	
	while(1){
		if(remote_ctrl_key_id != -1){
			// �������ң�ذ�������...
			
			remote_ctrl_key_id = -1;
		}
	}
}
