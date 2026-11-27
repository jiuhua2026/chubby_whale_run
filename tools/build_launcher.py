# -*- coding: utf-8 -*-
"""打包 Windows 启动器：<工程>/dist/大肥鱼快跑/大肥鱼快跑.exe（**单文件**）

怎么做到「一个 exe 双击就玩」
------------------------------
用 Godot 的**正式导出**（`--export-release` / `--export-debug`），并且
`binary_format/embed_pck=true` —— 把游戏数据直接嵌进 exe，所以只有一个文件：
不用管旁边有没有 pck、也不会误删。

⚠ **需要导出模板**（菜单：编辑器 → 管理导出模板 → 下载）。
  本机装好的是 **Windows 调试模板**（`windows_debug_x86_64.exe`），
  所以脚本先试 release、失败就自动退回 debug。
  调试版实测**稳定 60fps**，而且脚本里没有用到 `OS.is_debug_build()` 之类的分支，
  行为与 release 一致 —— 想拿 release 得先把模板补齐。

⚠ exe 的**文件图标 / 版本信息**由 preset 里的
  `application/modify_resources=true` + `application/icon="res://sprites/icon/icon.ico"` 打进去，
  **不需要 rcedit**。图标由 `tools/make_icon.py` 生成于 `sprites/icon/`。

用法
----
    python tools/build_launcher.py
"""
import argparse
import glob
import os
import subprocess
import sys
import time

NAME = "大肥鱼快跑"
## 导出的 exe 不可能小于这个体积（release 单文件 ≈105MB，debug ≈110MB）。
## 用来兜底"导出过程没真的写出文件"这类假成功。
MIN_EXE_BYTES = 100 * 1024 * 1024
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(PROJECT, "dist", NAME)
DEFAULT_GODOT = "D:/godot/Godot_v4.7.2-stable_win64_console.exe"
TEMPLATE_DIR = os.path.expanduser("~/AppData/Roaming/Godot/export_templates")

# ⚠ exclude_filter 必须排除这些目录：
#   tools/ 有 500 多张调试 PNG（抓帧、预览图），dist/ 有上一次的 exe —— 不排除都会被打进包里。
PRESET = """[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="tools/*, dist/*, docs/*, image/*, media/*, PV/*, .workbuddy/*"
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=0
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
binary_format/architecture="x86_64"
codesign/enable=false
application/modify_resources=true
application/icon="res://sprites/icon/icon.ico"
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version=""
application/product_version=""
application/company_name=""
application/product_name="%(name)s"
application/file_description="深海鲸鱼娘 2D 横版跑酷"
application/copyright=""
application/trademarks=""
application/export_angle=0
application/export_d3d12=0
ssh_remote_deploy/enabled=false
""" % {"name": NAME}

README = """%(name)s
%(rule)s

双击「%(name)s.exe」就能玩 —— 只有一个文件，随便放哪都行。

【放到桌面 / 任务栏】
  右键 %(name)s.exe → 「发送到」→「桌面快捷方式」。
  图标已经打进 exe 里了（是主角头像），不用另外设置。
  想钉在任务栏：右键 →「固定到任务栏」。

【操作】
  ↑ 跳　↓ 滑　空格 冲刺　　ESC 回主界面

【工程改了怎么办】
  这是打包好的快照。改完工程要重新跑一次打包：
  python tools/build_launcher.py
""" % {"name": NAME, "rule": "-" * 40}


def templates_for(ver="4.7.2.stable"):
    d = os.path.join(TEMPLATE_DIR, ver)
    return sorted(os.path.basename(p) for p in glob.glob(os.path.join(d, "*.exe")))


