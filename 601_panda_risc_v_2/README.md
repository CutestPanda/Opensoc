## v2版本新特性
(1)6级流水线（预取指/分支预测、取指、预取操作数、取操作数/译码/发射、分发/执行、交付/写回）  
(2)动态分支预测（预测方向：全局/局部分支历史；预测地址：BTB、RAS）  

| 分支指令类型 | 预测准确率 |
| ------------ | ---------- |
| JAL          | 99.946%    |
| JALR         | 97.597%    |
| B            | 94.230%    |

另外，测得BTB命中率为99.973%。  

> 分支预测准确率是从运行coremark程序中得到的。  
>
> 分支预测配置：  
>
> - BHT深度 = 512、BHT位宽 = 13、PHT地址位宽 = 16（13位用于索引BHR，3位用于索引PC的低位）  
> - BTB路数 = 2、BTB项数 = 1024  
> - RAS条目数 = 4  

(3)采用基于ROB的寄存器重命名  
(4)跑分2.663Coremark/MHz  
(5)采用AXI-Lite协议的指令、数据、外设总线  

![第2版小胖达risc-v微架构](../img/panda_risc_v_24.png)  

> 使用说明请见[**600_panda_risc_v**里的README](https://github.com/CutestPanda/Opensoc/tree/main/600_panda_risc_v)。  

## 示例硬件工程

v2版本的示例硬件工程在fpga文件夹里。需要注意的是，v2版本的示例硬件工程的存储映射、I/O与v1版本的不同，请查看**soc_rtl/panda_soc_top.v**。  

![示例硬件工程的顶层模块](../img/panda_risc_v_26.png)  

使用示例硬件工程时，请修改参数**ITCM_MEM_INIT_FILE**和**CPU_CLK_FREQUENCY_MHZ**，boot_rom.txt位于**上级目录/600_panda_risc_v/fpga**文件夹里。PLL请重新例化，根据需要来修改输出的时钟频率。  