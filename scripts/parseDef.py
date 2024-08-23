import argparse
import os

parser = argparse.ArgumentParser(description="parse user add defines")
parser.add_argument("-b", "--build", default="", required=True, type=str, help="build path")
parser.add_argument("-p", "--path", default="", type=str)
parser.add_argument("-e", "--extra", default="", type=str)

predef_tag = ["DIFFTEST", "ENABLE_LOG"]

def parseDef(define):
    if define[1] == "OFF":
        return f'''`ifdef {define[0]}
`undef {define[0]}
`endif
'''
    elif define[1] == "ON":
        return f'''`ifndef {define[0]}
`define {define[0]}
`endif
'''
    else:
        return f'''`ifdef {define[0]}
`undef {define[0]}
`endif
`define {define[0]} {define[1]}
'''

def main(args):
    defines = []
    if args.path != "":
        with open(args.path, "r", encoding="utf-8") as f:
            for line in f:
                define = line.split("=")
                defines.append([define[0], define[1]])
    if args.extra != "":
        extra_defines = args.extra.split(";")
        for extra_define in extra_defines:
            if "=" in extra_define:
                define = extra_define.split("=")
                defines.append([define[0], define[1]])
    if not os.path.exists(args.build):
        os.mkdir(args.build)
    with open(os.path.join(args.build, "predefine.svh"), "w", encoding="utf-8") as pre, \
         open(os.path.join(args.build, "postdefine.svh"), "w", encoding="utf-8") as post:
        pre.write("`ifndef __PRE_DEFINE_SVH__\n")
        pre.write("`define __PRE_DEFINE_SVH__\n")
        post.write("`ifndef __POST_DEFINE_SVH__\n")
        post.write("`define __POST_DEFINE_SVH__\n")
        for define in defines:
            parsed = parseDef(define)
            if define[0] in predef_tag:
                pre.write(parsed + "\n")
            else:
                post.write(parsed + "\n")
        pre.write("`endif")
        post.write("`endif")



if __name__ == "__main__":
    args = parser.parse_args()
    main(args)