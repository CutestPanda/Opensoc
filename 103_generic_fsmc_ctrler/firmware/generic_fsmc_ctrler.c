/************************************************************************************************************************
ͨ��FSMC����������(��Դ�ļ�)
@brief  ͨ��FSMC����������
@date   2024/08/29
@author �¼�ҫ
@eidt   2024/08/29 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "generic_fsmc_ctrler.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��FSMC������
@param  base_addr FSMC�������ַ
			  fsmc FSMC����(�ṹ��ָ��)
@return none
*************************/
void init_fsmc(uint32_t base_addr, Fsmc* fsmc){
	fsmc->base_addr_regs = base_addr;
	fsmc->base_addr_mem = base_addr + 0x00001000;
}

/*************************
@cfg
@public
@brief  ����FSMC������ʱ�����
@param  fsmc FSMC����(�ṹ��ָ��)
		    addr_set  ��ַ���������� - 1
			  data_set  ���ݽ��������� - 1
	      data_hold ���ݱ��������� - 1
@return none
*************************/
void fsmc_cfg_rt_pars(Fsmc* fsmc, uint8_t addr_set, uint8_t data_set, uint8_t data_hold){
	uint16_t* ptr = (uint16_t*)fsmc->base_addr_regs;
	
	ptr[0] = ((uint16_t)addr_set) | (((uint16_t)data_set) << 8);
	ptr[1] = (uint16_t)data_hold;
}

/*************************
@io
@public
@brief  FSMC��������16λ����λ��д����
@param  fsmc FSMC����(�ṹ��ָ��)
		    ofs FSMC�洢ƫ�Ƶ�ַ
        data ��д�İ�������
@return none
*************************/
void fsmc_write_16(Fsmc* fsmc, uint32_t ofs, uint16_t data){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + ofs);
	
	*ptr = data;
}

/*************************
@io
@public
@brief  FSMC��������8λ����λ��д����
@param  fsmc FSMC����(�ṹ��ָ��)
		    ofs FSMC�洢ƫ�Ƶ�ַ
        data ��д���ֽ�����
@return none
*************************/
void fsmc_write_8(Fsmc* fsmc, uint32_t ofs, uint8_t data){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + (ofs << 1));
	
	*ptr = (uint16_t)data;
}

/*************************
@io
@public
@brief  FSMC��������16λ����λ�������
@param  fsmc FSMC����(�ṹ��ָ��)
		    ofs FSMC�洢ƫ�Ƶ�ַ
@return ��ȡ���İ�������
*************************/
uint16_t fsmc_read_16(Fsmc* fsmc, uint32_t ofs){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + ofs);
	
	return *ptr;
}

/*************************
@io
@public
@brief  FSMC��������8λ����λ�������
@param  fsmc FSMC����(�ṹ��ָ��)
		    ofs FSMC�洢ƫ�Ƶ�ַ
@return ��ȡ�����ֽ�����
*************************/
uint8_t fsmc_read_8(Fsmc* fsmc, uint32_t ofs){
	uint16_t* ptr = (uint16_t*)(fsmc->base_addr_mem + (ofs << 1));
	
	return (uint8_t)(*ptr & 0x00FF);
}
