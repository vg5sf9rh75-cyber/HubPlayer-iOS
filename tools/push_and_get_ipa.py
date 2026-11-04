#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""一键：GitHub 建仓 -> API 推送工程 -> 触发云端 Mac 出 IPA -> 取回桌面。

用法（Token 从环境变量 GITHUB_TOKEN 读取，或作为第一个参数）：
    GITHUB_TOKEN=ghp_xxx python tools/push_and_get_ipa.py

只用 api.github.com（github.com 网页域名被墙也能跑通）。
产物优先从 Actions Artifact 下载；失败则回退读 ipa-delivery 分支。
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

API = "https://api.github.com"
REPO_NAME = "HubPlayer-iOS"
BRANCH = "main"
PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DESKTOP = os.path.join(os.path.expanduser("~"), "Desktop")
OUT_IPA = os.path.join(DESKTOP, "HubPlayer-unsigned.ipa")


def api(token, method, path, body=None, accept="application/vnd.github+json"):
    """返回 (status, parsed_or_bytes)。"""
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", accept)
    req.add_header("User-Agent", "hubplayer-ci")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            payload = r.read()
            if accept == "application/vnd.github.raw":
                return r.status, payload
            return r.status, (json.loads(payload) if payload else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode("utf-8", "replace")[:300]}
    except Exception as e:  # 网络层错误
        return -1, {"error": str(e)}


def list_files():
    # -z 输出以 \0 分隔且不做路径转义，兼容中文文件名
    out = subprocess.run(["git", "-c", "core.quotepath=off", "ls-files", "-z"],
                         cwd=PROJECT, capture_output=True)
    files = [f.decode("utf-8") for f in out.stdout.split(b"\0") if f.strip()]
    # 单机版不需要中继源码与其工作流，避免新仓库多跑一次 Android CI
    files = [f for f in files
             if not f.startswith("HubRelay/")
             and f != ".github/workflows/build-relay.yml"]
    # workflow 文件最后上传：前面的逐文件 commit 不会触发 CI
    files = ([f for f in files if not f.startswith(".github/workflows/")] +
             [f for f in files if f.startswith(".github/workflows/")])
    return files


def git_blob_sha(full_path):
    out = subprocess.run(["git", "hash-object", full_path],
                         cwd=PROJECT, capture_output=True, text=True)
    return out.stdout.strip()


