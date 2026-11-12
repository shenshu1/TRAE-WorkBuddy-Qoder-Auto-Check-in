#!/bin/bash
# 把本机最新的 TRAE / WorkBuddy / Qoder token 推送到 GitHub Actions Secrets。
# 幂等：每次覆盖同名 Secret；读取失败只记日志，不重试，避免反复触发风控。
#
# 用法：
#   ./tools/sync_tokens.sh                    # 目标仓库从 git remote origin 推导
#   GH_REPO=owner/repo ./tools/sync_tokens.sh # 显式指定目标仓库
#
# 可选环境变量：
#   GH_REPO      目标仓库，默认从 git remote 推导
#   PYTHON_BIN   Python 解释器，默认 python3
#   NODE_BIN     Node 解释器（CDP 兜底用），默认 node
#   WB_AUTH_DIR  WorkBuddy 登录态目录，默认 macOS 标准路径
#   HTTPS_PROXY  需要代理时自行 export，例如 http://127.0.0.1:7890

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG="$PROJECT/token_sync.log"

PYTHON_BIN="${PYTHON_BIN:-python3}"
NODE_BIN="${NODE_BIN:-node}"
WB_AUTH_DIR="${WB_AUTH_DIR:-$HOME/Library/Application Support/CodeBuddyExtension/Data/Public/auth}"

# launchd / cron 环境的 PATH 往往缺少 Homebrew 与 gh
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
unset PYTHONHOME PYTHONPATH

REPO="${GH_REPO:-}"
if [ -z "$REPO" ]; then
    REPO=$(git -C "$PROJECT" remote get-url origin 2>/dev/null \
        | sed -E 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')
fi
if [ -z "$REPO" ]; then
    echo "ERROR 无法确定目标仓库，请设置 GH_REPO=owner/repo" >&2
    exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR 找不到 gh，请先安装并 gh auth login" >&2
    exit 1
fi

exec >> "$LOG" 2>&1

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始同步 → $REPO"

# WorkBuddy token 来源优先级：
#   1. Tencent-Cloud.coding-copilot.info 明文 accessToken（5.9.2 起桌面端仍写明文，主路径）
#   2. workbuddy-desktop.info 明文 accessToken（旧版本格式）
#   3. CDP 调试端口（前两者都读不到时，需 WorkBuddy 以 --remote-debugging-port 启动）
# 5.9.2 起 workbuddy-desktop.info 中的 token 会被写成 $wbEncrypted 加密信封，无法直接读取。
WB_TOKEN=$("$PYTHON_BIN" - "$WB_AUTH_DIR/Tencent-Cloud.coding-copilot.info" "$WB_AUTH_DIR/workbuddy-desktop.info" <<'PY' 2>/dev/null
import base64, datetime, json, sys

for path in sys.argv[1:]:
    try:
        token = json.load(open(path))['auth']['accessToken']
    except Exception:
        continue
    if not isinstance(token, str) or not token.startswith('eyJ') or token.count('.') != 2:
        continue
    try:
        body = token.split('.')[1]
        body += '=' * (-len(body) % 4)
        exp = json.loads(base64.urlsafe_b64decode(body)).get('exp', 0)
    except Exception:
        exp = 0
    if exp and exp < datetime.datetime.now().timestamp():
        continue
    print(token)
    sys.exit(0)
PY
)

if [ -z "$WB_TOKEN" ] && curl -s --max-time 2 "http://127.0.0.1:${WB_CDP_PORT:-9222}/json/version" >/dev/null 2>&1; then
    WB_TOKEN=$("$NODE_BIN" "$PROJECT/tools/extract_workbuddy_token_cdp.js" "${WB_CDP_PORT:-9222}" 2>/dev/null)
    [ -n "$WB_TOKEN" ] && echo "[$(date '+%Y-%m-%d %H:%M:%S')] 通过 CDP 调试端口获取 WorkBuddy token"
fi

if [ -n "$WB_TOKEN" ]; then
    if printf '%s' "$WB_TOKEN" | gh secret set WORKBUDDY_ACCESS_TOKEN --repo "$REPO" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WORKBUDDY_ACCESS_TOKEN 已更新（${#WB_TOKEN} 字符）"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR WORKBUDDY_ACCESS_TOKEN 推送失败"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR 读取 WorkBuddy token 失败（三个来源均不可用，签到会中断，请检查 WorkBuddy 是否已登录）"
fi

# TRAE：byteCrypto 解密后的 JWT
TRAE_TOKEN=$("$PYTHON_BIN" "$PROJECT/tools/decrypt_trae_token.py" --stdout 2>/dev/null | tail -1)
if [ -n "$TRAE_TOKEN" ]; then
    if printf '%s' "$TRAE_TOKEN" | gh secret set TRAE_JWT --repo "$REPO" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] TRAE_JWT 已更新（${#TRAE_TOKEN} 字符）"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR TRAE_JWT 推送失败（网络不通？）"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR 解密 TRAE token 失败（客户端未登录？）"
fi

# Qoder CN：Electron safeStorage 解密后的 token
QODER_TOKEN=$("$PYTHON_BIN" "$PROJECT/tools/decrypt_qoder_token.py" --stdout 2>/dev/null | tail -1)
if [ -n "$QODER_TOKEN" ]; then
    if printf '%s' "$QODER_TOKEN" | gh secret set QODER_TOKEN --repo "$REPO" 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] QODER_TOKEN 已更新（${#QODER_TOKEN} 字符）"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR QODER_TOKEN 推送失败（网络不通？）"
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR 解密 Qoder token 失败（客户端未登录？）"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] 同步结束"
