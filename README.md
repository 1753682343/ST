# CloudflareSpeedTest Top 5 发布器

这个小仓库只做一件事：在**你的电脑和你的网络环境**中运行
[CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)，从测速结果中取下载速度排名前 5 且无丢包的 IPv4 地址，生成可被 Raw GitHub 链接直接读取的节点列表，并提交到你的仓库。

> 不建议把测速放到 GitHub Actions 里跑。GitHub Runner 的网络位置不是你自己的网络，测出的优选 IP 对你通常没有参考价值。

## 输出

脚本会更新以下文件：

- `public/cf-top5.txt`：一行一个 `IP:443`，适合供脚本或订阅模板读取。
- `public/cf-top5.json`：带测速指标的结构化结果，便于检查。

例如：

```text
104.27.200.69:443
172.67.60.78:443
```

## 首次准备

1. 在 GitHub 新建一个**私有仓库**，把本目录全部上传进去，或在本目录运行：

   ```powershell
   git init
   git branch -M main
   git add .
   git commit -m "Initialize Cloudflare Top 5 publisher"
   git remote add origin https://github.com/<你的用户名>/<你的仓库名>.git
   git push -u origin main
   ```

2. 从 [CloudflareSpeedTest Releases](https://github.com/XIU2/CloudflareSpeedTest/releases) 下载 Windows 版本，解压后把 `cfst.exe` 和同目录的 `ip.txt` 放到本仓库的 `cfst` 文件夹中。

3. Windows 安装 Git，并确保 PowerShell 中可使用 `git`。本脚本无需 Python。

## 每次更新

在仓库根目录打开 PowerShell，运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\publish-top5.ps1 -CfstPath .\cfst\cfst.exe
```

它会依次执行：测速 → 选出前 5 → 写入 `public` → `git commit` → `git push`。

可选参数：

```powershell
# 把最大延迟改为 200 ms，单个下载测速延长到 8 秒
.\publish-top5.ps1 -CfstPath .\cfst\cfst.exe -LatencyLimit 200 -DownloadTestSeconds 8

# 只生成文件，确认内容后再自己提交
.\publish-top5.ps1 -CfstPath .\cfst\cfst.exe -NoPush
```

## 获取 Raw 地址

推送成功后，地址格式为：

```text
https://raw.githubusercontent.com/<你的用户名>/<你的仓库名>/main/public/cf-top5.txt
```

这个文本只有 5 个 `IP:443`，不包含你的订阅链接、UUID、密钥或任何节点凭据。若仓库为私有仓库，Raw 链接不能匿名读取；给外部程序使用时需改用安全的认证方式，或由该程序读取仓库内容。

## ECH 使用提醒

这些只是 Cloudflare IP，不能单独构成代理节点。你的代理配置仍需保留原有协议、端口、UUID/密码等信息，仅把出站服务器地址依次替换为这里的 IP；TLS Server Name 和 ECH 相关域名应继续使用服务端要求的值，而不是改成 IP。

