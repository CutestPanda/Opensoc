/************************************************************************************************************************
APB-TIMER����(��Դ�ļ�)
@brief  APB-TIMER����
@date   2024/09/21
@author �¼�ҫ
@eidt   2024/09/21 1.00 �����˵�һ����ʽ�汾
		2025/07/27 1.10 ɾ����ApbTimer�ṹ����ı���ֵ
						�����˱Ƚ����ʹ�ܡ��Ƚ����ģʽ
		2025/08/11 1.20 �����˱�����ģʽ
************************************************************************************************************************/

#include "apb_timer.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ����/�Ƚ�ѡ��
#define CAP_SEL 0x00 // ����
#define CMP_SEL 0x01 // �Ƚ�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��APB-TIMER
@param  timer APB-TIMER(�ṹ��ָ��)
        base_addr APB-TIMER�������ַ
		config APB-TIMER��ʼ������(�ṹ��ָ��)
@return �Ƿ�ɹ�
*************************/
int init_apb_timer(ApbTimer* timer, uint32_t base_addr, const ApbTimerConfig* config){
	timer->hardware = (ApbTimerHd*)base_addr;
	
	timer->hw_version = (uint8_t)(timer->hardware->ctrl >> 16);
	
	if(timer->hw_version >= 2){
		timer->chn_n = (uint8_t)((timer->hardware->ctrl >> 24) & 0x07);
	}else{
		timer->chn_n = config->chn_n;
	}
	
	if(timer->hw_version > 2){
		return -1;
	}
	
	if(config->is_encoder_mode && ((timer->hw_version < 2) || (timer->chn_n < 2))){
		return -1;
	}
	
	timer->hardware->prescale = config->prescale;
	timer->hardware->auto_load = config->auto_load;
	timer->hardware->count = config->prescale;
	timer->hardware->ctrl = (((uint32_t)config->cap_cmp_sel) << 8) | (((uint32_t)config->is_encoder_mode) << 27);
	
	for(uint8_t i = 0;i < 4;i++){
		if(((config->cap_cmp_sel >> i) & 0x01) == CAP_SEL){
			// ��ǰͨ��ѡ�����벶��
			timer->hardware->chn_hd[i].cap_config = ((uint32_t)config->edge_filter_th[i]) | 
				(((uint32_t)config->edge_detect_type[i]) << 8);
		}else{
			// ��ǰͨ��ѡ������Ƚ�
			timer->hardware->chn_hd[i].cap_cmp = config->cmp[i];
			
			if(timer->hw_version >= 1){
				timer->hardware->chn_hd[i].cap_config = (((uint32_t)config->oc_mode[i]) << 10);
			}
		}
	}
	
	return 0;
}

/*************************
@cfg
@public
@brief  APB-TIMERʹ���ж�
@param  timer APB-TIMER(�ṹ��ָ��)
        itr_en �ж�ʹ������(
			{
				ITR_TIMER_ALL_MASK, 
				ITR_TIMER_ELAPSED_MASK, 
				ITR_INPUT_CAP_CHN0_MASK, 
				ITR_INPUT_CAP_CHN1_MASK, 
				ITR_INPUT_CAP_CHN2_MASK, 
				ITR_INPUT_CAP_CHN3_MASK
			}
		�İ�λ��)
@return none
*************************/
void apb_timer_enable_itr(ApbTimer* timer, uint8_t itr_en){
	timer->hardware->itr_en = (((uint32_t)itr_en) << 8) | 0x00000001;
}

/*************************
@cfg
@public
@brief  APB-TIMER�����ж�
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_disable_itr(ApbTimer* timer){
	timer->hardware->itr_en = 0x00000000;
}

/*************************
@sts
@public
@brief  APB-TIMER��ȡ�ж�״̬
@param  timer APB-TIMER(�ṹ��ָ��)
@return �жϱ�־����
*************************/
uint8_t apb_timer_get_itr_status(ApbTimer* timer){
	return (uint8_t)(timer->hardware->itr_flag >> 8);
}

