/************************************************************************************************************************
APB-I2Cʾ������
@brief  ����APB-I2Cʵ��EEPROM��д
@attention �����Ӳ��ƽ̨�������ӳ�(delay)��ص�API
@date   2024/08/28
@author �¼�ҫ
@eidt   2024/08/28 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../apb_i2c.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_I2C_BASEADDR 0x40000000 // APB-I2C�������ַ

#define EEPROM_I2C_ADDR 0xA0 // EEPROM I2C�ӻ���ַ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbI2C i2c; // APB-I2C����ṹ��

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static uint8_t read_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr); // ��EEPROM
static void write_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr, uint8_t data); // дEEPROM

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@io
@public
@brief  ��EEPROM
@param  i2c APB-I2C(�ṹ��ָ��)
        slave_addr I2C�ӻ���ַ
				mem_addr ��ȡ�ĵ�ַ
@return ��ȡ�����ֽ�����
*************************/
static uint8_t read_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr){
	uint8_t recv_buf;
	
	uint8_t send_buf[2] = {(uint8_t)(mem_addr >> 8), (uint8_t)(mem_addr & 0x00FF)};
	
	apb_i2c_start_wt_trans(i2c, slave_addr, send_buf, 2); // ����д����
	apb_i2c_start_rd_trans(i2c, slave_addr, 1); // ����������
	
	while(!apb_i2c_get_rx_byte(i2c, &recv_buf)); // ��ȡ1���ֽ�
	
	return recv_buf;
}

/*************************
@io
@public
@brief  дEEPROM
@param  i2c APB-I2C(�ṹ��ָ��)
        slave_addr I2C�ӻ���ַ
				mem_addr д��ĵ�ַ
			  data ��д����ֽ�����
@return none
*************************/
static void write_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr, uint8_t data){
	uint8_t send_buf[3] = {(uint8_t)(mem_addr >> 8), (uint8_t)(mem_addr & 0x00FF), data};
	
	apb_i2c_start_wt_trans(i2c, slave_addr, send_buf, 3); // ����д����
	
	delay_ms(10); // ��ʱ0.01s
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_i2c_eeprom_example(void){
	// ��ʼ��APB-I2C
	apb_i2c_init(&i2c, APB_I2C_BASEADDR);
	
	// ��������ʱ����
	// I2Cʱ�ӷ�Ƶϵ�� = 7
	apb_i2c_config_params(&i2c, 1, 1, 7);
	
	// ���ַ0x00д���ֽ�0x0A
	write_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x00, 0x0A);
	
	// ���ַ0x01д���ֽ�0xFE
	write_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x01, 0xFE);
	
	// ��ȡ��ַ0x00��0x01
	uint8_t rdata[2];
	
	rdata[0] = read_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x00);
	rdata[1] = read_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x01);
	
	if((rdata[0] == 0x0A) && (rdata[1] == 0xFE)){
		// ��д��֤�ɹ�
		// ...
	}else{
		// ��д��֤ʧ��
		// ...
	}
	
	while(1);
}
