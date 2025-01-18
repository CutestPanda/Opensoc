/************************************************************************************************************************
APB-TIMER����(��Դ�ļ�)
@brief  APB-TIMER����
@date   2024/09/21
@author �¼�ҫ
@eidt   2024/09/21 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../include/apb_timer.h"

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
@return none
*************************/
void init_apb_timer(ApbTimer* timer, uint32_t base_addr, const ApbTimerConfig* config){
	timer->hardware = (ApbTimerHd*)base_addr;
	
	timer->prescale = config->prescale;
	timer->auto_load = config->auto_load;
	timer->cap_cmp_sel = config->cap_cmp_sel;
	timer->chn_n = config->chn_n;
	
	timer->hardware->prescale = config->prescale;
	timer->hardware->auto_load = config->auto_load;
	timer->hardware->count = config->prescale;
	timer->hardware->ctrl = (((uint32_t)config->cap_cmp_sel) << 8);
	
	for(uint8_t i = 0;i < 4;i++){
		if(((config->cap_cmp_sel >> i) & 0x01) == CAP_SEL){
			// ��ǰͨ��ѡ�����벶��
			timer->hardware->chn_hd[i].cap_config = ((uint32_t)config->edge_filter_th[i]) | 
				(((uint32_t)config->edge_detect_type[i]) << 8);
		}else{
			// ��ǰͨ��ѡ������Ƚ�
			timer->hardware->chn_hd[i].cap_cmp = config->cmp[i];
		}
	}
}

/*************************
@cfg
@public
@brief  APB-TIMERʹ���ж�
@param  timer APB-TIMER(�ṹ��ָ��)
        itr_en �ж�ʹ������
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
	timer->hardware->ctrl = (((uint32_t)timer->cap_cmp_sel) << 8) | 0x00000001;
}

/*************************
@ctrl
@public
@brief  APB-TIMER��ͣ��ʱ��
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_stop(ApbTimer* timer){
	timer->hardware->ctrl = (((uint32_t)timer->cap_cmp_sel) << 8);
}

/*************************
@ctrl
@public
@brief  APB-TIMER���ö�ʱ��
@param  timer APB-TIMER(�ṹ��ָ��)
@return none
*************************/
void apb_timer_reset(ApbTimer* timer){
	timer->hardware->count = timer->auto_load;
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
	timer->prescale = prescale;
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
	timer->auto_load = auto_load;
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
@set
@public
@brief  APB-TIMER����ĳ��ͨ���ıȽ�ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
		    chn_id ͨ�����
				cmp �Ƚ�ֵ
@return �Ƿ�ɹ�
*************************/
int apb_timer_set_cmp(ApbTimer* timer, uint8_t chn_id, uint32_t cmp){
	if((chn_id <= timer->chn_n - 1) && (((timer->cap_cmp_sel >> chn_id) & 0x01) == CMP_SEL)){
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
		    chn_id ͨ�����
			  edge_detect_type ���ؼ������
				edge_filter_th �����˲���ֵ
@return �Ƿ�ɹ�
*************************/
int apb_timer_set_cap_config(ApbTimer* timer, uint8_t chn_id, 
	uint8_t edge_detect_type, uint8_t edge_filter_th){
	if((chn_id <= timer->chn_n - 1) && (((timer->cap_cmp_sel >> chn_id) & 0x01) == CAP_SEL)){
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
	return timer->prescale;
}

/*************************
@get
@public
@brief  APB-TIMER��ȡ�Զ�װ��ֵ
@param  timer APB-TIMER(�ṹ��ָ��)
@return �Զ�װ��ֵ
*************************/
uint32_t apb_timer_get_autoload(ApbTimer* timer){
	return timer->auto_load;
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
@param  chn_id ͨ�����
				timer APB-TIMER(�ṹ��ָ��)
@return ����ֵ
*************************/
uint32_t apb_timer_get_cap(ApbTimer* timer, uint8_t chn_id){
	if(chn_id > timer->chn_n - 1){
		return 0x00000000;
	}else{
		return timer->hardware->chn_hd[chn_id].cap_cmp;
	}
}
