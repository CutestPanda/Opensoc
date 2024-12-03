#include "axi_generic_conv.h"
#include "axi_generic_conv_cfg.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��AXIͨ�þ��������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
        baseaddr AXIͨ�þ������������ַ
@return none
*************************/
void init_axi_generic_conv(AXIGenericConv* axi_conv, uint32_t baseaddr){
	axi_conv->hardware = (AXIGenericConvHw*)baseaddr;
}

/*************************
@cfg
@public
@brief  ����AXIͨ�þ��������������ʱ����
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
        cfg ����ʱ��������(�ṹ��ָ��)
@return none
*************************/
void axi_generic_conv_set_conv_params(AXIGenericConv* axi_conv, AXIGenericConvCfg* cfg){
	axi_conv->hardware->kernal_style =
		((cfg->kernal_type == TYPE_3x3) ? 0x00000001:0x00000000) |
		(cfg->en_right_padding ? 0x00000100:0x00000000) |
		(cfg->en_left_padding ? 0x00000200:0x00000000) |
		(cfg->en_bottom_padding ? 0x00000400:0x00000000) |
		(cfg->en_top_padding ? 0x00000800:0x00000000);

	axi_conv->hardware->feature_map_w_h =
		((uint32_t)(cfg->feature_map_w - 1)) |
		(((uint32_t)(cfg->feature_map_h - 1)) << 16);

	axi_conv->hardware->kernal_c_n =
		((uint32_t)(cfg->feature_map_chn_n - 1)) |
		(((uint32_t)(cfg->kernal_n - 1)) << 16);

	axi_conv->hardware->act_rate_c_0 = cfg->act_rate_c_0;
	axi_conv->hardware->act_rate_c_1 = cfg->act_rate_c_1;
}

/*************************
@ctrl
@public
@brief  ����AXIͨ�þ��������
		ʹ�ܾ������, ��λ���Բ���������, ��λ����ͨ·�ϵľ���˲�������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return none
*************************/
void axi_generic_conv_start(AXIGenericConv* axi_conv){
	axi_conv->hardware->flow_en = 0x00000001;
	axi_conv->hardware->ctrl_sts = 0x00000003;
}

/*************************
@ctrl
@public
@brief  ��������AXIͨ�þ��������
		ʹ�ܾ������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return none
*************************/
void axi_generic_conv_resume(AXIGenericConv* axi_conv){
	axi_conv->hardware->flow_en = 0x00000001;
}

/*************************
@ctrl
@public
@brief  ��ͣAXIͨ�þ��������
		���ܾ������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return none
*************************/
void axi_generic_conv_suspend(AXIGenericConv* axi_conv){
	axi_conv->hardware->flow_en = 0x00000000;
}

/*************************
@cfg
@public
@brief  ʹ��AXIͨ�þ�����������ж�
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
        itr_mask �ж���������(��ʹ������AXI_GENERIC_CONV_ITR_XXX)
@return none
*************************/
void axi_generic_conv_enable_itr(AXIGenericConv* axi_conv, uint32_t itr_mask){
	axi_conv->hardware->itr_en =
		0x00000001 |
		(itr_mask << 8);
}

/*************************
@cfg
@public
@brief  ����AXIͨ�þ�����������ж�
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
        itr_mask �ж���������(��ʹ������AXI_GENERIC_CONV_ITR_XXX)
@return none
*************************/
void axi_generic_conv_disable_itr(AXIGenericConv* axi_conv, uint32_t itr_mask){
	uint32_t itr_en_pre = axi_conv->hardware->itr_en & 0xFFFFFFFE;

	itr_en_pre &= (~(itr_mask << 8));

	axi_conv->hardware->itr_en =
		((itr_en_pre == 0x00000000) ? 0x00000000:0x00000001) |
		itr_en_pre;
}

/*************************
@cfg
@public
@brief  ����AXIͨ�þ����������д����������ж���ֵ
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
        wt_req_itr_th д����������ж���ֵ
@return none
*************************/
void axi_generic_conv_set_wt_req_itr_th(AXIGenericConv* axi_conv, uint32_t wt_req_itr_th){
	axi_conv->hardware->wt_req_itr_th = wt_req_itr_th;
}

/*************************
@sts
@public
@brief  ��ȡAXIͨ�þ�����������ж�״̬
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return �ж�״̬����(��ʹ������AXI_GENERIC_CONV_ITR_XXX)
*************************/
uint32_t axi_generic_conv_get_itr_sts(AXIGenericConv* axi_conv){
	return (axi_conv->hardware->itr_flag >> 8);
}

/*************************
@ctrl
@public
@brief  ���AXIͨ�þ�����������жϱ�־
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return none
*************************/
void axi_generic_conv_clear_itr_flag(AXIGenericConv* axi_conv){
	axi_conv->hardware->itr_flag = 0x00000000;
}

