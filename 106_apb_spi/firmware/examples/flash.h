#include "apb_spi.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// ss(29) MOSI(22) MISO(23) SCK(24)

void init_flash(ApbSPI* spi, uint32_t spi_base_addr);

uint8_t SPI_FLASH_ReadDeviceID(ApbSPI* spi);
uint32_t SPI_FLASH_ReadID(ApbSPI* spi);
uint8_t spi_flash_read_status_reg(ApbSPI* spi, uint8_t id);
void spi_flash_write_status_reg(ApbSPI* spi, uint16_t value);

void SPI_FLASH_SectorErase(ApbSPI* spi, uint32_t SectorAddr);
void SPI_FLASH_PageWrite(ApbSPI* spi, uint8_t* pBuffer, uint32_t WriteAddr, uint16_t NumByteToWrite);
void SPI_FLASH_BufferWrite(ApbSPI* spi, uint8_t* pBuffer, uint32_t WriteAddr, uint16_t NumByteToWrite);
void SPI_FLASH_BufferRead(ApbSPI* spi, uint8_t* pBuffer, uint32_t ReadAddr, uint16_t NumByteToRead);
