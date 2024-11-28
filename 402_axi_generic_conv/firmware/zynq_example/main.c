#include "axi_generic_conv.h"
#include "gic.h"

#include "xil_cache.h"
#include "xil_printf.h"

#include "time.h"
#include <stdlib.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define KERNAL_TYPE 1 // ���������(1 -> 3x3, 0 -> 1x1)

#define PRL_KERNAL_N 2 // �˲�����
#define PRL_CHN_N 2 // ͨ��������

#define FT_MAP_W 13 // ����ͼ���
#define FT_MAP_H 13 // ����ͼ�߶�
#define FT_MAP_CHN 32 // ����ͼͨ����
#define KERNAL_N 64 // ����˸���

#define ACT_RATE_C (1 << 13) // Relu����ϵ��

#define IN_FT_QUAZ_ACC 10 // ��������������
#define CONV_RES_EXT_FRAC_WIDTH 4 // ���������⿼�ǵ�С��λ��
#define CONV_RES_EXT_INT_WIDTH 4 // ���������⿼�ǵ�����λ��
#define AB_QUAZ_ACC 12 // a/bϵ����������
#define C_QUAZ_ACC 14 // cϵ����������

#define MAX_RD_REQ_N 1024 * 1024 * 16 // ���Ķ��������
#define MAX_WT_REQ_N 65536 // ����д�������

#define USE_ACP_PORT // ʹ��ACP�ӿ�

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void axi_generic_conv_intr_handler(void* callback_ref); // AXIͨ�þ���������жϷ�����

void generate_ft_pars(void); // ������������ͼ/����˲���/���Բ���
void generate_golden_ref(void); // ���ɻƽ�ο�
int check_conv_res(void); // ��������

uint32_t* ptr_align(uint32_t* ptr, uint32_t align_byte_n); // ��������Ķ����ַ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ������
static XScuGic gic; // ȫ���жϿ�����(����ṹ��)
static AXIGenericConv axi_conv; // AXIͨ�þ��������(����ṹ��)

// ��������ͼ������
static uint16_t in_ft_map_buf[FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4];
// ����˻�����
static uint16_t kernal_buf[(KERNAL_TYPE ? 9:1) * FT_MAP_CHN * KERNAL_N + 4];
// ���Բ���A������
static uint16_t linear_a_buf[KERNAL_N + 4];
// ���Բ���B������
static uint16_t linear_b_buf[KERNAL_N + 4];
// �������ͼ������
static uint16_t out_ft_map_buf[FT_MAP_W * FT_MAP_H * KERNAL_N + 4];
// �ƽ�ο�
static uint16_t golden_ref_buf[FT_MAP_W * FT_MAP_H * KERNAL_N + 4];

// �����������ӻ�����
static uint32_t rd_req_dsc_buf[MAX_RD_REQ_N * 2 + 64];
static uint32_t* rd_req_dsc_buf_ptr;
static uint32_t rd_req_n;
// д���������ӻ�����
static uint32_t wt_req_dsc_buf[MAX_WT_REQ_N * 2 + 64];
static uint32_t* wt_req_dsc_buf_ptr;
static uint32_t wt_req_n;

// �жϱ�־
static uint8_t conv_itr_flag = 0;

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

	axi_conv_cfg.kernal_type = KERNAL_TYPE ? TYPE_3x3:TYPE_1x1;
	axi_conv_cfg.en_top_padding = 1;
	axi_conv_cfg.en_bottom_padding = 1;
	axi_conv_cfg.en_left_padding = 1;
	axi_conv_cfg.en_right_padding = 1;
	axi_conv_cfg.feature_map_w = FT_MAP_W;
	axi_conv_cfg.feature_map_h = FT_MAP_H;
	axi_conv_cfg.feature_map_chn_n = FT_MAP_CHN;
	axi_conv_cfg.kernal_n = KERNAL_N;
	axi_conv_cfg.act_rate_c_0 = ACT_RATE_C;
	axi_conv_cfg.act_rate_c_1 = 0;

	axi_generic_conv_set_conv_params(&axi_conv, &axi_conv_cfg);

	// ������������ͼ/����˲���/���Բ���
	generate_ft_pars();
	// ���ɻƽ�ο�
	generate_golden_ref();
	// ���ɶ���Ķ����������ӻ�����ָ��
	rd_req_dsc_buf_ptr = ptr_align(rd_req_dsc_buf, RD_REQ_BUF_ALIGNMENT);
	// ���ɶ����д���������ӻ�����ָ��
	wt_req_dsc_buf_ptr = ptr_align(wt_req_dsc_buf, WT_REQ_BUF_ALIGNMENT);
	// ���ɶ�����������
	rd_req_n = axi_generic_conv_generate_rd_req_dsc(rd_req_dsc_buf_ptr, (uint32_t)linear_a_buf, (uint32_t)linear_b_buf,
		(uint32_t)kernal_buf, (uint32_t)in_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_CHN, PRL_CHN_N,
		FT_MAP_W, FT_MAP_H, 1, 1, KERNAL_TYPE ? TYPE_3x3:TYPE_1x1);
	// ����д����������
	wt_req_n = axi_generic_conv_generate_wt_req_dsc(wt_req_dsc_buf_ptr, (uint32_t)out_ft_map_buf, KERNAL_N, PRL_KERNAL_N, FT_MAP_W, FT_MAP_H);

