/************************************************************************************************************************
双线性插值处理单元驱动(主源文件)
@brief  双线性插值处理单元驱动
@date   2025/03/03
@author 陈家耀
@eidt   2025/03/03 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "bilinear_imresize.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化双线性插值处理单元
@param  base_addr 双线性插值处理单元基地址
@return 双线性插值处理单元(句柄)
*************************/
BlnImrszUnit* bilinear_imresize_init(uint32_t base_addr){
	return (BlnImrszUnit*)base_addr;
}

/*************************
@cal
@public
@brief  以轮询方式进行双线性插值缩放
@param  unit 双线性插值处理单元(句柄)
        res_baseaddr 结果缓存区首地址
		src_baseaddr 源图片基地址
		dst_w 目标图片宽度
		dst_h 目标图片高度
		res_stride 结果缓存区行跨度
		src_w 源图片宽度
		src_h 源图片高度
		sbuf_stride 源缓存区行跨度
		chn_n 图片通道数
@return none
*************************/
void bilinear_imresize_poll(BlnImrszUnit* unit, uint32_t res_baseaddr, uint32_t src_baseaddr, 
	uint32_t dst_w, uint32_t dst_h, uint32_t res_stride, uint32_t src_w, uint32_t src_h, 
	uint32_t sbuf_stride, uint32_t chn_n){
	float resize_scale_x = ((float)src_w) / dst_w * (1 << BILINEAR_IMRESIZE_SCALE_QUAZ_N);
	float resize_scale_y = ((float)src_h) / dst_h * (1 << BILINEAR_IMRESIZE_SCALE_QUAZ_N);
	uint32_t resize_scale_x_fixed = (uint32_t)resize_scale_x;
	uint32_t resize_scale_y_fixed = (uint32_t)resize_scale_y;
	
	unit[3] = res_baseaddr; // 结果缓存区基地址
	unit[4] = src_baseaddr; // 源图片基地址
	unit[5] = res_stride | ((dst_w * chn_n) << 16); // 结果缓存区行跨度, 目标图片行跨度
	unit[6] = (src_w * chn_n) | (resize_scale_y_fixed << 16); // 源图片行跨度, 竖直缩放比例
	unit[7] = (resize_scale_x_fixed) | ((dst_h - 1) << 16); // 水平缩放比例, 目标图片高度 - 1
	unit[8] = (dst_w - 1) | ((src_h - 1) << 16); // 目标图片宽度 - 1, 源图片高度 - 1
	unit[9] = (src_w - 1) | (sbuf_stride << 16); // 源图片宽度 - 1, 源缓存区行跨度
	unit[10] = chn_n - 1; // 图片通道数 - 1
	
	unit[0] = 0x04; // 发送缩放请求
	
	while(!unit[2]); // 等待缩放完成
	
	unit[2] = 0xFFFFFFFF; // 清除中断等待标志向量
}
