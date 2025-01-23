import serial
from serial.tools import list_ports
import os
import time

def enum_com():
    port_names = []
    ports = list_ports.comports()
    
    for port, desc, hwid in ports:
        port_names.append(port)
    
    return port_names

if __name__ == "__main__":
    print("请选择一个串口来连接: ")
    ports = enum_com()
    
    if len(ports) > 0:
        for p in ports:
            print("    " + p)
    else:
        print("无")
    print()
    
    com_name = input()
    
    try:
        ser = serial.Serial(com_name, baudrate=115200, timeout=5)
        
        if ser.isOpen() == False:
            print(com_name + "未打开")
        
        print("打开" + com_name + "成功")
        
        print("请输入待烧录bin文件的路径:")
        bin_path = input()
        file_bin = open(bin_path, 'rb')
        
        bin_size = os.path.getsize(bin_path)
        print("bin文件大小: " + str(bin_size) + "字节")
        
        send_buf = bytes([250, 0, 0, 8, 0, 0, bin_size % 256, (bin_size // 256) % 256, (bin_size // 65536) % 256, (bin_size // 16777216) % 256, 193])
        ser.write(send_buf)
        
        time.sleep(1)
        recv_buf = ser.read(4)
        if (len(recv_buf) == 4) and (recv_buf[0] == 250) and (recv_buf[1] == 0) and (recv_buf[2] == 0) and (recv_buf[3] == 193):
            print("成功接收到编程应答")
            
            bin_data = file_bin.read(bin_size)
            
            ser.write(bin_data)
            
            time.sleep(1)
            recv_buf = ser.read(4)
            if (len(recv_buf) == 4) and (recv_buf[0] == 250) and (recv_buf[1] == 1) and (recv_buf[2] == 0) and (recv_buf[3] == 193):
                print("成功接收到编程完成")
            else:
                print("无法接收到编程完成")
        else:
            print("无法接收到编程应答")
        
        ser.close()
        file_bin.close()
    except serial.SerialException:
        print("打开" + com_name + "失败")
