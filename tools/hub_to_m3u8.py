#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Hub / TVBox 配置地址 -> 标准 M3U8 转换器
========================================
Hub 播放器（FongMi TV 二次开发）属于 CatVod/TVBox 架构：所有直播源/点播源都来自一个
「配置地址」（多行文本，每行一个源，或一个 JSON 含 lives/sites 数组）。

本工具把配置地址里的【直链型 M3U/M3U8 源】自动下载并合并成一份标准的 .m3u 播放列表，
可被 iOS 版 HubPlayer、VLC、Infuse、GSE 等任意支持 M3U 的播放器直接导入。

【爬虫型源】（type=1 / spider / liveContent 接口）无法静态提取真实播放地址，
因为真实地址需要运行 QuickJS 爬虫动态算出来。这类源会在结果里单独列出并标注，
需要配合 TVBox 运行时才能拿到地址，本工具不伪造地址。

用法：
    # 直接给配置地址（URL 或本地文件）
    python hub_to_m3u8.py "https://xxx.com/config.txt" -o hub_live.m3u

    # 只分析不下载（看有哪些可转 / 哪些需爬虫）
    python hub_to_m3u8.py "https://xxx.com/config.txt" --dry-run

    # 自带逻辑自检（无需联网）
    python hub_to_m3u8.py --self-test
