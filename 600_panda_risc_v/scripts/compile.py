import os
import argparse
import subprocess

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=str, default="file", help="target to compile")
    opt = parser.parse_args()
    
    return opt

if __name__ == "__main__":
    opt = parse_opt()
    
    target_name = opt.target
    
    file_bat = open("compile.bat", 'w')
    
    file_bat.writelines("cd ../software/test/" + target_name + "\n")
    file_bat.writelines("make\n")
    file_bat.writelines("copy " + target_name + ".bin ..\\\\..\\\\..\\\\scripts\\\\" + target_name + ".bin\n")
    file_bat.writelines("copy " + target_name + ".dump ..\\\\..\\\\..\\\\scripts\\\\" + target_name + ".dump\n")
    file_bat.writelines("make clean\n")
    file_bat.writelines("cd ../../../scripts\n")
    file_bat.writelines("python gen_imem_init_txt.py --file " + target_name + "\n")
    file_bat.writelines("pause\n")
    
    file_bat.close()
    
    subprocess.run("compile.bat", shell=True)
    
    os.remove("compile.bat")
