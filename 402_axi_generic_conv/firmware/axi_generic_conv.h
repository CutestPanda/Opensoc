#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �ж���������
#define AXI_GENERIC_CONV_ITR_ALL 0x00000007
#define AXI_GENERIC_CONV_ITR_RD_REQ_DSC_DMA 0x00000001 // ������������DMA����������ж�
#define AXI_GENERIC_CONV_ITR_WT_REQ_DSC_DMA 0x00000002 // д����������DMA����������ж�
#define AXI_GENERIC_CONV_ITR_WT_FNS 0x00000004 // д����������ж�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __AXI_GENERIC_CONV_H

#define __AXI_GENERIC_CONV_H

// ���Ͷ���:���������
typedef enum{
	TYPE_3x3, TYPE_1x1
}KernalType;

// ���Ͷ���: ͨ�þ�����㵥Ԫ�ļĴ�����
typedef struct{
	uint32_t ctrl_sts;
	uint32_t itr_en;
	uint32_t itr_flag;
	uint32_t wt_req_itr_th;
	uint32_t flow_en;
	uint32_t kernal_style;
	uint32_t rd_req_buf_baseaddr;
	uint32_t rd_req_n;
	uint32_t wt_req_buf_baseaddr;
	uint32_t wt_req_n;
	uint32_t feature_map_w_h;
	uint32_t kernal_c_n;
	uint32_t act_rate_c_0;
	uint32_t act_rate_c_1;
	uint32_t wt_req_fns_n;
}AXIGenericConvHw;

// ���Ͷ���: ͨ�þ�����㵥Ԫ������ʱ����
typedef struct{
	KernalType kernal_type;
	uint8_t en_top_padding;
	uint8_t en_bottom_padding;
	uint8_t en_left_padding;
	uint8_t en_right_padding;
	uint16_t feature_map_w;
	uint16_t feature_map_h;
	uint16_t feature_map_chn_n;
	uint16_t kernal_n;
	int32_t act_rate_c_0;
	int32_t act_rate_c_1;
}AXIGenericConvCfg;

// ���Ͷ���: ͨ�þ�����㵥Ԫ��������
typedef struct{
	AXIGenericConvHw* hardware;
}AXIGenericConv;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_axi_generic_conv(AXIGenericConv* axi_conv, uint32_t baseaddr); // ��ʼ��AXIͨ�þ��������

void axi_generic_conv_set_conv_params(AXIGenericConv* axi_conv, AXIGenericConvCfg* cfg); // ����AXIͨ�þ��������������ʱ����
void axi_generic_conv_start(AXIGenericConv* axi_conv); // ����AXIͨ�þ��������
void axi_generic_conv_resume(AXIGenericConv* axi_conv); // ��������AXIͨ�þ��������
void axi_generic_conv_suspend(AXIGenericConv* axi_conv); // ��ͣAXIͨ�þ��������
void axi_generic_conv_enable_itr(AXIGenericConv* axi_conv, uint32_t itr_mask); // ʹ��AXIͨ�þ�����������ж�
void axi_generic_conv_disable_itr(AXIGenericConv* axi_conv, uint32_t itr_mask); // ����AXIͨ�þ�����������ж�
void axi_generic_conv_set_wt_req_itr_th(AXIGenericConv* axi_conv, uint32_t wt_req_itr_th); // ����AXIͨ�þ����������д����������ж���ֵ
uint32_t axi_generic_conv_get_itr_sts(AXIGenericConv* axi_conv); // ��ȡAXIͨ�þ�����������ж�״̬
void axi_generic_conv_clear_itr_flag(AXIGenericConv* axi_conv); // ���AXIͨ�þ�����������жϱ�־
int axi_generic_conv_post_rd_req_dsc(AXIGenericConv* axi_conv, uint32_t rd_req_buf_baseaddr, uint32_t rd_req_n); // ��AXIͨ�þ���������ύ������������
int axi_generic_conv_post_wt_req_dsc(AXIGenericConv* axi_conv, uint32_t wt_req_buf_baseaddr, uint32_t wt_req_n); // ��AXIͨ�þ���������ύд����������
void axi_generic_conv_set_wt_req_fns_n(AXIGenericConv* axi_conv, uint32_t wt_req_fns_n); //����AXIͨ�þ������������ɵ�д�������
uint8_t axi_generic_conv_is_rd_req_dsc_dma_busy(AXIGenericConv* axi_conv); // �ж�AXIͨ�þ���������Ķ�����������DMA�Ƿ�æµ
uint8_t axi_generic_conv_is_wt_req_dsc_dma_busy(AXIGenericConv* axi_conv); // �ж�AXIͨ�þ����������д����������DMA�Ƿ�æµ
uint32_t axi_generic_conv_get_wt_req_fns_n(AXIGenericConv* axi_conv); //��ȡAXIͨ�þ������������ɵ�д�������

// ���ɶ�����������
uint32_t axi_generic_conv_generate_rd_req_dsc(uint32_t* rd_req_dsc_buf_ptr,
	uint32_t linear_a_buf_baseaddr, uint32_t linear_b_buf_baseaddr, uint32_t kernal_buf_baseaddr, uint32_t in_ft_map_buf_baseaddr,
	uint32_t kernal_n, uint8_t prl_kernal_n,
	uint32_t ft_map_chn_n, uint8_t prl_chn_n,
	uint32_t in_ft_map_w, uint32_t in_ft_map_h,
	uint8_t en_top_padding, uint8_t en_bottom_padding,
	KernalType kernal_type);
// ����д����������
uint32_t axi_generic_conv_generate_wt_req_dsc(
	uint32_t* wt_req_dsc_buf_ptr,
	uint32_t out_ft_map_buf_baseaddr,
	uint32_t kernal_n, uint8_t prl_kernal_n,
	uint32_t out_ft_map_w, uint32_t out_ft_map_h);
