#include "flash.h"

#include <stdio.h>

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SPI0_BASEADDR 0x43C00000
#define FLASH_RW_TEST_ADDR 8192

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static ApbSPI spi0;

static uint8_t wbuf[] = "hello, W25QXX";
static uint8_t rbuf[sizeof(wbuf)];

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void flash_rw_test_example(){
	init_flash(&spi0, SPI0_BASEADDR);
	
	uint32_t flash_id = SPI_FLASH_ReadID(&spi0);
	
	printf("id = %x\r\n", (int)flash_id);
	
	SPI_FLASH_SectorErase(&spi0, FLASH_RW_TEST_ADDR);
	SPI_FLASH_BufferWrite(&spi0, wbuf, FLASH_RW_TEST_ADDR, sizeof(wbuf));
	SPI_FLASH_BufferRead(&spi0, rbuf, FLASH_RW_TEST_ADDR, sizeof(wbuf));
	
	uint8_t match_flag = 1;
	
	for(int i = 0;i < sizeof(wbuf);i++){
		if(rbuf[i] != wbuf[i]){
			match_flag = 0;
			
			break;
		}
	}
	
	printf("success = %d\r\n", match_flag);
}
