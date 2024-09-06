/************************************************************************************************************************
APB-I2C示例代码
@brief  基于APB-I2C实现EEPROM读写
@attention 请根据硬件平台更换与延迟(delay)相关的API
@date   2024/08/28
@author 陈家耀
@eidt   2024/08/28 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../apb_i2c.h"
#include "delay.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define APB_I2C_BASEADDR 0x40000000 // APB-I2C外设基地址

#define EEPROM_I2C_ADDR 0xA0 // EEPROM I2C从机地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbI2C i2c; // APB-I2C外设结构体

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static uint8_t read_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr); // 读EEPROM
static void write_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr, uint8_t data); // 写EEPROM

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@io
@public
@brief  读EEPROM
@param  i2c APB-I2C(结构体指针)
        slave_addr I2C从机地址
				mem_addr 读取的地址
@return 读取到的字节数据
*************************/
static uint8_t read_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr){
	uint8_t recv_buf;
	
	uint8_t send_buf[2] = {(uint8_t)(mem_addr >> 8), (uint8_t)(mem_addr & 0x00FF)};
	
	apb_i2c_start_wt_trans(i2c, slave_addr, send_buf, 2); // 启动写传输
	apb_i2c_start_rd_trans(i2c, slave_addr, 1); // 启动读传输
	
	while(!apb_i2c_get_rx_byte(i2c, &recv_buf)); // 获取1个字节
	
	return recv_buf;
}

/*************************
@io
@public
@brief  写EEPROM
@param  i2c APB-I2C(结构体指针)
        slave_addr I2C从机地址
				mem_addr 写入的地址
			  data 待写入的字节数据
@return none
*************************/
static void write_eeprom_by_i2c(ApbI2C* i2c, uint8_t slave_addr, uint16_t mem_addr, uint8_t data){
	uint8_t send_buf[3] = {(uint8_t)(mem_addr >> 8), (uint8_t)(mem_addr & 0x00FF), data};
	
	apb_i2c_start_wt_trans(i2c, slave_addr, send_buf, 3); // 启动写传输
	
	delay_ms(10); // 延时0.01s
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void apb_i2c_eeprom_example(void){
	// 初始化APB-I2C
	apb_i2c_init(&i2c, APB_I2C_BASEADDR);
	
	// 配置运行时参数
	// I2C时钟分频系数 = 7
	apb_i2c_config_params(&i2c, 1, 1, 7);
	
	// 向地址0x00写入字节0x0A
	write_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x00, 0x0A);
	
	// 向地址0x01写入字节0xFE
	write_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x01, 0xFE);
	
	// 读取地址0x00和0x01
	uint8_t rdata[2];
	
	rdata[0] = read_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x00);
	rdata[1] = read_eeprom_by_i2c(&i2c, EEPROM_I2C_ADDR, 0x01);
	
	if((rdata[0] == 0x0A) && (rdata[1] == 0xFE)){
		// 读写验证成功
		// ...
	}else{
		// 读写验证失败
		// ...
	}
	
	while(1);
}
