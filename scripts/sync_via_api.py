#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""通过 GitHub REST Git Data API 把本地工程同步到远端。

用途：本机 HTTPS 代理会拦截 git smart-http（CONNECT tunnel 502 / schannel
close_notify），但 api.github.com 的 REST 调用正常。因此在无法使用
`git push` 的环境下，用本脚本上传完整 tree 并推进 refs/heads/main。

安全性：Token 只从环境变量 GITHUB_TOKEN 读取，不写入任何文件、不打印。
HTTP 请求统一交给 curl 子进程（复用系统代理与证书配置）。

用法：
    GITHUB_TOKEN=<pat> GITHUB_REPO=owner/repo python3 scripts/sync_via_api.py
"""
from __future__ import annotations

import base64
import json
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
REPO = os.environ.get("GITHUB_REPO", "mxr111/hmusicios")
TOKEN = os.environ.get("GITHUB_TOKEN")
BRANCH = os.environ.get("GITHUB_BRANCH", "main")
COMMIT_MESSAGE = os.environ.get(
    "SYNC_MESSAGE",
    "MuyuIOS: iOS 27 SwiftUI project (REA-based Huawei Music client)",
)

if not TOKEN:
    sys.exit("错误：环境变量 GITHUB_TOKEN 未设置")

API = f"https://api.github.com/repos/{REPO}"


def curl(method: str, path: str, payload=None):
    """调用 REST API，返回 (http_code, parsed_json)。"""
    cmd = [
        "curl", "-sS", "--max-time", "90",
        "-w", "\n__HTTP__%{http_code}",
        "-X", method,
        "-H", f"Authorization: Bearer {TOKEN}",
        "-H", "Accept: application/vnd.github+json",
        "-H", "X-GitHub-Api-Version: 2022-11-28",
    ]
    body = None
    if payload is not None:
        cmd += ["-H", "Content-Type: application/json", "--data-binary", "@-"]
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    cmd.append(path if path.startswith("http") else API + path)
    proc = subprocess.run(cmd, input=body, capture_output=True)
    out = proc.stdout.decode("utf-8", "replace")
    if "\n__HTTP__" not in out:
        raise RuntimeError(
            "curl 调用失败: " + proc.stderr.decode("utf-8", "replace")[:300]
            + " :: " + out[:300]
        )
    raw, code = out.rsplit("\n__HTTP__", 1)
    try:
        data = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        data = {"_raw": raw[:300]}
    return int(code.strip()), data


def git(*args, binary: bool = False):
    proc = subprocess.run(
        ["git", *args], cwd=str(ROOT), capture_output=True, check=False
    )
    if proc.returncode != 0:
        raise RuntimeError(
            "git " + " ".join(args) + " 失败: "
            + proc.stderr.decode("utf-8", "replace")[:300]
        )
    return proc.stdout if binary else proc.stdout.decode("utf-8", "replace")


def check(code, data, what, allowed=(200, 201)):
    if code not in allowed:
        raise RuntimeError(f"{what} 失败: HTTP {code} {data.get('message', data)}")


def main():
    print(f"目标仓库: {REPO}  分支: {BRANCH}")
    code, repo = curl("GET", "")
    check(code, repo, "读取仓库信息")
    print(f"仓库状态: private={repo.get('private')} default_branch={repo.get('default_branch')}")

    # --- 1. 确保分支存在。空仓库的 Git Data API 会返回 409，
    #        必须先用 Contents API 写入一个文件来初始化 refs/heads/main。
    code, ref = curl("GET", f"/git/ref/heads/{BRANCH}")
    # 空仓库在不同 GitHub 版本上可能返回 404，也可能返回 409 "Git Repository is empty."
    needs_init = code == 404 or (
        code == 409 and "empty" in str(ref.get("message", "")).lower()
    )
    if needs_init:
        seed = (ROOT / "README.md").read_bytes()
        code, created = curl("PUT", "/contents/README.md", {
            "message": "Initialize repository",
            "content": base64.b64encode(seed).decode("ascii"),
            "branch": BRANCH,
        })
        check(code, created, "初始化 main 分支（Contents API）")
        parent = created["commit"]["sha"]
        print(f"已初始化 main，初始提交: {parent[:12]}")
    else:
        check(code, ref, "读取远端分支引用")
        parent = ref["object"]["sha"]
        print(f"远端已有提交: {parent[:12]}")

    # --- 2. 上传所有 blob。blob 的 sha 由内容决定，必须与本地一致。
    tree_lines = git("ls-tree", "-r", "--full-tree", "HEAD").splitlines()
    entries = []
    for line in tree_lines:
        meta, path = line.split("\t", 1)
        mode, obj_type, sha = meta.split()
        if obj_type != "blob":
            continue
        content = git("cat-file", "blob", sha, binary=True)
        code, blob = curl("POST", "/git/blobs", {
            "content": base64.b64encode(content).decode("ascii"),
            "encoding": "base64",
        })
        check(code, blob, f"上传 blob {path}")
        if blob.get("sha") != sha:
            raise RuntimeError(f"blob 哈希不一致: {path} local={sha} remote={blob.get('sha')}")
        entries.append({"path": path, "mode": mode, "type": "blob", "sha": sha})
    print(f"已上传 {len(entries)} 个文件对象，哈希全部与本地一致")

    # --- 3. 用完整文件清单创建一棵树（GitHub 自动构造嵌套目录）。
    code, tree = curl("POST", "/git/trees", {"tree": entries})
    check(code, tree, "创建 tree")
    print(f"tree: {tree['sha'][:12]}")

    # --- 4. 创建提交，父提交指向远端当前 HEAD（fast-forward）。
    code, commit = curl("POST", "/git/commits", {
        "message": COMMIT_MESSAGE,
        "tree": tree["sha"],
        "parents": [parent],
    })
    check(code, commit, "创建 commit")
    new_sha = commit["sha"]
    print(f"commit: {new_sha[:12]}")

    # --- 5. 推进分支引用。这次 push 事件会触发 GitHub Actions。
    code, updated = curl("PATCH", f"/git/refs/heads/{BRANCH}", {
        "sha": new_sha, "force": False,
    })
    check(code, updated, "更新分支引用")
    print(f"refs/heads/{BRANCH} -> {new_sha}")

    # --- 6. 校验远端树与本地 HEAD 完全一致。
    code, remote_tree = curl("GET", f"/git/trees/{new_sha}?recursive=1")
    check(code, remote_tree, "读取远端 tree")
    if remote_tree.get("truncated"):
        raise RuntimeError("远端 tree 被截断，校验不可靠")
    remote_files = {e["path"] for e in remote_tree["tree"] if e["type"] == "blob"}
    local_files = {line.split("\t", 1)[1] for line in tree_lines}
    missing = local_files - remote_files
    extra = remote_files - local_files
    if missing or extra:
        raise RuntimeError(f"文件不一致: 缺失={sorted(missing)} 多余={sorted(extra)}")
    print(f"校验通过: 远端 {len(remote_files)} 个文件与本地 HEAD 完全一致")

    # --- 7. 确认 Actions 是否已感知这次 push。
    code, runs = curl("GET", "/actions/runs?per_page=3")
    if code == 200:
        items = runs.get("workflow_runs", [])
        print(f"Actions runs: {runs.get('total_count', 0)} 个")
        for r in items[:3]:
            print(f"  #{r.get('run_number')} {r.get('name')} status={r.get('status')} "
                  f"conclusion={r.get('conclusion')} url={r.get('html_url')}")
    else:
        print(f"Actions runs 查询: HTTP {code}（可能尚未启用）")

    print("同步完成")
    print(f"仓库地址: https://github.com/{REPO}")
    print(f"提交地址: https://github.com/{REPO}/commit/{new_sha}")


if __name__ == "__main__":
    main()