def unlock_target(exe):
    """目标 exe 正在运行时，把它改名挪开。

    Windows **允许重命名**一个正在运行的 exe，只是不允许删除/覆盖它
    ⇒ Godot 那种"先写 .tmp 再改名"的导出会失败（实测报错：
      `PCK 内嵌: 重命名临时文件 ... .tmp 失败`），而真实原因经常是**用户正开着游戏**。
    把旧 exe 挪成 `.old` 之后导出就能写出新文件，正在跑的实例继续用旧句柄、不会被打断。
    """
    if not os.path.isfile(exe):
        return
    try:
        open(exe, "ab").close()      # 能追加 ⇒ 没被占用
        return
    except OSError:
        pass
    old = exe + ".old"
    try:
        if os.path.exists(old):
            os.remove(old)
        os.replace(exe, old)
        print("      目标 exe 正在运行 → 已把旧的改名为 %s（游戏不用关）"
              % os.path.basename(old))
    except OSError as e:
        print("      ⚠ 无法挪开旧 exe：%s" % e)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=DEFAULT_GODOT, help="Godot 可执行文件路径")
    args = ap.parse_args()
    if not os.path.isfile(args.godot):
        sys.exit("找不到 Godot：%s（用 --godot 指定）" % args.godot)

    print("已装导出模板：%s" % (", ".join(templates_for()) or "（无）"))
    os.makedirs(DIST, exist_ok=True)
    # 清掉上一次的产物，免得残留一个过期的 pck 让人以为还在用
    for pat in ("*.pck", "*.console.exe"):
        for p in glob.glob(os.path.join(DIST, pat)):
            os.remove(p)
    with open(os.path.join(PROJECT, "export_presets.cfg"), "w", encoding="utf-8",
              newline="\n") as f:
        f.write(PRESET)

    exe = os.path.join(DIST, NAME + ".exe")
    unlock_target(exe)
    used = None
    r = None
    size = 0
    for mode, flag in (("release", "--export-release"), ("debug", "--export-debug")):
        print("[1/2] 导出（%s）…" % mode)
        t0 = time.time()
        r = subprocess.run([args.godot, "--headless", "--path", PROJECT, flag,
                            "Windows Desktop", exe],
                           capture_output=True, text=True, encoding="utf-8",
                           errors="replace")
        size = os.path.getsize(exe) if os.path.isfile(exe) else 0
        # ⚠ **只判断 `isfile` 是不够的**：旧文件也占着同一个路径 ⇒ 导出没真正替换成功也会"通过"。
        #   实测吃过这个亏：脚本报成功，用户双击的却还是 9-29 的旧 exe（连创建时间都是 9-29）。
        #   ⇒ 必须校验"这个文件是**这次**写的"：mtime 在本次开始之后 + 体积合理。
        fresh = (size > MIN_EXE_BYTES and os.path.getmtime(exe) >= t0 - 5.0)
        if r.returncode == 0 and fresh:
            used = mode
            break
        if size > 0 and not fresh:
            print("      ⚠ 该文件不是本次生成的（%.1f MB，mtime 比这次开始早 %.0f 秒）⇒ 判为失败"
                  % (size / 1048576.0, t0 - os.path.getmtime(exe)))
        else:
            print("      %s 导出不可用，换下一种" % mode)
        if mode == "release":
            print("      （通常是没装对应模板，见上面「已装导出模板」）")
    if not used:
        if r:
            print(r.stdout[-1500:], file=sys.stderr)
            print(r.stderr[-1500:], file=sys.stderr)
        sys.exit("导出失败。两种最常见的原因：\n"
                 "  ① 导出模板没装（看上面「已装导出模板」那一行）\n"
                 "  ② 目标 exe 被占用（游戏正在运行、且改名也失败）\n"
                 "Godot 的原始输出见上。")
    print("      → %.1f MB（%s 版，单文件）  **写入时间 %s**"
          % (size / 1048576.0, used,
             time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(exe)))))
    # 成功后清掉"为让位改名"的旧 exe（游戏已经关了就能删；还开着就留到下次）
    old = exe + ".old"
    if os.path.exists(old):
        try:
            os.remove(old)
            print("      已清掉打包时让位用的 .old")
        except OSError:
            print("      （.old 仍被正在运行的游戏占用，下次打包会再清）")

    print("[2/2] 写说明 …")
    with open(os.path.join(DIST, "说明.txt"), "w", encoding="utf-8",
              newline="\r\n") as f:
        f.write(README)
    print("      → 说明.txt")
    print("\n完成，双击即可游玩：\n  %s" % exe)


if __name__ == "__main__":
    main()
