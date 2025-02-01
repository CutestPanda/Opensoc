### panda_soc_test_v1
#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|

v1版本不包含PLIC，TIMER0中断被连接到CPU核的计时器中断。  

### panda_soc_test_v2
#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|
|PLIC|0xF000_0000 ~ 0xF03F_FFFF|4MB|

#### <center>外部中断</center>
|内容|中断号|
|---|---|
|不可用|0|
|GPIO0中断|1|
|TIMER0中断|2|
|UART0中断|3|

v2版本开始包含PLIC。  

### panda_soc_test_v3
#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|
|PLIC|0xF000_0000 ~ 0xF03F_FFFF|4MB|

#### <center>外部中断</center>
|内容|中断号|
|---|---|
|不可用|0|
|GPIO0中断|1|
|TIMER0中断|2|
|UART0中断|3|

指令存储器的低2KB用作bootrom。  
v3版本开始支持UART编程烧录。  

### panda_soc_test_v4
#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|
|PLIC|0xF000_0000 ~ 0xF03F_FFFF|4MB|
|CLINT|0xF400_0000 ~ 0xF7FF_FFFF|64MB|

#### <center>外部中断</center>
|内容|中断号|
|---|---|
|不可用|0|
|GPIO0中断|1|
|TIMER0中断|2|
|UART0中断|3|

指令存储器的低2KB用作bootrom。  
v4版本开始包含CLINT。  
