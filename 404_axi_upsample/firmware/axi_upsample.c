#include "axi_upsample.h"
#include "axi_upsample_cfg.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��AXI�ϲ�����Ԫ
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
        baseaddr AXI�ϲ�����Ԫ����ַ
@return none
*************************/
void init_axi_upsample(AXIUpsample* axi_upsample, uint32_t baseaddr){
	axi_upsample->hardware = (AXIUpsampleHw*)baseaddr;
}

/*************************
@cfg
@public
@brief  ����AXI�ϲ�����Ԫ������ʱ����
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
        cfg ����ʱ��������(�ṹ��ָ��)
@return none
*************************/
void axi_upsample_set_conv_params(AXIUpsample* axi_upsample, AXIUpsampleCfg* cfg){
	axi_upsample->hardware->feature_map_c_w =
		((uint32_t)(cfg->feature_map_chn_n - 1)) |
		(((uint32_t)(cfg->feature_map_w - 1)) << 16);
	axi_upsample->hardware->feature_map_h =
		(uint32_t)(cfg->feature_map_h - 1);
}

/*************************
@ctrl
@public
@brief  ����AXI�ϲ�����Ԫ��DMA��ͨ��
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
		ft_map_buf_baseaddr ����ͼ����������ַ
		ft_map_buf_len ����ͼ����������(���ֽڼ�)
@return �Ƿ�ɹ�
*************************/
int axi_upsample_start_dma_rchn(AXIUpsample* axi_upsample, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len){
	if(ft_map_buf_baseaddr % FT_MAP_BUF_ALIGNMENT){
		return -1;
	}

	if(axi_upsample->hardware->ctrl_sts & 0x00000100){
		axi_upsample->hardware->in_ft_map_buf_baseaddr = ft_map_buf_baseaddr;
		axi_upsample->hardware->in_ft_map_buf_len = ft_map_buf_len - 1;
		axi_upsample->hardware->ctrl_sts = 0x00000001;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@ctrl
@public
@brief  ����AXI�ϲ�����Ԫ��DMAдͨ��
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
		ft_map_buf_baseaddr ����ͼ����������ַ
		ft_map_buf_len ����ͼ����������(���ֽڼ�)
@return �Ƿ�ɹ�
*************************/
int axi_upsample_start_dma_wchn(AXIUpsample* axi_upsample, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len){
	if(ft_map_buf_baseaddr % FT_MAP_BUF_ALIGNMENT){
		return -1;
	}

	if(axi_upsample->hardware->ctrl_sts & 0x00000200){
		axi_upsample->hardware->out_ft_map_buf_baseaddr = ft_map_buf_baseaddr;
		axi_upsample->hardware->out_ft_map_buf_len = ft_map_buf_len - 1;
		axi_upsample->hardware->ctrl_sts = 0x00000002;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@cfg
@public
@brief  ʹ��AXI�ϲ�����Ԫ���ж�
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
        itr_mask �ж���������(��ʹ������AXI_UPSAMPLE_ITR_XXX)
@return none
*************************/
void axi_upsample_enable_itr(AXIUpsample* axi_upsample, uint32_t itr_mask){
	axi_upsample->hardware->itr_en =
		0x00000001 |
		(itr_mask << 8);
}

/*************************
@cfg
@public
@brief  ����AXI�ϲ�����Ԫ���ж�
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
        itr_mask �ж���������(��ʹ������AXI_UPSAMPLE_ITR_XXX)
@return none
*************************/
void axi_upsample_disable_itr(AXIUpsample* axi_upsample, uint32_t itr_mask){
	uint32_t itr_en_pre = axi_upsample->hardware->itr_en & 0xFFFFFFFE;

	itr_en_pre &= (~(itr_mask << 8));

	axi_upsample->hardware->itr_en =
		((itr_en_pre == 0x00000000) ? 0x00000000:0x00000001) |
		itr_en_pre;
}

/*************************
@sts
@public
@brief  ��ȡAXI�ϲ�����Ԫ���ж�״̬
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
@return �ж�״̬����(��ʹ������AXI_UPSAMPLE_ITR_XXX)
*************************/
uint32_t axi_upsample_get_itr_sts(AXIUpsample* axi_upsample){
	return (axi_upsample->hardware->itr_flag >> 8);
}

/*************************
@ctrl
@public
@brief  ���AXI�ϲ�����Ԫ���жϱ�־
@param  axi_upsample AXI�ϲ�����Ԫ(�ṹ��ָ��)
@return none
*************************/
void axi_upsample_clear_itr_flag(AXIUpsample* axi_upsample){
	axi_upsample->hardware->itr_flag = 0x00000000;
}
