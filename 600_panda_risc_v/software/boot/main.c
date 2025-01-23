#include <stdint.h>

#include "../include/apb_uart.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// BOOT串口外设基地址
#define BOOT_UART_BASEADDE 0x40003000

// 应用程序起始地址
#define APP_BASEADDE 0x00001000

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbUART boot_uart;

// 串口接收缓存区
static uint8_t prog_req[11];
static uint8_t prog_byte;

// 编程信息
static uint32_t prog_baseaddr; // 编程起始地址
static uint32_t prog_len; // 编程字节数
static uint8_t* prog_ptr; // 编程指针

// 编程应答
static const uint8_t prog_ack[4] = {0xFA, 0x00, 0x00, 0xC1};
// 编程完成
static const uint8_t prog_cpl[4] = {0xFA, 0x01, 0x00, 0xC1};

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int main(){
	apb_uart_init(&boot_uart, BOOT_UART_BASEADDE); // 初始化APB-UART
	
	while(1){
		// 等待编程请求
		for(int i = 0;i < 11;i++){
			while(apb_uart_rev_byte(&boot_uart, &prog_req[i]));
		}
		
		if(!((prog_req[0] == 0xFA) && (prog_req[1] == 0x00) && (prog_req[10] == 0xC1))){
			continue;
		}
		
		prog_baseaddr = 
			((uint32_t)prog_req[2]) | (((uint32_t)prog_req[3]) << 8) | 
			(((uint32_t)prog_req[4]) << 16) | (((uint32_t)prog_req[5]) << 24);
		
		prog_len = 
			((uint32_t)prog_req[6]) | (((uint32_t)prog_req[7]) << 8) | 
			(((uint32_t)prog_req[8]) << 16) | (((uint32_t)prog_req[9]) << 24);
		
		prog_ptr = (uint8_t*)prog_baseaddr;
		
		// 延迟一段时间
		for(int i = 0;i < 8000000;i++);
		
		// 发送编程应答
		for(int i = 0;i < 4;i++){
			while(apb_uart_send_byte(&boot_uart, prog_ack[i]));
		}
		
		// 执行编程
		for(uint32_t i = 0;i < prog_len;i++){
			while(apb_uart_rev_byte(&boot_uart, &prog_byte));
			
			prog_ptr[i] = prog_byte;
		}
		
		// 延迟一段时间
		for(int i = 0;i < 8000000;i++);
		
		// 发送编程完成
		for(int i = 0;i < 4;i++){
			while(apb_uart_send_byte(&boot_uart, prog_cpl[i]));
		}
	}
}
