#include "axi_max_pool.h"
#include "axi_max_pool_cfg.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��AXI���ػ���Ԫ
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
        baseaddr AXI���ػ���Ԫ����ַ
@return none
*************************/
void init_axi_max_pool(AXIMaxPool* axi_max_pool, uint32_t baseaddr){
	axi_max_pool->hardware = (AXIMaxPoolHw*)baseaddr;
}

/*************************
@cfg
@public
@brief  ����AXI���ػ���Ԫ������ʱ����
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
        cfg ����ʱ��������(�ṹ��ָ��)
@return none
*************************/
void axi_max_pool_set_conv_params(AXIMaxPool* axi_max_pool, AXIMaxPoolCfg* cfg){
	axi_max_pool->hardware->step_padding =
		((cfg->step_type == STEP_1) ? 0x00000000:0x00000001) |
		(cfg->en_right_padding ? 0x00000100:0x00000000) |
		(cfg->en_left_padding ? 0x00000200:0x00000000) |
		(cfg->en_bottom_padding ? 0x00000400:0x00000000) |
		(cfg->en_top_padding ? 0x00000800:0x00000000);
	axi_max_pool->hardware->feature_map_c_w =
		((uint32_t)(cfg->feature_map_chn_n - 1)) |
		(((uint32_t)(cfg->feature_map_w - 1)) << 16);
	axi_max_pool->hardware->feature_map_h =
		(uint32_t)(cfg->feature_map_h - 1);
}

/*************************
@ctrl
@public
@brief  ����AXI���ػ���Ԫ�ļ���
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
@return �Ƿ�ɹ�
*************************/
int axi_max_pool_start_cal(AXIMaxPool* axi_max_pool){
	if(axi_max_pool->hardware->ctrl_sts & 0x00000400){
		axi_max_pool->hardware->ctrl_sts = 0x00000004;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@ctrl
@public
@brief  ����AXI���ػ���Ԫ��DMA��ͨ��
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
		ft_map_buf_baseaddr ����ͼ����������ַ
		ft_map_buf_len ����ͼ����������(���ֽڼ�)
@return �Ƿ�ɹ�
*************************/
int axi_max_pool_start_dma_rchn(AXIMaxPool* axi_max_pool, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len){
	if(ft_map_buf_baseaddr % FT_MAP_BUF_ALIGNMENT){
		return -1;
	}

	if(axi_max_pool->hardware->ctrl_sts & 0x00000100){
		axi_max_pool->hardware->in_ft_map_buf_baseaddr = ft_map_buf_baseaddr;
		axi_max_pool->hardware->in_ft_map_buf_len = ft_map_buf_len - 1;
		axi_max_pool->hardware->ctrl_sts = 0x00000001;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@ctrl
@public
@brief  ����AXI���ػ���Ԫ��DMAдͨ��
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
		ft_map_buf_baseaddr ����ͼ����������ַ
		ft_map_buf_len ����ͼ����������(���ֽڼ�)
@return �Ƿ�ɹ�
*************************/
int axi_max_pool_start_dma_wchn(AXIMaxPool* axi_max_pool, uint32_t ft_map_buf_baseaddr, uint32_t ft_map_buf_len){
	if(ft_map_buf_baseaddr % FT_MAP_BUF_ALIGNMENT){
		return -1;
	}

	if(axi_max_pool->hardware->ctrl_sts & 0x00000200){
		axi_max_pool->hardware->out_ft_map_buf_baseaddr = ft_map_buf_baseaddr;
		axi_max_pool->hardware->out_ft_map_buf_len = ft_map_buf_len - 1;
		axi_max_pool->hardware->ctrl_sts = 0x00000002;

		return 0;
	}else{
		return -1;
	}
}

/*************************
@cfg
@public
@brief  ʹ��AXI���ػ���Ԫ���ж�
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
        itr_mask �ж���������(��ʹ������AXI_MAX_POOL_ITR_XXX)
@return none
*************************/
void axi_max_pool_enable_itr(AXIMaxPool* axi_max_pool, uint32_t itr_mask){
	axi_max_pool->hardware->itr_en =
		0x00000001 |
		(itr_mask << 8);
}

/*************************
@cfg
@public
@brief  ����AXI���ػ���Ԫ���ж�
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
        itr_mask �ж���������(��ʹ������AXI_MAX_POOL_ITR_XXX)
@return none
*************************/
void axi_max_pool_disable_itr(AXIMaxPool* axi_max_pool, uint32_t itr_mask){
	uint32_t itr_en_pre = axi_max_pool->hardware->itr_en & 0xFFFFFFFE;

	itr_en_pre &= (~(itr_mask << 8));

	axi_max_pool->hardware->itr_en =
		((itr_en_pre == 0x00000000) ? 0x00000000:0x00000001) |
		itr_en_pre;
}

/*************************
@sts
@public
@brief  ��ȡAXI���ػ���Ԫ���ж�״̬
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
@return �ж�״̬����(��ʹ������AXI_MAX_POOL_ITR_XXX)
*************************/
uint32_t axi_max_pool_get_itr_sts(AXIMaxPool* axi_max_pool){
	return (axi_max_pool->hardware->itr_flag >> 8);
}

/*************************
@ctrl
@public
@brief  ���AXI���ػ���Ԫ���жϱ�־
@param  axi_max_pool AXI���ػ���Ԫ(�ṹ��ָ��)
@return none
*************************/
void axi_max_pool_clear_itr_flag(AXIMaxPool* axi_max_pool){
	axi_max_pool->hardware->itr_flag = 0x00000000;
}