#ifndef USE_ACP_PORT
	// ˢ������Cache
	Xil_DCacheFlushRange((INTPTR)in_ft_map_buf, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)out_ft_map_buf, (FT_MAP_W * FT_MAP_H * FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)kernal_buf, (3 * 3 * FT_MAP_CHN * KERNAL_N + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_a_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)linear_b_buf, (FT_MAP_CHN + 4) * 2);
	Xil_DCacheFlushRange((INTPTR)rd_req_dsc_buf, (MAX_RD_REQ_N * 2 + 64) * 4);
	Xil_DCacheFlushRange((INTPTR)wt_req_dsc_buf, (MAX_WT_REQ_N * 2 + 64) * 4);
#endif

	// ����AXIͨ�þ�����������ж�
	if(gic_conn_config_itr(&gic, NULL, axi_generic_conv_intr_handler, XPAR_FABRIC_AXI_GENERIC_CONV_0_ITR_INTR,
		20, ITR_RISING_EDGE_TG) == XST_FAILURE){
		return XST_FAILURE;
	}
	axi_generic_conv_set_wt_req_itr_th(&axi_conv, FT_MAP_H * KERNAL_N);
	axi_generic_conv_enable_itr(&axi_conv, AXI_GENERIC_CONV_ITR_WT_FNS);

	// ����AXIͨ�þ��������
	axi_generic_conv_start(&axi_conv);

	// �ύ������������
	if(axi_generic_conv_post_rd_req_dsc(&axi_conv, (uint32_t)rd_req_dsc_buf_ptr, rd_req_n)){
		return XST_FAILURE;
	}
	// �ύд����������
	if(axi_generic_conv_post_wt_req_dsc(&axi_conv, (uint32_t)wt_req_dsc_buf_ptr, wt_req_n)){
		return XST_FAILURE;
	}

	// �ȴ���1�β��Է��ؽ��
	while(!conv_itr_flag);

	int check_res = check_conv_res();

	if(check_res){
		xil_printf("conv res checked unsuccessfully!");
	}else{
		xil_printf("conv res checked successfully!");
	}

	conv_itr_flag = 0;

	// �����������ͼ��������׼����2�β���
	memset(out_ft_map_buf, 0, (FT_MAP_W * FT_MAP_H * KERNAL_N + 4) * 2);

	// ����AXIͨ�þ��������
	axi_generic_conv_start(&axi_conv);

	// �ύ������������
	if(axi_generic_conv_post_rd_req_dsc(&axi_conv, (uint32_t)rd_req_dsc_buf_ptr, rd_req_n)){
		return XST_FAILURE;
	}
	// �ύд����������
	if(axi_generic_conv_post_wt_req_dsc(&axi_conv, (uint32_t)wt_req_dsc_buf_ptr, wt_req_n)){
		return XST_FAILURE;
	}

	// �ȴ���2�β��Է��ؽ��
	while(!conv_itr_flag);

	check_res = check_conv_res();

	if(check_res){
		xil_printf("conv res checked unsuccessfully!");
	}else{
		xil_printf("conv res checked successfully!");
	}

	conv_itr_flag = 0;

	while(1);

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
	uint32_t wt_req_fns_n = axi_generic_conv_get_wt_req_fns_n(&axi_conv); // ����ɵ�д�������

	xil_printf("wt_req_fns_n = %d", wt_req_fns_n);

	if(itr_sts & AXI_GENERIC_CONV_ITR_WT_FNS){
		// д����������ж�
#ifndef USE_ACP_PORT
		Xil_DCacheFlushRange((INTPTR)out_ft_map_buf, (FT_MAP_W * FT_MAP_H * KERNAL_N + 4) * 2);
#endif
	}

	axi_generic_conv_clear_itr_flag(&axi_conv); // ����жϱ�־
	axi_generic_conv_set_wt_req_fns_n(&axi_conv, 0); // ��������ɵ�д�������

	conv_itr_flag = 1;
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
	uint16_t kernal_size = KERNAL_TYPE ? 9:1;

	for(int i = 0;i < FT_MAP_CHN;i++){
		for(int j = 0;j < FT_MAP_W * FT_MAP_H;j++){
			in_ft_map_buf[i * FT_MAP_W * FT_MAP_H + j] = rand();
		}
	}

	for(int i = 0;i < KERNAL_N;i++){
		for(int j = 0;j < FT_MAP_CHN;j++){
			for(int m = 0;m < kernal_size;m++){
				kernal_buf[i * FT_MAP_CHN * kernal_size + j * kernal_size + m] = rand();
			}
		}
	}

	for(int i = 0;i < KERNAL_N;i++){
		linear_a_buf[i] = rand();
		linear_b_buf[i] = rand();
	}
}

