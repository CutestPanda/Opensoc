#include <stdint.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 中断类型掩码
#define I2C_TX_BYTES_N_ITR_MASK 0x01 // I2C发送指定字节数中断标志
#define I2C_SLAVE_RESP_ERR_ITR_MASK 0x02 // I2C从机响应错误中断标志
#define I2C_RX_BYTES_N_ITR_MASK 0x04 // I2C接收指定字节数中断标志
#define I2C_RX_OVF_ITR_MASK 0x08 // I2C接收溢出中断标志

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#ifndef __APB_I2C_H
#define __APB_I2C_H

typedef struct{
	uint32_t fifo_cs; // 收发fifo控制
	uint32_t itr_status_en; // 中断使能
	uint32_t itr_th; // 运行时参数
	uint32_t itr_flag_status; // 中断标志和状态信息
}ApbI2CHd;

typedef struct{
	ApbI2CHd* hardware; // APB-I2C寄存器接口(结构体指针)
}ApbI2C;

#endif

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_i2c_init(ApbI2C* i2c, uint32_t base_addr); // 初始化APB-I2C

int apb_i2c_start_wt_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t* data, uint8_t len); // APB-I2C启动写传输
int apb_i2c_start_rd_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t len); // APB-I2C启动读传输

int apb_i2c_get_rx_byte(ApbI2C* i2c, uint8_t* byte); // 从接收FIFO获取一个字节数据

// APB-I2C配置运行时参数
void apb_i2c_config_params(ApbI2C* i2c, uint8_t tx_bytes_n_th, uint8_t rx_bytes_n_th, uint8_t scl_div_n);

void apb_i2c_enable_itr(ApbI2C* i2c, uint8_t itr_en); // APB-I2C使能中断
void apb_i2c_disable_itr(ApbI2C* i2c); // APB-I2C除能中断
uint8_t apb_i2c_get_itr_status(ApbI2C* i2c, uint16_t* tx_bytes_n, uint16_t* rx_bytes_n); // APB-I2C获取中断状态
void apb_i2c_clear_itr_flag(ApbI2C* i2c); // APB-I2C清除中断标志
