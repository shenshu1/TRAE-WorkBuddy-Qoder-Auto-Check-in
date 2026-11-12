# TRAE-WorkBuddy-Qoder 自动签到

云端自动签到 Trae、WorkBuddy 和 Qoder CN 的每日积分/credits。

## 签到时间

| 产品 | 北京时间 | 说明 |
|------|---------|------|
| WorkBuddy | 10:13 | codebuddy.cn |
| TRAE | 10:23 | api.trae.cn |
| Qoder CN | 10:33 | openapi.qoder.com.cn |

每个产品另有一次下午兜底运行。

## 文件结构

```
├── trae_checkin.py              # TRAE 签到
├── workbuddy_checkin.py         # WorkBuddy 签到
├── qoder_checkin.py             # Qoder CN 签到
├── tools/
│   ├── decrypt_trae_token.py            # TRAE token 解密（byteCrypto AES-128-CBC）
│   ├── decrypt_qoder_token.py           # Qoder token 解密（Electron safeStorage）
│   ├── sync_tokens.sh                   # 本地 token → Secrets 自动同步（macOS）
│   └── extract_workbuddy_token_cdp.js   # WorkBuddy CDP 兜底取值（需 Node 22+）
├── .github/workflows/
│   ├── trae_checkin.yml
│   ├── workbuddy_checkin.yml
│   └── qoder_checkin.yml
└── GUIDE.md
```

## 本地 token 同步

云端 workflow 只消费 Secrets，token 需要定期刷新（TRAE 约 7 天，WorkBuddy 约 28 天，Qoder 约 30 天）。macOS 上执行：

```bash
./tools/sync_tokens.sh                  # 目标仓库从 git remote 推导
GH_REPO=owner/repo ./tools/sync_tokens.sh
```

脚本会跳过已过期的 token，日志写入 `token_sync.log`（不含 token 值）。可配合 LaunchAgent 每日定时执行，详见 [GUIDE.md](GUIDE.md) 第三章。

> WorkBuddy 5.9.2 起 `workbuddy-desktop.info` 中的 token 改为加密信封，脚本优先读取 `Tencent-Cloud.coding-copilot.info` 中的明文 token。

## Secrets

| 名称 | 说明 |
|------|------|
| `TRAE_JWT` | TRAE 登录 token（约 7 天有效期） |
| `TRAE_DEVICE_ID` | TRAE 设备指纹 ID |
| `WORKBUDDY_ACCESS_TOKEN` | WorkBuddy JWT（约 28 天有效期） |
| `WORKBUDDY_UID` | WorkBuddy 用户 ID |
| `QODER_TOKEN` | Qoder CN 登录 token（约 30 天有效期） |
