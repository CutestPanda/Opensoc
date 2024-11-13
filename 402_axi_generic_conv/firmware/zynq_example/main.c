#include "axi_generic_conv.h"
#include "gic.h"

#include "xil_cache.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define PRL_KERNAL_N 4 // �˲�����
#define PRL_CHN_N 4 // ͨ��������

#define FT_MAP_W 8 // ����ͼ���
#define FT_MAP_H 3 // ����ͼ�߶�
#define FT_MAP_CHN 5 // ����ͼͨ����
#define KERNAL_N 5 // ����˸���

#define RD_REQ_DSC_BUF_LEN 1024 * 2 + 64 // �����������ӻ���������(��˫�ּ�)
#define WT_REQ_DSC_BUF_LEN 1024 * 2 + 64 // д���������ӻ���������(��˫�ּ�)

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void axi_generic_conv_intr_handler(void* callback_ref); // AXIͨ�þ���������жϷ�����

void generate_ft_pars(void); // ������������ͼ/����˲���/���Բ���
uint32_t* ptr_align(uint32_t* ptr, uint32_t align_byte_n); // ��������Ķ����ַ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ������
static XScuGic gic; // ȫ���жϿ�����(����ṹ��)
static AXIGenericConv axi_conv; // AXIͨ�þ��������(����ṹ��)

// ��������ͼ������
static uint16_t in_ft_map_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4];
// ����˻�����
static uint16_t kernal_buf[3 * 3 * FT_MAP_CHN * KERNAL_N + 4];
// ���Բ���A������
static uint16_t linear_a_buf[FT_MAP_CHN + 4];
// ���Բ���B������
static uint16_t linear_b_buf[FT_MAP_CHN + 4];
// �������ͼ������
static uint16_t out_ft_map_buf[FT_MAP_W * FT_MAP_H * KERNAL_N + 4];

// �����������ӻ�����
static uint32_t rd_req_dsc_buf[RD_REQ_DSC_BUF_LEN];
static uint32_t* rd_req_dsc_buf_ptr;
static uint32_t rd_req_n;
// д���������ӻ�����
static uint32_t wt_req_dsc_buf[WT_REQ_DSC_BUF_LEN];
static uint32_t* wt_req_dsc_buf_ptr;
static uint32_t wt_req_n;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(void){
	// ��ʼ��ȫ���жϿ�����
	if(init_gic(&gic, XPAR_SCUGIC_SINGLE_DEVICE_ID) == XST_FAILURE){
		return XST_FAILURE;
	}
	// ��ʼ��AXIͨ�þ��������
	init_axi_generic_conv(&axi_conv, XPAR_AXI_GENERIC_CONV_0_BASEADDR);

	// ����AXIͨ�þ��������������ʱ����
	AXIGenericConvCfg axi_conv_cfg;

	axi_conv_cfg.kernal_type = TYPE_3x3;
	axi_conv_cfg.en_top_padding = 1;
	axi_conv_cfg.en_bottom_padding = 1;
	axi_conv_cfg.en_left_padding = 1;
	axi_conv_cfg.en_right_padding = 1;
	axi_conv_cfg.feature_map_w = FT_MAP_W;
	axi_conv_cfg.feature_map_h = FT_MAP_H;
	axi_conv_cfg.feature_map_chn_n = FT_MAP_CHN;
	axi_conv_cfg.kernal_n = KERNAL_N;
	axi_conv_cfg.act_rate_c_0 = (1 << 14);
	axi_conv_cfg.act_rate_c_1 = 0;

	axi_generic_conv_set_conv_params(&axi_conv, &axi_conv_cfg);

	// ������������ͼ/����˲���/���Բ���
	generate_ft_pars();
	// ���ɶ���Ķ����������ӻ�����ָ��
	rd_req_dsc_buf_ptr = ptr_align(rd_req_dsc_buf, RD_REQ_BUF_ALIGNMENT);
	// ���ɶ����д���������ӻ�����ָ��
	wt_req_dsc_buf_ptr = ptr_align(wt_req_dsc_buf, WT_REQ_BUF_ALIGNMENT);
	// ���ɶ�����������
	rd_req_n = axi_generic_conv_generate_rd_req_dsc(rd_req_dsc_buf_ptr, (uint32_t)linear_a_buf, (uint32_t)linear_b_buf,
		(uint32_t)kernal_buf, (uint32_t)in_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_CHN, PRL_CHN_N,
		FT_MAP_W, FT_MAP_H, 1, 1);
	// ����д����������
	wt_req_n = axi_generic_conv_generate_wt_req_dsc(wt_req_dsc_buf_ptr, (uint32_t)out_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_W, FT_MAP_H);

	// ˢ������Cache
	Xil_DCacheFlushRange((INTPTR)in_ft_map_buf, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)kernal_buf, (3 * 3 * FT_MAP_CHN * KERNAL_N + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_a_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_b_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)rd_req_dsc_buf, RD_REQ_DSC_BUF_LEN * 4);
	Xil_DCacheFlushRange((INTPTR)wt_req_dsc_buf, WT_REQ_DSC_BUF_LEN * 4);

	// ����AXIͨ�þ��������
	axi_generic_conv_start(&axi_conv);

	// ����AXIͨ�þ�����������ж�
	if(gic_conn_config_itr(&gic, NULL, axi_generic_conv_intr_handler, XPAR_FABRIC_AXI_GENERIC_CONV_0_ITR_INTR,
		20, ITR_RISING_EDGE_TG) == XST_FAILURE){
		return XST_FAILURE;
	}
	axi_generic_conv_set_wt_req_itr_th(&axi_conv, FT_MAP_H * KERNAL_N);
	axi_generic_conv_enable_itr(&axi_conv, AXI_GENERIC_CONV_ITR_WT_FNS);

	// �ύ������������
	if(axi_generic_conv_post_rd_req_dsc(&axi_conv, (uint32_t)rd_req_dsc_buf_ptr, rd_req_n)){
		return XST_FAILURE;
	}
	// �ύд����������
	if(axi_generic_conv_post_wt_req_dsc(&axi_conv, (uint32_t)wt_req_dsc_buf_ptr, wt_req_n)){
		return XST_FAILURE;
	}

	while(1){

	}

	return XST_SUCCESS;
}

