#include "flash.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SPI_FLASH_PageSize 256
#define SPI_FLASH_PerWritePageSize 256

#define W25X_WriteEnable 0x06
#define W25X_WriteDisable 0x04
#define W25X_ReadStatusReg_0 0x05
#define W25X_ReadStatusReg_1 0x35
#define W25X_WriteStatusReg 0x01
#define W25X_ReadData 0x03
#define W25X_FastReadData 0x0B
#define W25X_FastReadDual 0x3B
#define W25X_PageProgram 0x02
#define W25X_BlockErase 0xD8
#define W25X_SectorErase 0x20
#define W25X_ChipErase 0xC7
#define W25X_PowerDown 0xB9
#define W25X_ReleasePowerDown 0xAB
#define W25X_DeviceID 0xAB
#define W25X_ManufactDeviceID 0x90
#define W25X_JedecDeviceID 0x9F

#define WIP_Flag 0x01

#define Dummy_Byte 0x00

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static uint8_t SPI_FLASH_SendByte(ApbSPI* spi, uint8_t byte);
static void SPI_FLASH_WaitForWriteEnd(ApbSPI* spi);
static void SPI_FLASH_WriteEnable(ApbSPI* spi);

////////////////////////////////////////////////////////////////////////////////////////////////////////////

void init_flash(ApbSPI* spi, uint32_t spi_base_addr){
	apb_spi_init(spi, spi_base_addr);
	apb_spi_set_direction(spi, SPI_DIRE_SEND_REV);
	apb_spi_set_slave_sel(spi, 0);
}

uint8_t SPI_FLASH_ReadDeviceID(ApbSPI* spi){
	uint8_t device_id;
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
  SPI_FLASH_SendByte(spi, W25X_DeviceID);
  SPI_FLASH_SendByte(spi, Dummy_Byte);
  SPI_FLASH_SendByte(spi, Dummy_Byte);
  SPI_FLASH_SendByte(spi, Dummy_Byte);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
	device_id = SPI_FLASH_SendByte(spi, Dummy_Byte);
  
  return device_id;
}

uint32_t SPI_FLASH_ReadID(ApbSPI* spi){
  uint8_t temp0 = 0, temp1 = 0, temp2 = 0;
	uint32_t id;
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
  SPI_FLASH_SendByte(spi, W25X_JedecDeviceID);
  temp0 = SPI_FLASH_SendByte(spi, Dummy_Byte);
  temp1 = SPI_FLASH_SendByte(spi, Dummy_Byte);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
  temp2 = SPI_FLASH_SendByte(spi, Dummy_Byte);

  id = (((uint32_t)temp0) << 16) | (((uint32_t)temp1) << 8) | ((uint32_t)temp2);

  return id;
}

uint8_t spi_flash_read_status_reg(ApbSPI* spi, uint8_t id){
	uint8_t sts_reg;
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
	
	if(id == 0){
		SPI_FLASH_SendByte(spi, W25X_ReadStatusReg_0);
	}else{
		SPI_FLASH_SendByte(spi, W25X_ReadStatusReg_1);
	}
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
	sts_reg = SPI_FLASH_SendByte(spi, Dummy_Byte);
  
  return sts_reg;
}

void spi_flash_write_status_reg(ApbSPI* spi, uint16_t value){
	// ÎÞ·¨Ð´×´Ì¬¼Ä´æÆ÷???
	uint8_t byte0 = (uint8_t)(value & 0x00FF);
	uint8_t byte1 = (uint8_t)(value >> 8);
	
	SPI_FLASH_WriteEnable(spi);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
	
	SPI_FLASH_SendByte(spi, W25X_WriteStatusReg);
	SPI_FLASH_SendByte(spi, byte0);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
	SPI_FLASH_SendByte(spi, byte1);
}

void SPI_FLASH_SectorErase(ApbSPI* spi, uint32_t SectorAddr){
  SPI_FLASH_WriteEnable(spi);
  SPI_FLASH_WaitForWriteEnd(spi);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
  SPI_FLASH_SendByte(spi, W25X_SectorErase);
  SPI_FLASH_SendByte(spi, (SectorAddr & 0x00FF0000) >> 16);
  SPI_FLASH_SendByte(spi, (SectorAddr & 0x0000FF00) >> 8);
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
  SPI_FLASH_SendByte(spi, SectorAddr & 0x000000FF);
  
  SPI_FLASH_WaitForWriteEnd(spi);
}