/*************************
@cfg
@public
@brief  APB-TIMER����жϱ�־
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_clear_itr_flag(ApbTimer* timer){
	timer->hardware->itr_flag = 0x00000000;
}

/*************************
@ctrl
@public
@brief  APB-TIMER������ʱ��
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_start(ApbTimer* timer){
	timer->hardware->ctrl = (timer->hardware->ctrl) | 0x00000001;
}

/*************************
@ctrl
@public
@brief  APB-TIMER��ͣ��ʱ��
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_stop(ApbTimer* timer){
	timer->hardware->ctrl = (timer->hardware->ctrl) & 0xFFFFFFFE;
}

/*************************
@ctrl
@public
@brief  APB-TIMER���ö�ʱ��
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_reset(ApbTimer* timer){
	timer->hardware->count = timer->hardware->auto_load;
}

/*************************
@set
@public
@brief  APB-TIMER����Ԥ��Ƶϵ��
@param  timer APB-TIMER(�ṹ��ָ��)
		prescale Ԥ��Ƶϵ��
@return none
*************************/
void apb_timer_set_prescale(ApbTimer* timer, uint32_t prescale){
	timer->hardware->prescale = prescale;
}

/*************************
@set
@public
@brief  APB-TIMER�����Զ�װ��ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
		auto_load �Զ�װ��ֵ
@return none
*************************/
void apb_timer_set_autoload(ApbTimer* timer, uint32_t auto_load){
	timer->hardware->auto_load = auto_load;
}

/*************************
@set
@public
@brief  APB-TIMER���ü���ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
		cnt ����ֵ
@return none
*************************/
void apb_timer_set_cnt(ApbTimer* timer, uint32_t cnt){
	timer->hardware->count = cnt;
}

