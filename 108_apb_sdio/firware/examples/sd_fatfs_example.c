/************************************************************************************************************************
SD卡FATFS示例代码
@brief  基于FATFS的SD卡读写例程
				读取test.bin并检查数据
				向sd卡写入out.txt然后读取
@attention 请根据硬件平台更换与延迟(delay)相关的API
@date   2024/09/07
@author 陈家耀
@eidt   2024/09/07 1.00 创建了第一个正式版本
************************************************************************************************************************/

#include "../fatfs/ff.h"

#include "../apb_sdio.h"
#include "../apb_uart.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_UART 0x40002000 // UART外设基地址

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 外设句柄
static ApbUART uart;
ApbSDIO sdio;

// SD卡
static FATFS fatfs;
static uint8_t sd_wt_str[] = "hello, fatfs";
static uint8_t sd_rw_buf[1024];

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void sd_fatfs_example(void){
	// 初始化外设
	apb_uart_init(&uart, BASEADDR_UART);
	
	// 初始化应用
	// fatfs
	FRESULT status;
	
	status = f_mount(&fatfs, "0:/", 1);  // 挂载分区文件系统
	if (status != FR_OK) {
		uart_printf(&uart, "fatfs挂载失败(code = %d)!\r\n", status);
	}else{
		uart_printf(&uart, "fatfs挂载成功!\r\n");
	}
	
	// 初始化完成
	uart_printf(&uart, "\r\n系统初始化完成!\r\n");
	
	uart_printf(&uart, "SD卡测试->\r\n");
	
	// fatfs测试
	FIL file;
	
	status = f_open(&file, "test.bin", FA_READ); // 打开一个文件
	if (status != FR_OK) {
		uart_printf(&uart, "打开文件失败!\r\n");
	}
	
	UINT rw_n;
	status = f_read(&file, sd_rw_buf, 1024, &rw_n); // 读文件
	f_close(&file);
	uint8_t fatfs_read_ok = 1;
	for(int i = 4;i < 1024;i++){
		if(sd_rw_buf[i] != ((i - 4) & 0xFF)){
			fatfs_read_ok = 0;
			break;
		}
	}
	if(fatfs_read_ok){
		uart_printf(&uart, "fatfs读取测试成功\r\n");
	}else{
		uart_printf(&uart, "fatfs读取测试失败\r\n");
	}
	
	status = f_open(&file, "out.txt", FA_WRITE | FA_CREATE_ALWAYS); // 打开一个文件
	if (status != FR_OK) {
		uart_printf(&uart, "打开文件失败!\r\n");
	}
	
	for(int i = 0, j = 0;i < 1024;i++){
		if(j == sizeof(sd_wt_str) - 1){
			sd_rw_buf[i] = '\n';
			j = 0;
		}else{
			sd_rw_buf[i] = sd_wt_str[j];
			j++;
		}
	}
	f_write(&file, sd_rw_buf, 1024, &rw_n); // 写文件
	f_close(&file);
	
	memset(sd_rw_buf, 0, 1024);
	status = f_open(&file, "out.txt", FA_READ); // 打开一个文件
	if (status != FR_OK) {
		uart_printf(&uart, "打开文件失败!\r\n");
	}
	status = f_read(&file, sd_rw_buf, 60, &rw_n);
	f_close(&file);
	uart_printf(&uart, "写入文件数据: %s\r\n", sd_rw_buf);
	
	while(1);
}
