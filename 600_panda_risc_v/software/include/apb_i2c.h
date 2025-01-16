#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// �ж���������
#define I2C_TX_BYTES_N_ITR_MASK 0x01 // I2C����ָ���ֽ����жϱ�־
#define I2C_SLAVE_RESP_ERR_ITR_MASK 0x02 // I2C�ӻ���Ӧ�����жϱ�־
#define I2C_RX_BYTES_N_ITR_MASK 0x04 // I2C����ָ���ֽ����жϱ�־
#define I2C_RX_OVF_ITR_MASK 0x08 // I2C��������жϱ�־

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_I2C_H
#define __APB_I2C_H

typedef struct{
	uint32_t fifo_cs; // �շ�fifo����
	uint32_t itr_status_en; // �ж�ʹ��
	uint32_t itr_th; // ����ʱ����
	uint32_t itr_flag_status; // �жϱ�־��״̬��Ϣ
}ApbI2CHd;

typedef struct{
	ApbI2CHd* hardware; // APB-I2C�Ĵ����ӿ�(�ṹ��ָ��)
}ApbI2C;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_i2c_init(ApbI2C* i2c, uint32_t base_addr); // ��ʼ��APB-I2C

int apb_i2c_start_wt_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t* data, uint8_t len); // APB-I2C����д����
int apb_i2c_start_rd_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t len); // APB-I2C����������

int apb_i2c_get_rx_byte(ApbI2C* i2c, uint8_t* byte); // �ӽ���FIFO��ȡһ���ֽ�����

// APB-I2C��������ʱ����
void apb_i2c_config_params(ApbI2C* i2c, uint8_t tx_bytes_n_th, uint8_t rx_bytes_n_th, uint8_t scl_div_n);

void apb_i2c_enable_itr(ApbI2C* i2c, uint8_t itr_en); // APB-I2Cʹ���ж�
void apb_i2c_disable_itr(ApbI2C* i2c); // APB-I2C�����ж�
uint8_t apb_i2c_get_itr_status(ApbI2C* i2c, uint16_t* tx_bytes_n, uint16_t* rx_bytes_n); // APB-I2C��ȡ�ж�״̬
void apb_i2c_clear_itr_flag(ApbI2C* i2c); // APB-I2C����жϱ�־
