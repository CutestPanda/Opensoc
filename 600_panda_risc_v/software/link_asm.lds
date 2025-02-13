OUTPUT_ARCH( "riscv" )
ENTRY( entry )

MEMORY
{
  flash (wxa!ri) : ORIGIN = 0x00000000, LENGTH = 2K
}

SECTIONS
{
    .text :
    {
        *(.text)
    } >flash AT>flash 
	
	. = ALIGN(4);
	
    _end = .;
}
