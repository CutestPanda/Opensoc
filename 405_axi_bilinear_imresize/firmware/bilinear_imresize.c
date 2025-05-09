/************************************************************************************************************************
˫���Բ�ֵ����Ԫ����(��Դ�ļ�)
@brief  ˫���Բ�ֵ����Ԫ����
@date   2025/03/03
@author �¼�ҫ
@eidt   2025/03/03 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "bilinear_imresize.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��˫���Բ�ֵ����Ԫ
@param  base_addr ˫���Բ�ֵ����Ԫ����ַ
@return ˫���Բ�ֵ����Ԫ(���)
*************************/
BlnImrszUnit* bilinear_imresize_init(uint32_t base_addr){
	return (BlnImrszUnit*)base_addr;
}

/*************************
@cal
@public
@brief  ����ѯ��ʽ����˫���Բ�ֵ����
@param  unit ˫���Բ�ֵ����Ԫ(���)
        res_baseaddr ����������׵�ַ
		src_baseaddr ԴͼƬ����ַ
		dst_w Ŀ��ͼƬ���
		dst_h Ŀ��ͼƬ�߶�
		res_stride ����������п��
		src_w ԴͼƬ���
		src_h ԴͼƬ�߶�
		sbuf_stride Դ�������п��
		chn_n ͼƬͨ����
@return none
*************************/
void bilinear_imresize_poll(BlnImrszUnit* unit, uint32_t res_baseaddr, uint32_t src_baseaddr, 
	uint32_t dst_w, uint32_t dst_h, uint32_t res_stride, uint32_t src_w, uint32_t src_h, 
	uint32_t sbuf_stride, uint32_t chn_n){
	float resize_scale_x = ((float)src_w) / dst_w * (1 << BILINEAR_IMRESIZE_SCALE_QUAZ_N);
	float resize_scale_y = ((float)src_h) / dst_h * (1 << BILINEAR_IMRESIZE_SCALE_QUAZ_N);
	uint32_t resize_scale_x_fixed = (uint32_t)resize_scale_x;
	uint32_t resize_scale_y_fixed = (uint32_t)resize_scale_y;
	
	unit[3] = res_baseaddr; // �������������ַ
	unit[4] = src_baseaddr; // ԴͼƬ����ַ
	unit[5] = res_stride | ((dst_w * chn_n) << 16); // ����������п��, Ŀ��ͼƬ�п��
	unit[6] = (src_w * chn_n) | (resize_scale_y_fixed << 16); // ԴͼƬ�п��, ��ֱ���ű���
	unit[7] = (resize_scale_x_fixed) | ((dst_h - 1) << 16); // ˮƽ���ű���, Ŀ��ͼƬ�߶� - 1
	unit[8] = (dst_w - 1) | ((src_h - 1) << 16); // Ŀ��ͼƬ��� - 1, ԴͼƬ�߶� - 1
	unit[9] = (src_w - 1) | (sbuf_stride << 16); // ԴͼƬ��� - 1, Դ�������п��
	unit[10] = chn_n - 1; // ͼƬͨ���� - 1
	
	unit[0] = 0x04; // ������������
	
	while(!unit[2]); // �ȴ��������
	
	unit[2] = 0xFFFFFFFF; // ����жϵȴ���־����
}