"""

import argparse
import base64
import json
import os
import re
import sys
import urllib.request
import urllib.error
from urllib.parse import urljoin, urlparse


# ---------------------------------------------------------------------------
# 配置获取与解析
# ---------------------------------------------------------------------------

def fetch_text(url_or_path: str, timeout: int = 20) -> str:
    """从 URL 或本地文件读取配置文本。"""
    if os.path.isfile(url_or_path):
        with open(url_or_path, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()
    req = urllib.request.Request(url_or_path, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    # 尝试 utf-8，失败再用 gbk（部分国内源）
    for enc in ("utf-8", "gbk", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="ignore")


def maybe_b64_decode(text: str) -> str:
    """如果整段是 base64 且能解出 JSON，就返回解出的文本，否则原样返回。"""
    t = text.strip()
    if not t or t[0] in "{[":  # 已经像 JSON
        return text
    # 去掉常见包裹
    try:
        # base64 长度通常是 4 的倍数
        candidate = t
        if len(candidate) % 4 != 0:
            return text
        decoded = base64.b64decode(candidate + "=" * (-len(candidate) % 4), validate=True)
        s = decoded.decode("utf-8", errors="ignore")
        if s.strip().startswith(("{", "[")):
            return s
    except Exception:
        pass
    return text


def parse_config(text: str) -> dict:
    """
    把配置文本统一解析为结构化数据：
    返回 {"sites": [...], "lives": [...], "raw_sources": [...]}
    - 若整段是 JSON 对象（含 sites/lives），直接用；
    - 否则按行解析，每行一个源 JSON。
    """
    text = maybe_b64_decode(text)
    result = {"sites": [], "lives": [], "raw_sources": []}

    stripped = text.strip()
    # 情况 A：整段就是一个 JSON 对象
    if stripped.startswith("{"):
        try:
            root = json.loads(stripped)
            if isinstance(root, dict):
                result["sites"] = root.get("sites") or []
                result["lives"] = root.get("lives") or []
                # 兼容「多仓」store 结构
                for store in (root.get("stores") or []):
                    if isinstance(store, dict):
                        result["sites"].extend(store.get("sites") or [])
                        result["lives"].extend(store.get("lives") or [])
                return result
        except json.JSONDecodeError:
            pass

    # 情况 B：多行，每行一个源（或每行可能是某个源的 JSON）
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # 单行的 JSON 对象
        if line.startswith("{"):
            try:
                obj = json.loads(line)
                if isinstance(obj, dict):
                    result["raw_sources"].append(obj)
                    continue
            except json.JSONDecodeError:
                pass
        # 形如 key<<<url 或 key,,,url 的旧式订阅（TVBox 兼容格式）
        # 例："小明直播,,,https://x.com/live.m3u"
        m = re.match(r'^([^<,]+?)\s*(?:<<<|,,|,,,)\s*(https?://\S+)', line)
        if m:
            result["raw_sources"].append({
                "name": m.group(1).strip(),
                "type": 3,
                "url": m.group(2).strip(),
            })
            continue
        # 其余当作裸 URL
        if re.match(r'^https?://\S+\.(m3u8?|txt)(\?.*)?$', line, re.IGNORECASE):
            result["raw_sources"].append({"name": "源", "type": 3, "url": line})
    return result


# ---------------------------------------------------------------------------
# 源分类
# ---------------------------------------------------------------------------

def is_live_direct(lv: dict) -> bool:
    """lives 中 type=0 是直链 M3U（url 直接是频道列表，可能由 .php 等代理动态生成、
    不一定带 .m3u 后缀）；type=1 是爬虫直播，需要运行时。"""
    typ = lv.get("type")
    return typ in (0, "0")


def is_site_direct(st: dict) -> bool:
    """sites 中只有 url 明确指向 .m3u/.m3u8/.txt 文件才算直链；
    type=3 的 csp_ 自定义爬虫（api 是类名）不算直链，需要 Hub/TVBox 运行时。"""
    url = (st.get("url") or "").strip()
    return bool(url) and re.search(r"\.(m3u8?|txt)(\?|$)", url, re.IGNORECASE) is not None


def collect_direct_urls(cfg: dict) -> list:
    """收集所有『真正可静态提取』的直链源：lives 直链 + sites 文件直链 + 裸 M3U url。"""
    out = []
    # lives：type=0 即为可静态提取的直链直播源
    for lv in (cfg.get("lives") or []):
        if isinstance(lv, dict) and is_live_direct(lv):
            url = (lv.get("url") or "").strip()
            if url:
                out.append((lv.get("name") or lv.get("key") or "直播", url))
    # sites：只有 url 明确是 M3U 文件的才算直链（csp 自定义爬虫 type=3 不算）
    for st in (cfg.get("sites") or []):
        if isinstance(st, dict) and is_site_direct(st):
            out.append((st.get("name") or st.get("key") or "点播", (st.get("url") or "").strip()))
    # raw_sources：裸 M3U 链接
    for rs in (cfg.get("raw_sources") or []):
        if isinstance(rs, dict):
            for key in ("url", "api"):
                u = (rs.get(key) or "").strip()
                if u and re.search(r"\.(m3u8?|txt)(\?|$)", u, re.IGNORECASE):
                    out.append((rs.get("name") or rs.get("key") or "源", u))
                    break
    return [(n, u) for n, u in out if u]


def collect_spider_sources(cfg: dict) -> list:
    """收集需要爬虫/运行时才能解析的源（lives type!=0、sites 的 csp/API、非直链 raw）。"""
    out = []
    for lv in (cfg.get("lives") or []):
        if isinstance(lv, dict) and not is_live_direct(lv):
            out.append((lv.get("name") or lv.get("key") or "直播", lv.get("type")))
    for st in (cfg.get("sites") or []):
        if isinstance(st, dict) and not is_site_direct(st):
            out.append((st.get("name") or st.get("key") or "点播", st.get("type")))
    for rs in (cfg.get("raw_sources") or []):
        if isinstance(rs, dict):
            u = (rs.get("url") or rs.get("api") or "").strip()
            if not (u and re.search(r"\.(m3u8?|txt)(\?|$)", u, re.IGNORECASE)):
                out.append((rs.get("name") or rs.get("key") or "源", rs.get("type")))
    return out


# ---------------------------------------------------------------------------
# M3U 下载与合并
# ---------------------------------------------------------------------------

def fetch_m3u(url: str, timeout: int = 25) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read()
    for enc in ("utf-8", "gbk", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="ignore")


def normalize_m3u(content: str, base_url: str, group: str) -> list:
    """
    解析一个 M3U 文本，返回 [(title, absolute_url)]，并把相对地址补全、
    统一加上 #EXTGRP 分组（源名字）。
    """
    entries = []
    pending_title = ""
    pending_attrs = ""
    for line in content.splitlines():
        line = line.rstrip("\r")
        if line.startswith("#EXTINF"):
            # 提取标题（逗号后）和可能存在的 tvg/group 信息
            if "," in line:
                pending_title = line.split(",", 1)[1].strip()
            else:
                pending_title = ""
            pending_attrs = line  # 保留整行属性
        elif line.startswith("#"):
            # 其它指令行（如 #EXTGRP、#EXT-X-...）忽略，稍后统一重写
            continue
        elif line.strip() == "":
            continue
        else:
            # 这是一个播放地址
            url = line.strip()
            if not url.startswith("http"):
                url = urljoin(base_url, url)
            entries.append((pending_title or "未命名", url, pending_attrs))
            pending_title = ""
            pending_attrs = ""
    return entries


def build_m3u(entries_by_group: list) -> str:
    """把 [(group, title, url)] 组装成标准 M3U 文本。"""
    lines = ["#EXTM3U"]
    for group, title, url in entries_by_group:
        lines.append(f'#EXTINF:-1 group-title="{group}",{title}')
        lines.append(url)
    return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------

def run(config_arg: str, out_path: str, dry_run: bool, timeout: int) -> int:
    print(f"[*] 读取配置：{config_arg}")
    try:
        text = fetch_text(config_arg, timeout)
    except Exception as e:
        print(f"[!] 无法读取配置：{e}")
        return 2
    cfg = parse_config(text)
    n_lives = len(cfg.get("lives") or [])
    n_sites = len(cfg.get("sites") or [])
    n_raw = len(cfg.get("raw_sources") or [])
    print(f"[*] 解析完成：lives={n_lives} sites={n_sites} 单行源={n_raw}")

    direct = collect_direct_urls(cfg)
    spider = collect_spider_sources(cfg)
    print(f"[*] 直链型（可转 M3U8）源：{len(direct)} 个")
    print(f"[*] 爬虫/API 型（需 TVBox 运行时，无法静态提取）：{len(spider)} 个")

    for name, typ in spider:
        print(f"    - [需运行时] {name} (type={typ})")
    print()

    if dry_run:
        for name, url in direct:
            print(f"    [可转] {name}: {url}")
        print("\n[*] dry-run 完成，未下载。去掉 --dry-run 即可生成 M3U。")
        return 0

    if not direct:
        print("[!] 没有发现可直接提取的直链型 M3U 源。")
        print("    这通常意味着你的配置全部是爬虫/API 型（type=1），")
        print("    真实播放地址需要 Hub/TVBox 运行时动态算出，无法静态转成 M3U8。")
        return 0

    all_entries = []
    failed = []
    for name, url in direct:
        try:
            print(f"[*] 下载源「{name}」: {url}")
            content = fetch_m3u(url, timeout)
            if "#EXTM3U" not in content.upper():
                print(f"    ! 内容不像 M3U（无 #EXTM3U），已跳过：{url}")
                failed.append((name, url, "非 M3U 内容"))
                continue
            entries = normalize_m3u(content, url, name)
            print(f"    + 解析到 {len(entries)} 个频道")
            all_entries.extend([(name, t, u) for (t, u, _) in entries])
        except Exception as e:
            print(f"    ! 下载失败：{e}")
            failed.append((name, url, str(e)))

    if not all_entries:
        print("[!] 所有直链源都没能成功解析出频道。")
        return 0

    m3u = build_m3u(all_entries)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(m3u)
    print(f"\n[✓] 已生成标准 M3U 播放列表：{out_path}")
    print(f"    总频道数：{len(all_entries)}，来源组数：{len(set(e[0] for e in all_entries))}")
    if failed:
        print(f"    失败源：{len(failed)} 个（见上方 ! 标记）")
    print("\n[>] 在 iOS 版 HubPlayer 的「设置」里添加此 .m3u 地址即可订阅；")
    print("    也可直接把文件 AirDrop 到 iPhone 用 VLC/Infuse 打开。")
    return 0


# ---------------------------------------------------------------------------
# 自检（无需联网）
# ---------------------------------------------------------------------------

SAMPLE_STRUCTURED = json.dumps({
    "lives": [
        {"name": "直链直播", "type": 0, "url": "https://live.example.com/tv.m3u8"},
        {"name": "爬虫直播", "type": 1, "url": "https://spider.example.com/"}
    ],
    "sites": [
        {"name": "直链点播", "type": 3, "url": "https://vod.example.com/list.m3u"},
        {"name": "API点播", "type": 1, "api": "https://api.example.com/provide/vod/"},
        {"name": "爬虫点播", "type": 3, "api": "csp_FooGuard"}
    ]
}, ensure_ascii=False)

SAMPLE_MULTILINE = "\n".join([
    "# 备注行",
    '{"name":"单行直链","type":3,"url":"https://a.example.com/x.m3u8"}',
    '小明直播,,,https://b.example.com/live.m3u',
])

SAMPLE_M3U = """#EXTM3U
#EXTINF:-1 tvg-name="CCTV1" group-title="央视",CCTV-1 综合
/cctv1.m3u8
#EXTINF:-1,CCTV-2
https://live.example.com/cctv2.m3u8
"""


def self_test() -> int:
    print("[*] 自检：结构化配置解析")
    cfg = parse_config(SAMPLE_STRUCTURED)
    direct = collect_direct_urls(cfg)
    spider = collect_spider_sources(cfg)
    assert len(direct) == 2, f"直链数应为2，实际{len(direct)}"
    assert len(spider) == 3, f"爬虫数应为3，实际{len(spider)}"
    print(f"    OK 直链={len(direct)} 爬虫={len(spider)}")

    print("[*] 自检：多行/旧式订阅解析")
    cfg2 = parse_config(SAMPLE_MULTILINE)
    direct2 = collect_direct_urls(cfg2)
    assert len(direct2) == 2, f"直链数应为2，实际{len(direct2)}"
    print(f"    OK 直链={len(direct2)}")

    print("[*] 自检：M3U 归一化（相对地址补全 + 分组）")
    entries = normalize_m3u(SAMPLE_M3U, "https://live.example.com/", "测试组")
    # 第一个是相对地址 /cctv1.m3u8 -> 补全为 https://live.example.com/cctv1.m3u8
    assert entries[0][1] == "https://live.example.com/cctv1.m3u8", entries[0]
    assert "CCTV-1" in entries[0][0], entries[0]
    print(f"    OK 解析到 {len(entries)} 个频道，相对地址已补全")

    print("[*] 自检：base64 包裹配置")
    b64 = base64.b64encode(SAMPLE_STRUCTURED.encode("utf-8")).decode()
    cfg3 = parse_config(b64)
    assert len(collect_direct_urls(cfg3)) == 2
    print("    OK base64 解码成功")

    print("\n[✓] 全部自检通过。脚本逻辑可用，给它一个真实配置地址即可产出 M3U。")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Hub/TVBox 配置地址 -> 标准 M3U8 转换器")
    ap.add_argument("config", nargs="?", help="配置地址 URL 或本地 .txt/.json 文件路径")
    ap.add_argument("-o", "--out", default="hub_live.m3u", help="输出 M3U 文件路径（默认 hub_live.m3u）")
    ap.add_argument("--dry-run", action="store_true", help="只分析源、不下载生成")
    ap.add_argument("--timeout", type=int, default=25, help="网络超时秒数")
    ap.add_argument("--self-test", action="store_true", help="运行内置逻辑自检（不联网）")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not args.config:
        ap.print_help()
        return 1
    return run(args.config, args.out, args.dry_run, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
