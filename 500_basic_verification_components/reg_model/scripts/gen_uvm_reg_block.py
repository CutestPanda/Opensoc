import os
import re
import argparse

class RegMemb:
    def __init__(self, typ="Reg", name="reg", ofs_addr="32'h00", access="RW", hdl_path="", rand=True):
        self.__typ = typ
        self.__name = name
        self.__ofs_addr = ofs_addr
        self.__access = '\"' + access + '\"'
        self.__hdl_path = '\"' + hdl_path + '\"'
        self.__rand = rand
    
    def gen_member_def_code(self):
        return self.__insert_tab(1) + ("rand " if self.__rand else "") + self.__typ + " " + self.__name + ";\n"
    
    def gen_reg_init_code(self):
        return self.__insert_tab(2) + "this." + self.__name + " = " + self.__typ + "::type_id::create(\"" + \
            self.__name + "\", this.get_full_name());\n" + \
            self.__insert_tab(2) + "this." + self.__name + ".configure(this, null, " + self.__hdl_path + ");\n" + \
            self.__insert_tab(2) + "this." + self.__name + ".build();\n"
    
    def gen_map_add_code(self):
        return self.__insert_tab(2) + "this.default_map.add_reg(this." + self.__name + ", " + self.__ofs_addr + ", " + \
            self.__access + ");\n"
    
    def __insert_tab(self, n):
        return "".join(["    " for _ in range(n)])

class RegBlkDef:
    def __init__(self, name="RegBlk", baseaddr="32'h4000_0000", bus_width="32", endian="UVM_LITTLE_ENDIAN", \
        en_byte_addr="0", cvg_mode="UVM_NO_COVERAGE"):
        self.__name = name
        self.__baseaddr = baseaddr
        self.__bus_width = str(int(bus_width)//8)
        self.__endian = endian
        self.__en_byte_addr = en_byte_addr
        self.__cvg_mode = cvg_mode
        
        self.__reg_members = []
    
    def add_reg_memb(self, reg_memb=None):
        if reg_memb != None:
            self.__reg_members.append(reg_memb)
    
    def gen_code(self):
        return self.__gen_class_title_code() + \
            self.__gen_memb_def_code() + "\n" + \
            self.__gen_registry_code() + "\n" + \
            self.__gen_constructor_code() + "\n" + \
            self.__gen_build_func_code() + "\n" + \
            self.__gen_class_foot_code()
    
    def __gen_class_title_code(self):
        return "class " + self.__name + " extends uvm_reg_block;\n"
    
    def __gen_memb_def_code(self):
        memb_def_code = ""
        
        for reg_memb in self.__reg_members:
            memb_def_code += reg_memb.gen_member_def_code()
        
        return memb_def_code
    
    def __gen_registry_code(self):
        return self.__insert_tab(1) + "`uvm_object_utils(" + self.__name + ")\n"
    
    def __gen_constructor_code(self):
        return self.__insert_tab(1) + "function new(input string name = \"" + self.__name + "\");\n" + \
            self.__insert_tab(2) + "super.new(name, " + self.__cvg_mode + ");\n" + \
            self.__insert_tab(1) + "endfunction\n"
    
    def __gen_build_func_code(self):
        regs_init_code = ""
        add_map_code = ""
        
        for reg_memb in self.__reg_members:
            regs_init_code += reg_memb.gen_reg_init_code() + "\n"
            add_map_code += reg_memb.gen_map_add_code()
        
        return self.__insert_tab(1) + "virtual function void build();\n" + \
            self.__insert_tab(2) + "this.default_map = this.create_map(\"default_map\", " + self.__baseaddr + ", " + \
            self.__bus_width + ", " + self.__endian + ", " + self.__en_byte_addr + ");\n" + \
            "\n" + regs_init_code + \
            add_map_code + \
            self.__insert_tab(1) + "endfunction\n"
    
    def __gen_class_foot_code(self):
        return "endclass\n"
    
    def __insert_tab(self, n):
        return "".join(["    " for _ in range(n)])

def parse_regblk_define_str(lines):
    lines = list(filter(lambda l: re.sub(r"[\s\n]+", "", l) != "", lines))
    
    property_arr = []
    for p in lines[0].split(','):
        p = re.sub(r"[\s\n]+", "", p)
        property_arr.append(p.split('=')[1])
    
    reg_blk_obj = RegBlkDef(property_arr[0], property_arr[1], property_arr[2], property_arr[3], \
        property_arr[4], property_arr[5])
    
    for i in range(3, len(lines)):
        p = list(filter(lambda e: re.sub(r"[\s\n]+", "", e) != "", lines[i].split("|")))
        p = [re.sub(r"\s+", "", s) for s in p]
        
        reg_obj = RegMemb(p[0], p[1], p[2], p[3], p[4] if p[4] != "x" else "", p[5] == "1")
        
        reg_blk_obj.add_reg_memb(reg_obj)
    
    return reg_blk_obj.gen_code()

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", type=str, default="reg_block.txt", help="File of RegBlk Description")
    parser.add_argument("-o", type=str, default="code.sv", help="Output SV Code")
    opt = parser.parse_args()
    
    return opt

if __name__ == "__main__":
    opt = parse_opt()
    
    ifile = opt.i
    ofile = opt.o
    
    code_str = ""
    
    with open(ifile, 'r', encoding='utf-8') as fr:
        lines = fr.readlines()
        code_str = parse_regblk_define_str(lines)
    
    with open(ofile, 'w', encoding='utf-8') as fr:
        fr.write(code_str)
