/*-----------------------------------------------------------------------*/
/* Low level disk I/O module SKELETON for FatFs     (C)ChaN, 2019        */
/*-----------------------------------------------------------------------*/
/* If a working storage control module is available, it should be        */
/* attached to the FatFs via a glue function rather than modifying it.   */
/* This is an example of glue functions to attach various exsisting      */
/* storage control modules to the FatFs module with a defined API.       */
/*-----------------------------------------------------------------------*/

#include "ff.h"			/* Obtains integer types */
#include "diskio.h"		/* Declarations of disk functions */

/* Definitions of physical drive number for each drive */
#define SD_CARD 0 // SD卡(卷标为0)
#define SPI_FLASH 1 // SPI-Flash模块(卷标为1)

/* 配置参数 */
#define SD_EN_WIDE_IF 1 // 是否使用4位SDIO总线
#define SD_BLOCKSIZE 512 // SD卡块大小(以字节计)
#define SD_SECTOR_COUNT 32 * 1024 * 2 // SD卡块总数

#define BASEADDR_SDIO 0x4000D000 // SDIO控制器基地址

extern ApbSDIO sdio;

/*-----------------------------------------------------------------------*/
/* Get Drive Status                                                      */
/*-----------------------------------------------------------------------*/

DSTATUS disk_status (
	BYTE pdrv		/* Physical drive nmuber to identify the drive */
)
{
	return RES_OK;
}



/*-----------------------------------------------------------------------*/
/* Inidialize a Drive                                                    */
/*-----------------------------------------------------------------------*/

DSTATUS disk_initialize (
	BYTE pdrv				/* Physical drive nmuber to identify the drive */
)
{
	SDCardInitRes sdcard_init_res;
	
	if(pdrv == SD_CARD){ // SD卡
		apb_sdio_init(&sdio, BASEADDR_SDIO);
		
		if(sd_card_init(&sdio, SD_EN_WIDE_IF, &sdcard_init_res, BASEADDR_SDIO) == SD_CARD_INIT_SUCCESS){
			return 0;
		}else{
			return STA_NOINIT;
		}
	}else{
		return STA_NOINIT;
	}
}



/*-----------------------------------------------------------------------*/
/* Read Sector(s)                                                        */
/*-----------------------------------------------------------------------*/

DRESULT disk_read (
	BYTE pdrv,		/* Physical drive nmuber to identify the drive */
	BYTE *buff,		/* Data buffer to store read data */
	LBA_t sector,	/* Start sector in LBA */
	UINT count		/* Number of sectors to read */
)
{
	uint32_t* buf_ptr = (uint32_t*)buff;
	DRESULT status;

	switch (pdrv) {
		case SD_CARD:
			if(count == 1){
				while(sd_card_send_read_single_block_cmd(&sdio, sector));
				while(!__apb_sdio_is_ctrler_idle(&sdio));
				if(sd_card_read_data_block(&sdio, buf_ptr) != 128){
					return RES_ERROR;
				}
			}else{
				uint32_t now_sec_addr = sector;
				uint8_t read_n;
				
				while(count){
					read_n = count >= 16 ? 16:count;
					
					while(sd_card_send_read_mul_block_cmd(&sdio, now_sec_addr, read_n - 1));
					while(!__apb_sdio_is_ctrler_idle(&sdio));
					if(sd_card_read_data_block(&sdio, buf_ptr) != read_n * 128){
						return RES_ERROR;
					}
					while(sd_card_stop_trans(&sdio));
					while(!__apb_sdio_is_ctrler_idle(&sdio));
					
					count -= read_n;
					now_sec_addr += read_n;
					buf_ptr += read_n * 128;
				}
			}
			
			status = RES_OK;
			break;
		
		default:
			status = RES_PARERR;
			break;
	}

	return status;
}



/*-----------------------------------------------------------------------*/
/* Write Sector(s)                                                       */
/*-----------------------------------------------------------------------*/

#if FF_FS_READONLY == 0

DRESULT disk_write (
	BYTE pdrv,			/* Physical drive nmuber to identify the drive */
	const BYTE *buff,	/* Data to be written */
	LBA_t sector,		/* Start sector in LBA */
	UINT count			/* Number of sectors to write */
)
{
	uint32_t* buf_ptr = (uint32_t*)buff;
	DRESULT status;
	
	switch (pdrv) {
		case SD_CARD:
			if(count == 1){
				sd_card_write_data_block(&sdio, buf_ptr, 128);
				while(sd_card_send_write_single_block_cmd(&sdio, sector));
				while(!__apb_sdio_is_ctrler_idle(&sdio));
			}else{
				uint32_t now_sec_addr = sector;
				
				// 使用多块写
				uint8_t write_n;
				
				while(count){
					write_n = count >= 16 ? 16:count;
					
					sd_card_write_data_block(&sdio, buf_ptr, write_n * 128);
					while(sd_card_send_write_mul_block_cmd(&sdio, now_sec_addr, write_n - 1));
					while(!__apb_sdio_is_ctrler_idle(&sdio));
					while(sd_card_stop_trans(&sdio));
					while(!__apb_sdio_is_ctrler_idle(&sdio));
					
					count -= write_n;
					now_sec_addr += write_n;
					buf_ptr += write_n * 128;
				}
				
				/*
				// 仅使用单块写
				while(count){
					sd_card_write_data_block(&sdio, buf_ptr, 128);
					while(!sd_card_send_write_single_block_cmd(&sdio, now_sec_addr));
					while(!__apb_sdio_is_ctrler_idle(&sdio));
					
					count--;
					now_sec_addr++;
					buf_ptr += 128;
				}
				*/
			}
			status = RES_OK;
			break;
		default:
			status = RES_PARERR;
			break;
	}
	
	return status;
}

#endif


/*-----------------------------------------------------------------------*/
/* Miscellaneous Functions                                               */
/*-----------------------------------------------------------------------*/

DRESULT disk_ioctl (
	BYTE pdrv,		/* Physical drive nmuber (0..) */
	BYTE cmd,		/* Control code */
	void *buff		/* Buffer to send/receive control data */
)
{
	DRESULT status = RES_PARERR;
	
	switch (pdrv) {
		case SD_CARD:
			switch (cmd) {
				// Get R/W sector size (WORD) 
				case GET_SECTOR_SIZE:    
					*(WORD*)buff = SD_BLOCKSIZE;
					break;
				// Get erase block size in unit of sector (DWORD)
				case GET_BLOCK_SIZE:      
					*(DWORD*)buff = 1;
					break;
				case GET_SECTOR_COUNT:
					*(DWORD*)buff = SD_SECTOR_COUNT;
					break;
				case CTRL_SYNC:
					break;
			}
			
			status = RES_OK;
			
			break;
		default:
			status = RES_PARERR;
			break;
	}
	
	return status;
}