/*************************
@ctrl
@public
@brief  APB-TIMER����ĳ��ͨ���ıȽ����
@param  timer APB-TIMER(�ṹ��ָ��)
		chn_id ͨ�����(��{APB_TIMER_CH0, APB_TIMER_CH1, APB_TIMER_CH2, APB_TIMER_CH3}��ѡ��1��)
@return �Ƿ�ɹ�
*************************/
int apb_timer_start_oc(ApbTimer* timer, uint8_t chn_id){
	if((timer->hw_version >= 1) && timer->chn_n && (chn_id <= timer->chn_n - 1)){
		timer->hardware->ctrl = timer->hardware->ctrl | (0x00001000 << chn_id);
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@ctrl
@public
@brief  APB-TIMERֹͣĳ��ͨ���ıȽ����
@param  timer APB-TIMER(�ṹ��ָ��)
		chn_id ͨ�����(��{APB_TIMER_CH0, APB_TIMER_CH1, APB_TIMER_CH2, APB_TIMER_CH3}��ѡ��1��)
@return �Ƿ�ɹ�
*************************/
int apb_timer_stop_oc(ApbTimer* timer, uint8_t chn_id){
	if((timer->hw_version >= 1) && timer->chn_n && (chn_id <= timer->chn_n - 1)){
		timer->hardware->ctrl = timer->hardware->ctrl & (~(0x00001000 << chn_id));
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@set
@public
@brief  APB-TIMER����ĳ��ͨ���ıȽ����ģʽ
@param  timer APB-TIMER(�ṹ��ָ��)
		chn_id ͨ�����(��{APB_TIMER_CH0, APB_TIMER_CH1, APB_TIMER_CH2, APB_TIMER_CH3}��ѡ��1��)
		oc_mode �Ƚ����ģʽ(��{OC_MODE_GEQ_HIGH, OC_MODE_LT_HIGH}��ѡ��1��)
@return �Ƿ�ɹ�
*************************/
int apb_timer_set_oc_mode(ApbTimer* timer, uint8_t chn_id, uint8_t oc_mode){
	if((timer->hw_version >= 1) && timer->chn_n && (chn_id <= timer->chn_n - 1) && ((oc_mode == OC_MODE_GEQ_HIGH) || (oc_mode == OC_MODE_LT_HIGH))){
		timer->hardware->chn_hd[chn_id].cap_config = (((uint32_t)oc_mode) << 10);
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@set
@public
@brief  APB-TIMER����ĳ��ͨ���ıȽ�ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
		chn_id ͨ�����(��{APB_TIMER_CH0, APB_TIMER_CH1, APB_TIMER_CH2, APB_TIMER_CH3}��ѡ��1��)
		cmp �Ƚ�ֵ
@return �Ƿ�ɹ�
*************************/
int apb_timer_set_cmp(ApbTimer* timer, uint8_t chn_id, uint32_t cmp){
	uint8_t cap_cmp_sel = (uint8_t)(timer->hardware->ctrl >> 8);
	
	if(timer->chn_n && (chn_id <= timer->chn_n - 1) && (((cap_cmp_sel >> chn_id) & 0x01) == CMP_SEL)){
		timer->hardware->chn_hd[chn_id].cap_cmp = cmp;
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@set
@public
@brief  APB-TIMER����ĳ��ͨ���Ĳ�������
@param  timer APB-TIMER(�ṹ��ָ��)
		chn_id ͨ�����(��{APB_TIMER_CH0, APB_TIMER_CH1, APB_TIMER_CH2, APB_TIMER_CH3}��ѡ��1��)
		edge_detect_type ���ؼ������(��{CAP_POS_EDGE, CAP_NEG_EDGE, CAP_BOTH_EDGE}��ѡ��1��)
		edge_filter_th �����˲���ֵ
@return �Ƿ�ɹ�
*************************/
int apb_timer_set_cap_config(ApbTimer* timer, uint8_t chn_id, 
	uint8_t edge_detect_type, uint8_t edge_filter_th){
	uint8_t cap_cmp_sel = (uint8_t)(timer->hardware->ctrl >> 8);
	
	if(timer->chn_n && (chn_id <= timer->chn_n - 1) && (((cap_cmp_sel >> chn_id) & 0x01) == CAP_SEL)){
		timer->hardware->chn_hd[chn_id].cap_config = ((uint32_t)edge_filter_th) | 
			(((uint32_t)edge_detect_type) << 8);
		
		return 0;
	}else{
		return -1;
	}
}

/*************************
@get
@public
@brief  APB-TIMER��ȡԤ��Ƶϵ��
@param  timer APB-TIMER(�ṹ��ָ��)
@return Ԥ��Ƶϵ��
*************************/
uint32_t apb_timer_get_prescale(ApbTimer* timer){
	return timer->hardware->prescale;
}

/*************************
@get
@public
@brief  APB-TIMER��ȡ�Զ�װ��ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
@return �Զ�װ��ֵ
*************************/
uint32_t apb_timer_get_autoload(ApbTimer* timer){
	return timer->hardware->auto_load;
}

/*************************
@get
@public
@brief  APB-TIMER��ȡ����ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
@return ��ǰ����ֵ
*************************/
uint32_t apb_timer_get_cnt(ApbTimer* timer){
	return timer->hardware->count;
}

/*************************
@get
@public
@brief  APB-TIMER��ȡĳ��ͨ���Ĳ���ֵ
@param  chn_id ͨ�����(��{APB_TIMER_CH0, APB_TIMER_CH1, APB_TIMER_CH2, APB_TIMER_CH3}��ѡ��1��)
		timer APB-TIMER(�ṹ��ָ��)
@return ����ֵ
*************************/
uint32_t apb_timer_get_cap(ApbTimer* timer, uint8_t chn_id){
	if(timer->chn_n && (chn_id <= timer->chn_n - 1)){
		return timer->hardware->chn_hd[chn_id].cap_cmp;
	}else{
		return 0x00000000;
	}
}
