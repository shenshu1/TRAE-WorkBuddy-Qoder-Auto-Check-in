#!/usr/bin/env node
// 通过 Chrome DevTools Protocol 从运行中的 WorkBuddy 取 access token。
// 用法: node tools/extract_workbuddy_token_cdp.js [port]
// 前置: WorkBuddy 需带 --remote-debugging-port=9222 启动。
// 依赖: Node 22+（使用内置 WebSocket，无需 npm install）。

const http = require('http');

const port = process.argv[2] || 9222;

function getTargets() {
  return new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${port}/json`, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(e);
        }
      });
    }).on('error', reject);
  });
}

function evalInTarget(wsUrl, expression) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error('timeout'));
    }, 10000);

    ws.onopen = () => {
      ws.send(JSON.stringify({
        id: 1,
        method: 'Runtime.evaluate',
        params: { expression, returnByValue: true, awaitPromise: true },
      }));
    };

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      if (msg.id !== 1) return;
      clearTimeout(timer);
      ws.close();
      if (msg.result && msg.result.result && msg.result.result.value !== undefined) {
        resolve(msg.result.result.value);
      } else if (msg.result && msg.result.exceptionDetails) {
        reject(new Error(msg.result.exceptionDetails.text || 'Evaluation error'));
      } else {
        reject(new Error('Unexpected CDP response'));
      }
    };

    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error('WebSocket error'));
    };
  });
}

async function main() {
  const targets = await getTargets();
  const page =
    targets.find((t) => t.type === 'page' && t.title === 'WorkBuddy') ||
    targets.find((t) => t.type === 'page');

  if (!page) {
    console.error('Error: 未找到可用的 WorkBuddy 页面目标');
    console.error('Available targets:', targets.map((t) => `${t.type}: ${t.title}`).join(', '));
    process.exit(1);
  }

  const token = await evalInTarget(
    page.webSocketDebuggerUrl,
    `(async () => await window.__GENIE_DEFAULT_APP_PROVIDERS__.auth.getToken())()`
  );

  if (typeof token === 'string' && token.startsWith('eyJ')) {
    process.stdout.write(token);
    return;
  }
  console.error('Error: 拿到的不是 JWT:', typeof token, String(token).slice(0, 100));
  process.exit(1);
}

main().catch((e) => {
  console.error('Error:', e.message);
  process.exit(1);
});
