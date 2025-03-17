### TD工程下载
测试FPGA板的型号为EG4S20BG256。  
[百度云链接](https://pan.baidu.com/s/1Wq-isumnnuQNxXdvCApr0g?pwd=1234)  

### panda_soc_test_v1
#### <center>存储映射表</center>
|内容|地址范围|区间长度|
|---|---|---|
|指令存储器|0x0000_0000 ~ ?|imem_depth|
|数据存储器|0x1000_0000 ~ ?|dmem_depth|
|APB-GPIO|0x4000_0000 ~ 0x4000_0FFF|4KB|
|APB-I2C|0x4000_1000 ~ 0x4000_1FFF|4KB|
|APB-TIMER|0x4000_2000 ~ 0x4000_2FFF|4KB|
|APB-UART|0x4000_3000 ~ 0x4000_3FFF|4KB|
|PLIC|0xF000_0000 ~ 0xF03F_FFFF|4MB|
|CLINT|0xF400_0000 ~ 0xF7FF_FFFF|64MB|
|调试模块|0xFFFF_F800 ~ 0xFFFF_FBFF|1KB|

#### <center>外部中断</center>
|内容|中断号|
|---|---|
|不可用|0|
|GPIO0中断|1|
|TIMER0中断|2|
|UART0中断|3|
