/************************************************************************************************************************
APB-TIMER����(�ӿ�ͷ�ļ�)
@brief  APB-TIMER����
@date   2024/09/21
@author �¼�ҫ
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ͨ�����
#define APB_TIMER_CH0 0x00 // ͨ��0
#define APB_TIMER_CH1 0x01 // ͨ��1
#define APB_TIMER_CH2 0x02 // ͨ��2
#define APB_TIMER_CH3 0x03 // ͨ��3

// ����/�Ƚ�ѡ��
#define CAP_SEL_CHN0 0x00 // ͨ��0��Ϊ����ģʽ
#define CMP_SEL_CHN0 0x01 // ͨ��0��Ϊ�Ƚ�ģʽ
#define CAP_SEL_CHN1 0x00 // ͨ��1��Ϊ����ģʽ
#define CMP_SEL_CHN1 0x02 // ͨ��1��Ϊ�Ƚ�ģʽ
#define CAP_SEL_CHN2 0x00 // ͨ��2��Ϊ����ģʽ
#define CMP_SEL_CHN2 0x04 // ͨ��2��Ϊ�Ƚ�ģʽ
#define CAP_SEL_CHN3 0x00 // ͨ��3��Ϊ����ģʽ
#define CMP_SEL_CHN3 0x08 // ͨ��3��Ϊ�Ƚ�ģʽ

// �Ƚ����ģʽ
#define OC_MODE_GEQ_HIGH 0x00 // ����ֵ>=�Ƚ�ֵʱ����ߵ�ƽ
#define OC_MODE_LT_HIGH 0x01 // ����ֵ<�Ƚ�ֵʱ����ߵ�ƽ

// ���벶����ؼ������
#define CAP_POS_EDGE 0x00 // ����������
#define CAP_NEG_EDGE 0x01 // �����½���
#define CAP_BOTH_EDGE 0x02 // ����˫��

// �ж���������
#define ITR_TIMER_ALL_MASK 0x1F // �����ж�
#define ITR_TIMER_ELAPSED_MASK 0x01 // ��������ж�
#define ITR_INPUT_CAP_CHN0_MASK 0x02 // ͨ��0���벶���ж�
#define ITR_INPUT_CAP_CHN1_MASK 0x04 // ͨ��1���벶���ж�
#define ITR_INPUT_CAP_CHN2_MASK 0x08 // ͨ��2���벶���ж�
#define ITR_INPUT_CAP_CHN3_MASK 0x10 // ͨ��3���벶���ж�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_TIMER_H
#define __APB_TIMER_H

// APB-TIMER����/�Ƚ�ͨ��(�Ĵ���ӳ��ṹ��)
typedef struct{
	uint32_t cap_cmp; // ����/�Ƚ�ֵ
	uint32_t cap_config; // ��������
}ApbTimerChnHd;

// APB-TIMER(�Ĵ���ӳ��ṹ��)
typedef struct{
	uint32_t prescale; // Ԥ��Ƶϵ�� - 1
	uint32_t auto_load; // �Զ�װ��ֵ - 1
	uint32_t count; // ��ʱ������ֵ
	uint32_t ctrl; // ��ʱ������, ����/�Ƚ�ѡ��, �Ƚ����ʹ��, �汾��
	uint32_t itr_en; // �ж�ʹ��
	uint32_t itr_flag; // �жϱ�־
	ApbTimerChnHd chn_hd[4]; // ����/�Ƚ�ͨ��(�Ĵ�����)
}ApbTimerHd;

// APB-TIMER(����ṹ��)
typedef struct{
	ApbTimerHd* hardware; // APB-TIMER�Ĵ����ӿ�(�ṹ��ָ��)
	uint8_t chn_n; // ����/�Ƚ�ͨ����
}ApbTimer;

// APB-TIMER(��ʼ�����ýṹ��)
typedef struct{
	uint8_t cap_cmp_sel; // ����/�Ƚ�ѡ��
	uint8_t chn_n; // ͨ����
	uint32_t prescale; // Ԥ��Ƶϵ�� - 1
	uint32_t auto_load; // �Զ�װ��ֵ - 1
	uint32_t cmp[4]; // �Ƚ�ֵ
	uint8_t oc_mode[4]; // �Ƚ����ģʽ
	uint8_t edge_detect_type[4]; // ���ؼ������
	uint8_t edge_filter_th[4]; // �����˲���ֵ
}ApbTimerConfig;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// APB-TIMER��ȡӲ���汾��
#define __apb_timer_get_hw_version(timer) ((uint8_t)(((timer)->hardware->ctrl) >> 16))

// APB-TIMER������ʱ��
#define __apb_timer_start(timer) (timer)->hardware->ctrl = ((timer)->hardware->ctrl) | 0x00000001
// APB-TIMER��ͣ��ʱ��
#define __apb_timer_stop(timer) (timer)->hardware->ctrl = ((timer)->hardware->ctrl) & 0xFFFFFFFE
// APB-TIMER���ö�ʱ��
#define __apb_timer_reset(timer) (timer)->hardware->count = (timer)->hardware->auto_load

// APB-TIMER���ü���ֵ
#define __apb_timer_set_cnt(timer, cnt) (timer)->hardware->count = cnt

// APB-TIMER��ȡԤ��Ƶϵ��
#define __apb_timer_get_prescale(timer) ((timer)->hardware->prescale)
// APB-TIMER��ȡ�Զ�װ��ֵ
#define __apb_timer_get_autoload(timer) ((timer)->hardware->auto_load)
// APB-TIMER��ȡ����ֵ
#define __apb_timer_get_cnt(timer) ((timer)->hardware->count)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int init_apb_timer(ApbTimer* timer, uint32_t base_addr, const ApbTimerConfig* config); // ��ʼ��APB-TIMER

void apb_timer_enable_itr(ApbTimer* timer, uint8_t itr_en); // APB-TIMERʹ���ж�
void apb_timer_disable_itr(ApbTimer* timer); // APB-TIMER�����ж�
uint8_t apb_timer_get_itr_status(ApbTimer* timer); // APB-TIMER��ȡ�ж�״̬
void apb_timer_clear_itr_flag(ApbTimer* timer); // APB-TIMER����жϱ�־

void apb_timer_start(ApbTimer* timer); // APB-TIMER������ʱ��
void apb_timer_stop(ApbTimer* timer); // APB-TIMER��ͣ��ʱ��
void apb_timer_reset(ApbTimer* timer); // APB-TIMER���ö�ʱ��

void apb_timer_set_prescale(ApbTimer* timer, uint32_t prescale); // APB-TIMER����Ԥ��Ƶϵ��
void apb_timer_set_autoload(ApbTimer* timer, uint32_t auto_load); // APB-TIMER�����Զ�װ��ֵ
void apb_timer_set_cnt(ApbTimer* timer, uint32_t cnt); // APB-TIMER���ü���ֵ

int apb_timer_start_oc(ApbTimer* timer, uint8_t chn_id); // APB-TIMER����ĳ��ͨ���ıȽ����
int apb_timer_stop_oc(ApbTimer* timer, uint8_t chn_id); // APB-TIMERֹͣĳ��ͨ���ıȽ����
int apb_timer_set_oc_mode(ApbTimer* timer, uint8_t chn_id, uint8_t oc_mode); // APB-TIMER����ĳ��ͨ���ıȽ����ģʽ
int apb_timer_set_cmp(ApbTimer* timer, uint8_t chn_id, uint32_t cmp); // APB-TIMER����ĳ��ͨ���ıȽ�ֵ
int apb_timer_set_cap_config(ApbTimer* timer, uint8_t chn_id, 
	uint8_t edge_detect_type, uint8_t edge_filter_th); // APB-TIMER����ĳ��ͨ���Ĳ�������

uint32_t apb_timer_get_prescale(ApbTimer* timer); // APB-TIMER��ȡԤ��Ƶϵ��
uint32_t apb_timer_get_autoload(ApbTimer* timer); // APB-TIMER��ȡ�Զ�װ��ֵ
uint32_t apb_timer_get_cnt(ApbTimer* timer); // APB-TIMER��ȡ����ֵ
uint32_t apb_timer_get_cap(ApbTimer* timer, uint8_t chn_id); // APB-TIMER��ȡĳ��ͨ���Ĳ���ֵ
