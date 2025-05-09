/************************************************************************************************************************
˫���Բ�ֵ����Ԫ����(�ӿ�ͷ�ļ�)
@brief  ˫���Բ�ֵ����Ԫ����
@date   2025/03/03
@author �¼�ҫ
************************************************************************************************************************/

#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __BILINEAR_IMRESIZE_H
#define __BILINEAR_IMRESIZE_H

#define BILINEAR_IMRESIZE_SCALE_QUAZ_N 10 // ��ֵϵ����������

typedef uint32_t BlnImrszUnit;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

BlnImrszUnit* bilinear_imresize_init(uint32_t base_addr); // ��ʼ��˫���Բ�ֵ����Ԫ

void bilinear_imresize_poll(BlnImrszUnit* unit, uint32_t res_baseaddr, uint32_t src_baseaddr, 
	uint32_t dst_w, uint32_t dst_h, uint32_t res_stride, uint32_t src_w, uint32_t src_h, 
	uint32_t sbuf_stride, uint32_t chn_n); // ����ѯ��ʽ����˫���Բ�ֵ����
