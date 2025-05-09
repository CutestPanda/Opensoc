/************************************************************************************************************************
双线性插值处理单元驱动(接口头文件)
@brief  双线性插值处理单元驱动
@date   2025/03/03
@author 陈家耀
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __BILINEAR_IMRESIZE_H
#define __BILINEAR_IMRESIZE_H

#define BILINEAR_IMRESIZE_SCALE_QUAZ_N 10 // 插值系数量化精度

typedef uint32_t BlnImrszUnit;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

BlnImrszUnit* bilinear_imresize_init(uint32_t base_addr); // 初始化双线性插值处理单元

void bilinear_imresize_poll(BlnImrszUnit* unit, uint32_t res_baseaddr, uint32_t src_baseaddr, 
	uint32_t dst_w, uint32_t dst_h, uint32_t res_stride, uint32_t src_w, uint32_t src_h, 
	uint32_t sbuf_stride, uint32_t chn_n); // 以轮询方式进行双线性插值缩放
