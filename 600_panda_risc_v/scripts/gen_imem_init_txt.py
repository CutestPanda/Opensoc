import os

print("please input bin_filename:")
bin_filename = input()

print("please input txt_filename:")
txt_filename = input()

file_bin = open(bin_filename, 'rb')
bin_size = os.path.getsize(bin_filename)
print("bin文件大小 = " + str(bin_size))

file_txt = open(txt_filename, 'w')

for i in range(bin_size // 4):
    data = file_bin.read(4)
    bins = [hex(data[3]), hex(data[2]), hex(data[1]), hex(data[0])]
    file_txt.writelines(bins[0][2:].zfill(2) + bins[1][2:].zfill(2) + bins[2][2:].zfill(2) + bins[3][2:].zfill(2) + '\n')

file_bin.close()
file_txt.close()