void SPI_FLASH_PageWrite(ApbSPI* spi, uint8_t* pBuffer, uint32_t WriteAddr, uint16_t NumByteToWrite){
  SPI_FLASH_WriteEnable(spi);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
  SPI_FLASH_SendByte(spi, W25X_PageProgram);
  SPI_FLASH_SendByte(spi, (WriteAddr & 0x00FF0000) >> 16);
  SPI_FLASH_SendByte(spi, (WriteAddr & 0x0000FF00) >> 8);
  SPI_FLASH_SendByte(spi, WriteAddr & 0x000000FF);

  if(NumByteToWrite > SPI_FLASH_PerWritePageSize){
		NumByteToWrite = SPI_FLASH_PerWritePageSize;
  }

  while(NumByteToWrite--){
		apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, NumByteToWrite == 0);
		SPI_FLASH_SendByte(spi, *pBuffer);
		pBuffer++;
  }

  SPI_FLASH_WaitForWriteEnd(spi);
}

void SPI_FLASH_BufferWrite(ApbSPI* spi, uint8_t* pBuffer, uint32_t WriteAddr, uint16_t NumByteToWrite){
  uint8_t NumOfPage = 0, NumOfSingle = 0, Addr = 0, count = 0, temp = 0;

  Addr = WriteAddr % SPI_FLASH_PageSize;
  count = SPI_FLASH_PageSize - Addr;
  NumOfPage =  NumByteToWrite / SPI_FLASH_PageSize;
  NumOfSingle = NumByteToWrite % SPI_FLASH_PageSize;

  if (Addr == 0){
		if (NumOfPage == 0){
      SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, NumByteToWrite);
    }else{
      while(NumOfPage--){
        SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, SPI_FLASH_PageSize);
        WriteAddr += SPI_FLASH_PageSize;
        pBuffer += SPI_FLASH_PageSize;
      }

      SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, NumOfSingle);
    }
  }else{
    if (NumOfPage == 0){
      if (NumOfSingle > count){
        temp = NumOfSingle - count;

        SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, count);
        WriteAddr += count;
        pBuffer += count;

        SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, temp);
      }else{
        SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, NumByteToWrite);
      }
    }
    else{
      NumByteToWrite -= count;
      NumOfPage =  NumByteToWrite / SPI_FLASH_PageSize;
      NumOfSingle = NumByteToWrite % SPI_FLASH_PageSize;

      SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, count);
      WriteAddr += count;
      pBuffer += count;

      while(NumOfPage--){
        SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, SPI_FLASH_PageSize);
        WriteAddr +=  SPI_FLASH_PageSize;
        pBuffer += SPI_FLASH_PageSize;
      }

      if(NumOfSingle != 0){
        SPI_FLASH_PageWrite(spi, pBuffer, WriteAddr, NumOfSingle);
      }
    }
  }
}

void SPI_FLASH_BufferRead(ApbSPI* spi, uint8_t* pBuffer, uint32_t ReadAddr, uint16_t NumByteToRead){
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
  SPI_FLASH_SendByte(spi, W25X_ReadData);

  SPI_FLASH_SendByte(spi, (ReadAddr & 0x00FF0000) >> 16);
  SPI_FLASH_SendByte(spi, (ReadAddr & 0x0000FF00) >> 8);
  SPI_FLASH_SendByte(spi, ReadAddr & 0x000000FF);

  while(NumByteToRead--){
		apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, NumByteToRead == 0);
    *pBuffer = SPI_FLASH_SendByte(spi, Dummy_Byte);
    pBuffer++;
  }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

static uint8_t SPI_FLASH_SendByte(ApbSPI* spi, uint8_t byte){
	uint8_t rev_byte;
	
	while(!apb_spi_tx_rx(spi, byte));
	while(!apb_spi_get_rev_byte(spi, &rev_byte));
	
	return rev_byte;
}

static void SPI_FLASH_WaitForWriteEnd(ApbSPI* spi){
  uint8_t flash_status = 0;
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 0);
  SPI_FLASH_SendByte(spi, W25X_ReadStatusReg_0);

  do{
    flash_status = SPI_FLASH_SendByte(spi, Dummy_Byte);	 
  }
  while(flash_status & WIP_Flag);
	
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
	SPI_FLASH_SendByte(spi, Dummy_Byte);
}

static void SPI_FLASH_WriteEnable(ApbSPI* spi){
	apb_spi_set_user(spi, 0, SPI_NOW_BYTE_SEND, SPI_NOW_BYTE_DISABLE_MUL, 1);
  SPI_FLASH_SendByte(spi, W25X_WriteEnable);
}