/*************************
@logic
@private
@brief  ���ɻƽ�ο�
@param  none
@return none
*************************/
void generate_golden_ref(void){
	for(int i = 0;i < KERNAL_N;i++){
		int16_t linear_a = linear_a_buf[i];
		int16_t linear_b = linear_b_buf[i];

		for(int y = 0;y < FT_MAP_H;y++){
			for(int x = 0;x < FT_MAP_W;x++){
				int64_t conv_res = 0;

				for(int c = 0;c < FT_MAP_CHN;c++){
					int16_t in_ft_roi[3][3];
					int16_t kernal[3][3];

					in_ft_roi[0][0] = ((x >= 1) && (y >= 1)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y - 1) * FT_MAP_W + (x - 1)]:0;
					in_ft_roi[0][1] = (y >= 1) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y - 1) * FT_MAP_W + x]:0;
					in_ft_roi[0][2] = ((x <= (FT_MAP_W - 2)) && (y >= 1)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y - 1) * FT_MAP_W + (x + 1)]:0;

					in_ft_roi[1][0] = (x >= 1) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + (x - 1)]:0;
					in_ft_roi[1][1] = in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x];
					in_ft_roi[1][2] = (x <= (FT_MAP_W - 2)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + (x + 1)]:0;

					in_ft_roi[2][0] = ((x >= 1) && (y <= (FT_MAP_H - 2))) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + (x - 1)]:0;
					in_ft_roi[2][1] = (y <= (FT_MAP_H - 2)) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + x]:0;
					in_ft_roi[2][2] = ((x <= (FT_MAP_W - 2)) && (y <= (FT_MAP_H - 2))) ? in_ft_map_buf[c * FT_MAP_W * FT_MAP_H + (y + 1) * FT_MAP_W + (x + 1)]:0;

					kernal[0][0] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 0]:0;
					kernal[0][1] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 1]:0;
					kernal[0][2] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 2]:0;
					kernal[1][0] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 3]:0;
					kernal[1][1] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 4]:kernal_buf[FT_MAP_CHN * i + c];
					kernal[1][2] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 5]:0;
					kernal[2][0] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 6]:0;
					kernal[2][1] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 7]:0;
					kernal[2][2] = KERNAL_TYPE ? kernal_buf[9 * FT_MAP_CHN * i + 9 * c + 8]:0;

					for(int m = 0;m < 3;m++){
						int32_t conv_row_res = 0;

						conv_row_res += ((int32_t)in_ft_roi[m][0]) * ((int32_t)kernal[m][0]);
						conv_row_res += ((int32_t)in_ft_roi[m][1]) * ((int32_t)kernal[m][1]);
						conv_row_res += ((int32_t)in_ft_roi[m][2]) * ((int32_t)kernal[m][2]);

						conv_row_res >>= (IN_FT_QUAZ_ACC - CONV_RES_EXT_FRAC_WIDTH);
						conv_row_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);

						conv_res += conv_row_res;
						conv_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);
					}
				}

				// ����λ��չ
				if(conv_res & (1 << (15 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH))){
					conv_res |= (0xFFFFFFFFFFFFFFFF << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH));
				}

				// ���Գ˼�
				int64_t linear_a_ext = linear_a;
				int64_t linear_b_ext = linear_b;

				conv_res = linear_a_ext * conv_res + (linear_b_ext << (IN_FT_QUAZ_ACC + CONV_RES_EXT_FRAC_WIDTH));
				conv_res >>= AB_QUAZ_ACC;
				conv_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);

				// ����λ��չ
				if(conv_res & (1 << (15 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH))){
					conv_res |= (0xFFFFFFFFFFFFFFFF << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH));
				}

				// Relu����
				if(conv_res < 0){
					conv_res *= ACT_RATE_C;
					conv_res >>= C_QUAZ_ACC;
					conv_res &= ((1 << (16 + CONV_RES_EXT_INT_WIDTH + CONV_RES_EXT_FRAC_WIDTH)) - 1);
				}

				// ����
				conv_res >>= CONV_RES_EXT_FRAC_WIDTH;
				conv_res &= ((1 << 16) - 1);

				golden_ref_buf[i * FT_MAP_W * FT_MAP_H + y * FT_MAP_W + x] = conv_res;
			}
		}
	}
}

/*************************
@check
@private
@brief  ��������
@param  none
@return �Ƿ�һ��
*************************/
int check_conv_res(void){
	uint8_t success = 1;

	for(int i = 0;i < FT_MAP_W * FT_MAP_H * KERNAL_N;i++){
		uint16_t res = out_ft_map_buf[i];
		uint16_t ref = golden_ref_buf[i];

		if(res != ref){
			success = 0;
		}
	}

	return success ? 0:-1;
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