/*************************
@itr_handler
@private
@brief  AXIͨ�þ���������жϷ�����
@param  callback_ref �ص����
@return none
*************************/
void axi_generic_conv_intr_handler(void* callback_ref){
	uint32_t itr_sts = axi_generic_conv_get_itr_sts(&axi_conv); // �ж�״̬����

	if(itr_sts & AXI_GENERIC_CONV_ITR_WT_FNS){
		// д����������ж�
		Xil_DCacheFlushRange((INTPTR)out_ft_map_buf, (FT_MAP_W * FT_MAP_H * KERNAL_N + 4) * 2);
	}

	axi_generic_conv_clear_itr_flag(&axi_conv); // ����жϱ�־
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@logic
@private
@brief  ������������ͼ/����˲���/���Բ���
@param  none
@return none
*************************/
void generate_ft_pars(void){
	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int j = 0;j < FT_MAP_W * FT_MAP_H;j++){
			in_ft_map_buf[i * FT_MAP_W * FT_MAP_H + j] = j + 1;
		}
	}

	for(int i = 0;i < KERNAL_N;i++){
		for(int j = 0;j < FT_MAP_CHN;j++){
			for(int m = 0;m < 9;m++){
				kernal_buf[i * FT_MAP_CHN * 9 + j * 9 + m] = (1 << 10);
			}
		}
	}

	for(int i = 0;i < FT_MAP_CHN;i++){
		linear_a_buf[i] = (1 << 12);
		linear_b_buf[i] = 0;
	}
}

/*************************
@logic
@private
@brief  ��������Ķ����ַ
@param  ptr ԭʼָ��
        align_byte_n �����ֽ���
@return �����ָ��
*************************/
uint32_t* ptr_align(uint32_t* ptr, uint32_t align_byte_n){
	while(((uint32_t)ptr) % align_byte_n){
		ptr++;
	}

	return ptr;
}
