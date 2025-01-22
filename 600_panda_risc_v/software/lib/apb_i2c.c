/************************************************************************************************************************
APB-I2C驱动(主源文件)
@brief  APB-I2C驱动
@date   2024/08/28
@author 陈家耀
@eidt   2024/08/28 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../include/apb_i2c.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static int apb_i2c_tx(ApbI2C* i2c, uint8_t byte, uint8_t is_last); // 向发送FIFO写入一个字节数据

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化APB-I2C
@param  i2c APB-I2C(结构体指针)
        base_addr APB-I2C外设基地址
@return none
*************************/
void apb_i2c_init(ApbI2C* i2c, uint32_t base_addr){
	i2c->hardware = (ApbI2CHd*)base_addr;
}

/*************************
@io
@public
@brief  APB-I2C启动写传输
@param  i2c APB-I2C(结构体指针)
        slave_addr 从机地址
        data 待发送字节缓冲区(首地址)
        len 待发送字节数
@attention 向发送fifo写数据可能会产生阻塞
@return 是否成功
*************************/
int apb_i2c_start_wt_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t* data, uint8_t len){
	if(len > 15){ // 每个I2C数据包不能超过15字节
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
@brief  APB-I2C启动读传输
@param  i2c APB-I2C(结构体指针)
        slave_addr 从机地址
        len 待接收字节数
@attention 向发送fifo写数据可能会产生阻塞
@return 是否成功
*************************/
int apb_i2c_start_rd_trans(ApbI2C* i2c, uint8_t slave_addr, uint8_t len){
	if(len > 15){ // 每个I2C数据包不能超过15字节
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
@brief  从接收FIFO获取一个字节数据
@param  i2c APB-I2C(结构体指针)
        byte 接收字节缓冲区(首地址)
@return 是否成功
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
@brief  APB-I2C使能中断
@param  i2c APB-I2C(结构体指针)
        itr_en 中断使能向量
@return none
*************************/
void apb_i2c_enable_itr(ApbI2C* i2c, uint8_t itr_en){
	i2c->hardware->itr_status_en = 0x00000001 | (((uint32_t)itr_en) << 8);
}

/*************************
@cfg
@public
@brief  APB-I2C除能中断
@param  i2c APB-I2C(结构体指针)
@return none
*************************/
void apb_i2c_disable_itr(ApbI2C* i2c){
	i2c->hardware->itr_status_en = 0x00000000;
}

/*************************
@cfg
@public
@brief  APB-I2C配置运行时参数
@param  i2c APB-I2C(结构体指针)
			  tx_bytes_n_th I2C发送中断字节数阈值
				rx_bytes_n_th I2C接收中断字节数阈值
				scl_div_n I2C时钟分频系数
@return none
*************************/
void apb_i2c_config_params(ApbI2C* i2c, uint8_t tx_bytes_n_th, uint8_t rx_bytes_n_th, uint8_t scl_div_n){
	i2c->hardware->itr_th = ((uint32_t)tx_bytes_n_th) | (((uint32_t)rx_bytes_n_th) << 8)
		 | (((uint32_t)scl_div_n) << 16);
}

/*************************
@sts
@public
@brief  APB-I2C获取中断状态
@param  i2c APB-I2C(结构体指针)
			  tx_bytes_n I2C发送字节数(指针)
				rx_bytes_n I2C接收字节数(指针)
@return 中断状态
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
@brief  APB-I2C清除中断标志
@param  i2c APB-I2C(结构体指针)
@return none
*************************/
void apb_i2c_clear_itr_flag(ApbI2C* i2c){
	i2c->hardware->itr_flag_status = 0x00000000;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@io
@private
@brief  向发送FIFO写入一个字节数据
@param  i2c APB-I2C(结构体指针)
        byte 待写入的字节数据
			  is_last 附带的last指示
@return 是否成功
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