/*************************
@ctrl
@public
@brief  ��AXIͨ�þ���������ύ������������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
		rd_req_buf_baseaddr �����������ӻ������׵�ַ
		rd_req_n �����������Ӹ���
@return �Ƿ�ɹ�
*************************/
int axi_generic_conv_post_rd_req_dsc(AXIGenericConv* axi_conv, uint32_t rd_req_buf_baseaddr, uint32_t rd_req_n){
	if((rd_req_buf_baseaddr % RD_REQ_BUF_ALIGNMENT) || (rd_req_n > MAX_RD_REQ_N)){
		return -1;
	}

	if(axi_conv->hardware->ctrl_sts & 0x00010000){
		axi_conv->hardware->rd_req_buf_baseaddr = rd_req_buf_baseaddr;
		axi_conv->hardware->rd_req_n = rd_req_n - 1;
		axi_conv->hardware->ctrl_sts = 0x00000100;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@ctrl
@public
@brief  ��AXIͨ�þ���������ύд����������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
		wt_req_buf_baseaddr д���������ӻ������׵�ַ
		wt_req_n д���������Ӹ���
@return �Ƿ�ɹ�
*************************/
int axi_generic_conv_post_wt_req_dsc(AXIGenericConv* axi_conv, uint32_t wt_req_buf_baseaddr, uint32_t wt_req_n){
	if((wt_req_buf_baseaddr % WT_REQ_BUF_ALIGNMENT) || (wt_req_n > MAX_WT_REQ_N)){
		return -1;
	}

	if(axi_conv->hardware->ctrl_sts & 0x00020000){
		axi_conv->hardware->wt_req_buf_baseaddr = wt_req_buf_baseaddr;
		axi_conv->hardware->wt_req_n = wt_req_n - 1;
		axi_conv->hardware->ctrl_sts = 0x00000200;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@cfg
@public
@brief  ����AXIͨ�þ������������ɵ�д�������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
		wt_req_fns_n ����ɵ�д�������
@return none
*************************/
void axi_generic_conv_set_wt_req_fns_n(AXIGenericConv* axi_conv, uint32_t wt_req_fns_n){
	axi_conv->hardware->wt_req_fns_n = wt_req_fns_n;
}

/*************************
@sts
@public
@brief  �ж�AXIͨ�þ���������Ķ�����������DMA�Ƿ�æµ
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return �Ƿ�æµ
*************************/
uint8_t axi_generic_conv_is_rd_req_dsc_dma_busy(AXIGenericConv* axi_conv){
	return (axi_conv->hardware->ctrl_sts & 0x00010000) ? 0x00:0x01;
}

/*************************
@sts
@public
@brief  �ж�AXIͨ�þ����������д����������DMA�Ƿ�æµ
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return �Ƿ�æµ
*************************/
uint8_t axi_generic_conv_is_wt_req_dsc_dma_busy(AXIGenericConv* axi_conv){
	return (axi_conv->hardware->ctrl_sts & 0x00020000) ? 0x00:0x01;
}

/*************************
@sts
@public
@brief  ��ȡAXIͨ�þ������������ɵ�д�������
@param  axi_conv AXIͨ�þ��������(�ṹ��ָ��)
@return ����ɵ�д�������
*************************/
uint32_t axi_generic_conv_get_wt_req_fns_n(AXIGenericConv* axi_conv){
	return axi_conv->hardware->wt_req_fns_n;
}

/*************************
@logic
@public
@brief  ���ɶ�����������
@param  rd_req_dsc_buf_ptr �����������ӻ�����(ָ��)
        linear_a_buf_baseaddr ���Բ���A�������׵�ַ
        linear_b_buf_baseaddr ���Բ���B�������׵�ַ
        kernal_buf_baseaddr ����˻������׵�ַ
        in_ft_map_buf_baseaddr ��������ͼ�������׵�ַ
		kernal_n ����˸���
		prl_kernal_n �˲�����
		ft_map_chn_n ����ͼͨ����
		prl_chn_n ͨ��������
		in_ft_map_w ��������ͼ���
		in_ft_map_h ��������ͼ�߶�
		en_top_padding �Ƿ�ʹ�������
		en_bottom_padding �Ƿ�ʹ�������
		kernal_type ���������
@return ���������
*************************/
uint32_t axi_generic_conv_generate_rd_req_dsc(uint32_t* rd_req_dsc_buf_ptr,
	uint32_t linear_a_buf_baseaddr, uint32_t linear_b_buf_baseaddr, uint32_t kernal_buf_baseaddr, uint32_t in_ft_map_buf_baseaddr,
	uint32_t kernal_n, uint8_t prl_kernal_n,
	uint32_t ft_map_chn_n, uint8_t prl_chn_n,
	uint32_t in_ft_map_w, uint32_t in_ft_map_h,
	uint8_t en_top_padding, uint8_t en_bottom_padding,
	KernalType kernal_type){
	uint32_t rd_req_n = 0;

	// ���Բ���A
	rd_req_dsc_buf_ptr[rd_req_n * 2] = linear_a_buf_baseaddr;
	rd_req_dsc_buf_ptr[rd_req_n * 2 + 1] = 0x00000000 | 0x00000008 | ((kernal_n * 2) << 4);
	rd_req_n++;
	// ���Բ���B
	rd_req_dsc_buf_ptr[rd_req_n * 2] = linear_b_buf_baseaddr;
	rd_req_dsc_buf_ptr[rd_req_n * 2 + 1] = 0x00000000 | 0x0000000C | ((kernal_n * 2) << 4);
	rd_req_n++;

	int ft_map_repeat_n = kernal_n / prl_kernal_n + ((kernal_n % prl_kernal_n) ? 1:0);
	int in_ft_map_chn_n_to_fetch = (ft_map_chn_n / prl_chn_n + ((ft_map_chn_n % prl_chn_n) ? 1:0)) * prl_chn_n;

	for(int i = 0;i < ft_map_repeat_n;i++){
		// �����
		for(int j = 0;j < prl_kernal_n;j++){
			rd_req_dsc_buf_ptr[rd_req_n * 2] = kernal_buf_baseaddr + ((kernal_type == TYPE_3x3) ? 9:1) * ft_map_chn_n * (i * prl_kernal_n + j) * 2;
			rd_req_dsc_buf_ptr[rd_req_n * 2 + 1] = 0x00000001 | (((i * prl_kernal_n + j) >= kernal_n) ? 0x00000000:0x00000008) |
				((((kernal_type == TYPE_3x3) ? 9:1) * ft_map_chn_n * 2) << 4);
			rd_req_n++;
		}

		// ��������ͼ
		for(int j = 0;j < in_ft_map_h;j++){
			if(((j == 0) && (!en_top_padding) && (kernal_type == TYPE_3x3)) ||
				((j == (in_ft_map_h - 1)) && (!en_bottom_padding) && (kernal_type == TYPE_3x3))){
				continue;
			}

			for(int k = 0;k < in_ft_map_chn_n_to_fetch;k++){
				// ��#0
				rd_req_dsc_buf_ptr[rd_req_n * 2] = in_ft_map_buf_baseaddr + in_ft_map_w * in_ft_map_h * k * 2 + in_ft_map_w * (j - 1) * 2;
				rd_req_dsc_buf_ptr[rd_req_n * 2 + 1] = 0x00000002 | (((j == 0) || (k >= ft_map_chn_n)) ? 0x00000000:0x00000008) |
					((in_ft_map_w * 2) << 4);
				rd_req_n++;

				// ��#1
				rd_req_dsc_buf_ptr[rd_req_n * 2] = in_ft_map_buf_baseaddr + in_ft_map_w * in_ft_map_h * k * 2 + in_ft_map_w * j * 2;
				rd_req_dsc_buf_ptr[rd_req_n * 2 + 1] = 0x00000002 | ((k >= ft_map_chn_n) ? 0x00000000:0x00000008) |
					((in_ft_map_w * 2) << 4);
				rd_req_n++;

				// ��#2
				rd_req_dsc_buf_ptr[rd_req_n * 2] = in_ft_map_buf_baseaddr + in_ft_map_w * in_ft_map_h * k * 2 + in_ft_map_w * (j + 1) * 2;
				rd_req_dsc_buf_ptr[rd_req_n * 2 + 1] = 0x00000002 | (((j == (in_ft_map_h - 1)) || (k >= ft_map_chn_n)) ? 0x00000000:0x00000008) |
					0x00000004 |
					((in_ft_map_w * 2) << 4);
				rd_req_n++;
			}
		}
	}

	return rd_req_n;
}

/*************************
@logic
@public
@brief  ����д����������
@param  wt_req_dsc_buf_ptr д���������ӻ�����(ָ��)
        out_ft_map_buf_baseaddr �������ͼ�������׵�ַ
		kernal_n ����˸���
		prl_kernal_n �˲�����
		out_ft_map_w �������ͼ���
		out_ft_map_h �������ͼ�߶�
@return д�������
*************************/
uint32_t axi_generic_conv_generate_wt_req_dsc(
	uint32_t* wt_req_dsc_buf_ptr,
	uint32_t out_ft_map_buf_baseaddr,
	uint32_t kernal_n, uint8_t prl_kernal_n,
	uint32_t out_ft_map_w, uint32_t out_ft_map_h){
	uint32_t wt_req_n = 0;

	int ft_map_repeat_n = kernal_n / prl_kernal_n + ((kernal_n % prl_kernal_n) ? 1:0);

	for(int i = 0;i < ft_map_repeat_n;i++){
		for(int k = 0;k < out_ft_map_h;k++){
			for(int j = 0;j < prl_kernal_n;j++){
				if((i * prl_kernal_n + j) >= kernal_n){
					break;
				}else{
					wt_req_dsc_buf_ptr[wt_req_n * 2] = out_ft_map_buf_baseaddr + out_ft_map_w * out_ft_map_h * (i * prl_kernal_n + j) * 2 +
						k * out_ft_map_w * 2;
					wt_req_dsc_buf_ptr[wt_req_n * 2 + 1] = out_ft_map_w * 2;
					wt_req_n++;
				}
			}
		}
	}

	return wt_req_n;
}
