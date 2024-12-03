#include "axi_max_pool.h"
#include "axi_max_pool_cfg.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化AXI最大池化单元
@param  axi_max_pool AXI最大池化单元(结构体指针)
        baseaddr AXI最大池化单元基地址
@return none
*************************/
void init_axi_max_pool(AXIMaxPool* axi_max_pool, uint32_t baseaddr){
	axi_max_pool->hardware = (AXIMaxPoolHw*)baseaddr;
}

/*************************
@cfg
@public
@brief  配置AXI最大池化单元的运行时参数
@param  axi_max_pool AXI最大池化单元(结构体指针)
        cfg 运行时参数配置(结构体指针)
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
@brief  启动AXI最大池化单元的计算
@param  axi_max_pool AXI最大池化单元(结构体指针)
@return 是否成功
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
@brief  启动AXI最大池化单元的DMA读通道
@param  axi_max_pool AXI最大池化单元(结构体指针)
		ft_map_buf_baseaddr 特征图缓存区基地址
		ft_map_buf_len 特征图缓存区长度(以字节计)
@return 是否成功
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
@brief  启动AXI最大池化单元的DMA写通道
@param  axi_max_pool AXI最大池化单元(结构体指针)
		ft_map_buf_baseaddr 特征图缓存区基地址
		ft_map_buf_len 特征图缓存区长度(以字节计)
@return 是否成功
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
@brief  使能AXI最大池化单元的中断
@param  axi_max_pool AXI最大池化单元(结构体指针)
        itr_mask 中断类型掩码(请使用掩码AXI_MAX_POOL_ITR_XXX)
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
@brief  除能AXI最大池化单元的中断
@param  axi_max_pool AXI最大池化单元(结构体指针)
        itr_mask 中断类型掩码(请使用掩码AXI_MAX_POOL_ITR_XXX)
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
@brief  获取AXI最大池化单元的中断状态
@param  axi_max_pool AXI最大池化单元(结构体指针)
@return 中断状态向量(请使用掩码AXI_MAX_POOL_ITR_XXX)
*************************/
uint32_t axi_max_pool_get_itr_sts(AXIMaxPool* axi_max_pool){
	return (axi_max_pool->hardware->itr_flag >> 8);
}

/*************************
@ctrl
@public
@brief  清除AXI最大池化单元的中断标志
@param  axi_max_pool AXI最大池化单元(结构体指针)
@return none
*************************/
void axi_max_pool_clear_itr_flag(AXIMaxPool* axi_max_pool){
	axi_max_pool->hardware->itr_flag = 0x00000000;
}
