/************************************************************************************************************************
SD��FATFSʾ������
@brief  ����FATFS��SD����д����
				��ȡtest.bin���������
				��sd��д��out.txtȻ���ȡ
@attention �����Ӳ��ƽ̨�������ӳ�(delay)��ص�API
@date   2024/09/07
@author �¼�ҫ
@eidt   2024/09/07 1.00 �����˵�һ����ʽ�汾
************************************************************************************************************************/

#include "../fatfs/ff.h"

#include "../apb_sdio.h"
#include "../apb_uart.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define BASEADDR_UART 0x40002000 // UART�������ַ

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ������
static ApbUART uart;
ApbSDIO sdio;

// SD��
static FATFS fatfs;
static uint8_t sd_wt_str[] = "hello, fatfs";
static uint8_t sd_rw_buf[1024];

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void sd_fatfs_example(void){
	// ��ʼ������
	apb_uart_init(&uart, BASEADDR_UART);
	
	// ��ʼ��Ӧ��
	// fatfs
	FRESULT status;
	
	status = f_mount(&fatfs, "0:/", 1);  // ���ط����ļ�ϵͳ
	if (status != FR_OK) {
		uart_printf(&uart, "fatfs����ʧ��(code = %d)!\r\n", status);
	}else{
		uart_printf(&uart, "fatfs���سɹ�!\r\n");
	}
	
	// ��ʼ�����
	uart_printf(&uart, "\r\nϵͳ��ʼ�����!\r\n");
	
	uart_printf(&uart, "SD������->\r\n");
	
	// fatfs����
	FIL file;
	
	status = f_open(&file, "test.bin", FA_READ); // ��һ���ļ�
	if (status != FR_OK) {
		uart_printf(&uart, "���ļ�ʧ��!\r\n");
	}
	
	UINT rw_n;
	status = f_read(&file, sd_rw_buf, 1024, &rw_n); // ���ļ�
	f_close(&file);
	uint8_t fatfs_read_ok = 1;
	for(int i = 4;i < 1024;i++){
		if(sd_rw_buf[i] != ((i - 4) & 0xFF)){
			fatfs_read_ok = 0;
			break;
		}
	}
	if(fatfs_read_ok){
		uart_printf(&uart, "fatfs��ȡ���Գɹ�\r\n");
	}else{
		uart_printf(&uart, "fatfs��ȡ����ʧ��\r\n");
	}
	
	status = f_open(&file, "out.txt", FA_WRITE | FA_CREATE_ALWAYS); // ��һ���ļ�
	if (status != FR_OK) {
		uart_printf(&uart, "���ļ�ʧ��!\r\n");
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
	f_write(&file, sd_rw_buf, 1024, &rw_n); // д�ļ�
	f_close(&file);
	
	memset(sd_rw_buf, 0, 1024);
	status = f_open(&file, "out.txt", FA_READ); // ��һ���ļ�
	if (status != FR_OK) {
		uart_printf(&uart, "���ļ�ʧ��!\r\n");
	}
	status = f_read(&file, sd_rw_buf, 60, &rw_n);
	f_close(&file);
	uart_printf(&uart, "д���ļ�����: %s\r\n", sd_rw_buf);
	
	while(1);
}
