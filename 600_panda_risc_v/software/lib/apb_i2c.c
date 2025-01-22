/************************************************************************************************************************
APB-I2C����(��Դ�ļ�)
@brief  APB-I2C����
@date   2024/08/28
@author �¼�ҫ
@eidt   2024/08/28 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../include/apb_i2c.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int apb_i2c_tx(ApbI2C* i2c, uint8_t byte, uint8_t is_last); // ����FIFOд��һ���ֽ�����

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  ��ʼ��APB-I2C
@param  i2c APB-I2C(�ṹ��ָ��)
        base_addr APB-I2C�������ַ
@return none
*************************/
void apb_i2c_init(ApbI2C* i2c, uint32_t base_addr){
	i2c->hardware = (ApbI2CHd*)base_addr;
}

/*************************
@io
@public
@brief  APB-I2C����д����
@param  i2c APB-I2C(�ṹ��ָ��)
        slave_addr �ӻ���ַ
        data �������ֽڻ�����(�׵�ַ)
        len �������ֽ���
@attention ����fifoд���ݿ��ܻ��������
@return �Ƿ�ɹ�
*************************/
int apb_i2c_start_wt_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t* data, uint8_t len){
	if(len > 15){ // ÿ��I2C���ݰ����ܳ���15�ֽ�
		return -1;
	}else{
		while(apb_i2c_tx(i2c, slave_addr, 0));
		
		for(uint8_t i = 0;i < len;i++){
			while(apb_i2c_tx(i2c, data[i], i == (len - 1)));
		}
		
		return 0;
	}
}

/*************************
@io
@public
@brief  APB-I2C����������
@param  i2c APB-I2C(�ṹ��ָ��)
        slave_addr �ӻ���ַ
        len �������ֽ���
@attention ����fifoд���ݿ��ܻ��������
@return �Ƿ�ɹ�
*************************/
int apb_i2c_start_rd_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t len){
	if(len > 15){ // ÿ��I2C���ݰ����ܳ���15�ֽ�
		return -1;
	}else{
		while(apb_i2c_tx(i2c, slave_addr | 0x01, 0));
		while(apb_i2c_tx(i2c, len, 1));
		
		return 0;
	}
}

/*************************
@io
@public
@brief  �ӽ���FIFO��ȡһ���ֽ�����
@param  i2c APB-I2C(�ṹ��ָ��)
        byte �����ֽڻ�����(�׵�ַ)
@return �Ƿ�ɹ�
*************************/
int apb_i2c_get_rx_byte(ApbI2C* i2c, uint8_t* byte){
	volatile uint32_t* LocalAddr = &(i2c->hardware->fifo_cs);
	uint32_t fifo_cs = *LocalAddr;
	
	if(fifo_cs & 0x00010000){
		return -1;
	}else{
		*LocalAddr = 0x00020000;
		
		*byte = (uint8_t)((*LocalAddr) >> 18);
		
		return 0;
	}
}

/*************************
@cfg
@public
@brief  APB-I2Cʹ���ж�
@param  i2c APB-I2C(�ṹ��ָ��)
        itr_en �ж�ʹ������
@return none
*************************/
void apb_i2c_enable_itr(ApbI2C* i2c, uint8_t itr_en){
	i2c->hardware->itr_status_en = 0x00000001 | (((uint32_t)itr_en) << 8);
}

/*************************
@cfg
@public
@brief  APB-I2C�����ж�
@param  i2c APB-I2C(�ṹ��ָ��)
@return none
*************************/
void apb_i2c_disable_itr(ApbI2C* i2c){
	i2c->hardware->itr_status_en = 0x00000000;
}

/*************************
@cfg
@public
@brief  APB-I2C��������ʱ����
@param  i2c APB-I2C(�ṹ��ָ��)
			  tx_bytes_n_th I2C�����ж��ֽ�����ֵ
				rx_bytes_n_th I2C�����ж��ֽ�����ֵ
				scl_div_n I2Cʱ�ӷ�Ƶϵ��
@return none
*************************/
void apb_i2c_config_params(ApbI2C* i2c, uint8_t tx_bytes_n_th, uint8_t rx_bytes_n_th, uint8_t scl_div_n){
	i2c->hardware->itr_th = ((uint32_t)tx_bytes_n_th) | (((uint32_t)rx_bytes_n_th) << 8)
		 | (((uint32_t)scl_div_n) << 16);
}

/*************************
@sts
@public
@brief  APB-I2C��ȡ�ж�״̬
@param  i2c APB-I2C(�ṹ��ָ��)
			  tx_bytes_n I2C�����ֽ���(ָ��)
				rx_bytes_n I2C�����ֽ���(ָ��)
@return �ж�״̬
*************************/
uint8_t apb_i2c_get_itr_status(ApbI2C* i2c, uint16_t* tx_bytes_n, uint16_t* rx_bytes_n){
	uint8_t itr_status = ((uint8_t)(i2c->hardware->itr_flag_status >> 1)) & 0x0000000F;
	
	uint32_t rx_tx_bytes_n = (i2c->hardware->itr_flag_status >> 8);
	
	*tx_bytes_n = (uint16_t)(rx_tx_bytes_n & 0x00000FFF);
	*rx_bytes_n = (uint16_t)(rx_tx_bytes_n >> 12);
	
	return itr_status;
}

/*************************
@sts
@public
@brief  APB-I2C����жϱ�־
@param  i2c APB-I2C(�ṹ��ָ��)
@return none
*************************/
void apb_i2c_clear_itr_flag(ApbI2C* i2c){
	i2c->hardware->itr_flag_status = 0x00000000;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@io
@private
@brief  ����FIFOд��һ���ֽ�����
@param  i2c APB-I2C(�ṹ��ָ��)
        byte ��д����ֽ�����
			  is_last ������lastָʾ
@return �Ƿ�ɹ�
*************************/
static int apb_i2c_tx(ApbI2C* i2c, uint8_t byte, uint8_t is_last){
	uint32_t fifo_cs = i2c->hardware->fifo_cs;
	
	if(fifo_cs & 0x00000001){
		return -1;
	}else{
		i2c->hardware->fifo_cs = 0x00000002 | (((uint32_t)byte) << 2) | (((uint32_t)is_last) << 10);
		
		return 0;
	}
}