def main():
    token = os.environ.get("GITHUB_TOKEN") or (sys.argv[1] if len(sys.argv) > 1 else "")
    if not token:
        print("缺少 Token：设置环境变量 GITHUB_TOKEN 或作为参数传入")
        sys.exit(1)

    # 0) 验证 token + 拿用户名
    st, me = api(token, "GET", "/user")
    if st != 200:
        print("Token 无效或网络失败:", st, me)
        sys.exit(1)
    owner = me["login"]
    print(f"[0/5] Token 有效，账号: {owner}")

    # 1) 建仓库（public，免费额度才能用 macOS runner）
    st, repo = api(token, "POST", "/user/repos", {
        "name": REPO_NAME,
        "private": False,
        "description": "HubPlayer iOS - SwiftUI player (live M3U / WebDAV / Quark / Bili)",
    })
    if st == 201:
        print(f"[1/5] 仓库已创建: {repo['html_url']} (public)")
    elif st == 422:
        print(f"[1/5] 仓库已存在，直接使用: https://github.com/{owner}/{REPO_NAME}")
    else:
        print("建仓失败:", st, repo)
        sys.exit(1)

    # 2) 逐文件推送（Contents API，走 api.github.com）
    files = list_files()
    print(f"[2/5] 开始上传 {len(files)} 个文件 ...")
    for i, path in enumerate(files, 1):
        full = os.path.join(PROJECT, path.replace("/", os.sep))
        from urllib.parse import quote
        qpath = quote(path)
        with open(full, "rb") as f:
            content = base64.b64encode(f.read()).decode()
        body = {
            "message": "chore: upload " + path,
            "content": content,
            "branch": BRANCH,
        }
        # 已存在且内容一致则跳过（断点续传）
        st0, old = api(token, "GET", f"/repos/{owner}/{REPO_NAME}/contents/{qpath}?ref={BRANCH}")
        if st0 == 200 and isinstance(old, dict) and old.get("sha"):
            if old.get("type") == "file" and old.get("sha") == git_blob_sha(full):
                print(f"    [{i}/{len(files)}] SKIP {path} (内容一致)")
                continue
            body["sha"] = old["sha"]
        st, resp = api(token, "PUT", f"/repos/{owner}/{REPO_NAME}/contents/{qpath}", body)
        ok = st in (200, 201)
        print(f"    [{i}/{len(files)}] {'OK ' if ok else 'FAIL '} {path} (http {st})")
        if not ok:
            print("      详情:", json.dumps(resp, ensure_ascii=False)[:300])
            sys.exit(1)

    # 3) 触发 workflow（先记录基线，避免轮询选中上传期间 push 触发的旧 run）
    st0, prev = api(token, "GET",
                    f"/repos/{owner}/{REPO_NAME}/actions/runs?branch={BRANCH}&per_page=10")
    baseline = 0
    if st0 == 200:
        baseline = max((r.get("id", 0) for r in prev.get("workflow_runs", [])), default=0)
    st, resp = api(token, "POST",
                   f"/repos/{owner}/{REPO_NAME}/actions/workflows/build-ipa.yml/dispatches",
                   {"ref": BRANCH})
    if st != 204:
        print("触发 workflow 失败（检查 token 是否勾了 workflow 权限）:", st, resp)
        sys.exit(1)
    print("[3/5] 已触发云端 macOS 编译，轮询中（一般 3-6 分钟）...")

    # 4) 轮询运行状态
    run_id = None
    deadline = time.time() + 1800
    while time.time() < deadline:
        time.sleep(15)
        st, runs = api(token, "GET",
                       f"/repos/{owner}/{REPO_NAME}/actions/runs?branch={BRANCH}&per_page=10")
        if st != 200 or not runs.get("workflow_runs"):
            continue
        # 只认本次 dispatch 产生的 iOS 编译 run（排除旧 run 与 relay 工作流）
        valid = [r for r in runs["workflow_runs"]
                 if r.get("conclusion") != "cancelled"
                 and r.get("name") == "Build iOS IPA"
                 and r.get("id", 0) > baseline]
        if not valid:
            continue
        run = valid[0]
        run_id = run["id"]
        status, concl = run["status"], run.get("conclusion")
        print(f"    run {run_id}: status={status} conclusion={concl}")
        if status == "completed":
            if concl != "success":
                stj, jobs = api(token, "GET", f"/repos/{owner}/{REPO_NAME}/actions/runs/{run_id}/jobs")
                if stj == 200:
                    for job in jobs.get("jobs", []):
                        for s in job.get("steps", []):
                            if s.get("conclusion") not in ("success", "skipped", None):
                                print(f"    失败步骤: {job['name']} / {s['name']} -> {s.get('conclusion')}")
                print("编译失败，日志: " + run["html_url"])
                sys.exit(1)
            break
    else:
        print("轮询超时（30 分钟），请手动查看 Actions 页")
        sys.exit(1)
    print("[4/5] 编译完成!")

    # 5) 取回 IPA：先试本次 run 的 Artifact，失败走 ipa-delivery 分支
    import io
    import shutil
    import zipfile

    # 清掉上一版产物，避免 Windows 上 move 到已存在文件失败 / 误交付旧包
    if os.path.exists(OUT_IPA):
        os.remove(OUT_IPA)

    st, arts = api(token, "GET",
                   f"/repos/{owner}/{REPO_NAME}/actions/runs/{run_id}/artifacts")
    downloaded = False
    if st == 200 and arts.get("artifacts"):
        mine = [a for a in arts["artifacts"]
                if a.get("name") == "HubPlayer.ipa" and not a.get("expired")]
        if mine:
            aid = mine[0]["id"]
            print(f"[5/5] 下载 Artifact id={aid} ...")
            st2, blob = api(token, "GET",
                            f"/repos/{owner}/{REPO_NAME}/actions/artifacts/{aid}/zip",
                            accept="application/vnd.github.raw")
            if st2 == 200 and blob[:2] == b"PK":
                tmp = os.path.join(DESKTOP, "_ipa_tmp")
                shutil.rmtree(tmp, ignore_errors=True)
                os.makedirs(tmp, exist_ok=True)
                with zipfile.ZipFile(io.BytesIO(blob)) as z:
                    z.extractall(tmp)
                for root, _dirs, fs in os.walk(tmp):
                    for fn in fs:
                        if fn.endswith(".ipa"):
                            shutil.move(os.path.join(root, fn), OUT_IPA)
                            downloaded = True
                            break
                    if downloaded:
                        break
                shutil.rmtree(tmp, ignore_errors=True)
    if not downloaded:
        print("    Artifact 通道不可用，回退 ipa-delivery 分支 ...")
        st, blob = api(token, "GET",
                       f"/repos/{owner}/{REPO_NAME}/contents/HubPlayer.ipa?ref=ipa-delivery",
                       accept="application/vnd.github.raw")
        if st == 200 and blob[:2] == b"PK":
            with open(OUT_IPA, "wb") as f:
                f.write(blob)
        else:
            print("取回失败:", st, str(blob)[:200])
            sys.exit(1)

    size_mb = os.path.getsize(OUT_IPA) / 1024 / 1024
    print(f"\n完成! IPA 已保存到: {OUT_IPA}  ({size_mb:.2f} MB)")
    print("下一步：Windows 上用 Sideloadly（需要 iTunes+iCloud 官网版驱动）")
    print("  1. iPhone 用数据线连电脑；2. Sideloadly 选这个 IPA，登录你的 Apple ID；3. Start 即可安装。")


if __name__ == "__main__":
    main()
