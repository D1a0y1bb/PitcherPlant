import argparse
import json
import os
import time


def banner() -> None:
    print(
        r"""
   _________   __      ____              
  / _______/  / /     / __ \   ____  ____
 / /     ____/ /____ / / / /  / __ \/ __ \
/ /____ /____  /____// /_/ /  / /_/ / /_/ /
\_____/      /_/     \____/   \____/\____/ 
   PitcherPlant • Writeup 自动化审计
"""
    )


def easter_show() -> None:
    frames = [
        "✦        ",
        " ✦       ",
        "  ✦      ",
        "   ✦     ",
        "    ✦    ",
        "     ✦   ",
        "      ✦  ",
        "       ✦ ",
        "        ✦",
    ]
    for _ in range(2):
        for frame in frames:
            print(f"\r{frame} PitcherPlant · Smart Audit ✦", end="", flush=True)
            time.sleep(0.05)
    print()


def _load_run_audit():
    try:
        from .audit import run_audit
    except RuntimeError as exc:
        raise SystemExit(str(exc)) from exc
    return run_audit


def run_menu() -> int:
    banner()
    print("[1] 选择审计文件夹")
    print("[2] 设置文本相似度阈值")
    print("[3] 设置图片汉明距离阈值")
    print("[4] 设置报告输出目录")
    print("[5] 设置报告文件名模板")
    print("[6] 切换 OpenCV 预处理 开/关")
    print("[7] 开始审计")
    print("[8] 彩蛋展示")

    directory = None
    text_thresh = 0.75
    img_thresh = 5
    output_dir = None
    name_template = None
    cv_preprocess = True
    dedup_thresh = 0.85

    while True:
        choice = input("请输入选项编号: ").strip()
        if choice == "1":
            directory = input("请输入文件夹路径: ").strip()
        elif choice == "2":
            try:
                text_thresh = float(input("请输入文本阈值(0.0-1.0): ").strip())
            except ValueError:
                pass
        elif choice == "3":
            try:
                img_thresh = int(input("请输入图片汉明距离阈值(0-10): ").strip())
            except ValueError:
                pass
        elif choice == "4":
            output_dir = input("请输入报告输出目录: ").strip()
        elif choice == "5":
            print("示例: {dir}_PitcherPlant_{date}.html")
            name_template = input("请输入文件名模板: ").strip()
        elif choice == "6":
            cv_preprocess = not cv_preprocess
            print(f"OpenCV 预处理: {cv_preprocess}")
        elif choice == "7":
            if not directory:
                print("请先设置审计文件夹")
                continue
            run_audit = _load_run_audit()
            run_audit(
                directory,
                text_thresh,
                img_thresh,
                output_dir,
                name_template,
                cv_preprocess,
                dedup_thresh,
            )
            return 0
        elif choice == "8":
            easter_show()
        else:
            print("无效选项")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="CTF Writeup 自动化审计工具 (专业版)",
        formatter_class=argparse.RawTextHelpFormatter,
        add_help=False,
    )
    parser.add_argument("directory", nargs="?", help="Writeup 文件所在的目录路径")
    parser.add_argument("-h", "--help", action="help", default=argparse.SUPPRESS, help="显示此帮助信息并退出")
    parser.add_argument(
        "--text-thresh",
        type=float,
        default=0.75,
        metavar="FLOAT",
        help="文本相似度阈值 (0.0-1.0)\n默认: 0.75 (超过此值视为疑似抄袭)",
    )
    parser.add_argument(
        "--img-thresh",
        type=int,
        default=5,
        metavar="INT",
        help="图片哈希汉明距离阈值 (0-10)\n默认: 5 (数值越小越严格，0表示完全一致)",
    )
    parser.add_argument("--menu", action="store_true", help="启动交互式菜单模式")
    parser.add_argument("--output", type=str, default=None, help="报告输出目录")
    parser.add_argument("--name", type=str, default=None, help="报告文件名模板，支持 {dir} 与 {date}")
    parser.add_argument("--no-cv", action="store_true", help="禁用 OpenCV 预处理")
    parser.add_argument("--config", type=str, default=None, help="从 JSON 配置文件加载参数")
    parser.add_argument("--egg", action="store_true", help="显示 ASCII 彩蛋节目")
    parser.add_argument("--dedup-thresh", type=float, default=0.85, help="重复文件去重相似度阈值 (0.0-1.0)")
    parser.add_argument("--db-path", type=str, default=None, help="指纹库sqlite路径，默认 ./PitcherPlant.sqlite")
    parser.add_argument("--whitelist", type=str, default=None, help="白名单文件路径，按行配置 author:xxx/filename:xxx/simhash:xxx")
    parser.add_argument("--simhash-thresh", type=int, default=4, help="跨批次SimHash匹配容忍位差 (0-64)")
    parser.add_argument("--whitelist-mode", type=str, default="mark", choices=["hide", "mark"], help="白名单命中是否隐藏或标记")
    return parser


def _load_config(path: str | None) -> dict:
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return {}


def main(argv=None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.egg:
        banner()
        easter_show()
        return 0

    cfg = _load_config(args.config)

    if args.menu or (not args.directory and not cfg.get("directory")):
        return run_menu()

    directory = args.directory or cfg.get("directory")
    if not directory or not os.path.exists(directory):
        print(f"错误: 找不到目录 '{directory}'")
        return 1

    text_thresh = args.text_thresh if args.text_thresh is not None else cfg.get("text_thresh", 0.75)
    img_thresh = args.img_thresh if args.img_thresh is not None else cfg.get("img_thresh", 5)
    output_dir = args.output or cfg.get("output")
    name_template = args.name or cfg.get("name")
    cv_preprocess = False if args.no_cv else cfg.get("cv_preprocess", True)
    dedup_thresh = args.dedup_thresh if args.dedup_thresh is not None else cfg.get("dedup_thresh", 0.85)
    simhash_thresh = args.simhash_thresh if args.simhash_thresh is not None else cfg.get("simhash_thresh", 4)
    whitelist_mode = args.whitelist_mode or cfg.get("whitelist_mode", "mark")

    run_audit = _load_run_audit()
    run_audit(
        directory,
        text_thresh,
        img_thresh,
        output_dir,
        name_template,
        cv_preprocess,
        dedup_thresh,
        args.db_path or cfg.get("db_path"),
        args.whitelist or cfg.get("whitelist"),
        simhash_thresh,
        whitelist_mode,
    )
    return 0
