# dsh-launcher-macOS


macOS 上把「**本地服务 + Safari 独立窗口**」变成 **Dock 一键启动**的启动器。

默认适配 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`@deepseek-ai/dsh`），改几行配置即可适配任意本地 Web 服务。

## 它解决什么问题

很多本地工具（AI 工作台、开发服务器、自建面板）的启动方式是"跑一条命令，然后在浏览器打开一个地址"。在 macOS 上这会带来三个烦人问题：

1. **打扰你的浏览器**：新窗口开在你全屏的 Safari/Chrome 里，打断手头的事；
2. **关不干净**：窗口关了，后台服务、渲染进程还挂在内存里；
3. **地址会变**：很多服务每次启动生成带 token 的随机地址，"添加到程序坞"的固定窗口根本指不准。

dsh-launcher 把这三件事一次解决。

## 效果

- **点 Dock 图标** → 约 6 秒：服务起来了，一个**独立窗口**弹出（你的默认浏览器完全不受打扰）；
- **再点一下** → 把窗口带到前台（不刷新页面）；
- **Cmd+Q 关窗** → 3 秒内服务、跳板、窗口、渲染进程**全部退出，零残留**;
- 服务崩溃或启动器中断时，守卫进程负责善后清理。

## 工作原理

```
点 Dock 图标
    │
[launcher 脚本]                     ← 你放进 Dock 的启动器
    │ ① 起服务（独立进程组；--no-open 绝不打开浏览器）
    ▼
[本地服务 127.0.0.1:<端口>]          ← 如 dsh web，每次启动生成带 token 的新 URL
    │ ② 从日志里抓出带 token 的 URL
    │ ③ 起一个固定端口的 302 跳板
    ▼
[跳板 127.0.0.1:3099] ──302──▶ 服务当前 URL   ← 让窗口地址可以"永远不变"
    │ ④ 打开 WebApp 窗口（指向 3099）
    ▼
[Safari WebApp 独立窗口]             ← 「添加到程序坞」生成的网页应用壳
    │ ⑤ 守卫进程每 2 秒盯一次：窗口关/服务死 → 全量清理
```

三根支柱：

- **固定端口跳板**：服务 URL 每次都变，但窗口壳的地址写死在 3099；302 跳板永远把它导向当前 URL。
- **进程组**：服务用 `setpgrp` 起在独立进程组里，退出时按组灭杀整棵树（`npx → npm → node → 子孙`一个不漏），这是"零残留"的关键。
- **独立守卫**：点完图标，启动器本体立即退出（app 恢复"未运行"，保证**每次点击都有响应**）；守候交给跑在 app 外的后台进程，窗口一关就清场。

## 安装（以 dsh 为例）

**1. 准备 Node.js**

```bash
node -v   # 没有的话先装：https://nodejs.org 或 brew install node
```

**2. 下载本仓库**

```bash
git clone https://github.com/lioswift/dsh-launcher-macOS.git ~/Documents/dsh-launcher
cd ~/Documents/dsh-launcher
```

**3. 创建 Safari WebApp 壳**（一次性）

先把手动把服务和一个临时跳板跑起来：

```bash
# 终端 A：起服务（记下它打印的 http://127.0.0.1:3080/?token=... 这一串）
npx -y @deepseek-ai/dsh web --no-open --port 3080

# 终端 B：起临时跳板（把上一行打印的 URL 填进 DSH_URL）
DSH_URL='http://127.0.0.1:3080/?token=替换成你的' node -e \
  "require('http').createServer((q,s)=>{s.writeHead(302,{Location:process.env.DSH_URL});s.end()}).listen(3099,'127.0.0.1')"
```

然后 **Safari 打开 `http://127.0.0.1:3099`** → 菜单栏 **文件 → 添加到程序坞…** → 命名 `DSH`。

完成后 `~/Applications/DSH.app` 就是你的窗口壳（把终端 A、B 都 Ctrl+C 关掉）。

> 关键：添加时的地址必须是 **3099**（跳板），不是服务的动态地址——这样以后 token 变了也能自动跟上。

**4. 生成启动器并放进 Dock**

```bash
# 有图标的话带上图标（png 或 icns），没有就去掉第三个参数
./make-app.sh "$HOME/Applications/dsh 启动器.app" ./dsh-launcher ~/Downloads/deep.png
```

打开 `~/Applications`，把 **dsh 启动器.app** 拖进 Dock，完成！

**5. 日常使用**

点图标启动；关窗全清。就这些。

## 适配其他本地服务

编辑 `dsh-launcher` 顶部配置区：

| 配置项 | 说明 |
|---|---|
| `APP_NAME` | 显示名（通知里用） |
| `SVC_CMD` | 起服务的命令（脚本会自动追加 `--port <端口>`） |
| `SVC_SIG` | 识别"本启动器起的服务进程"的 ps 特征（用于清孤儿） |
| `PREFERRED_PORT` | 服务首选端口（被占会自动换空闲端口） |
| `RPORT` | 跳板端口（WebApp 壳指向它） |
| `WEBAPP_APP` | WebApp 壳路径 |
| `WORKDIR` | 工作目录（状态/日志/守卫） |

适配要求只有一条：**服务需要把 `http://127.0.0.1:<port>/...` 形式的地址打印到输出**（脚本靠它抓 URL）。大多数本地 dev server 天然就打印。

## 踩坑记录（如果你想做类似的东西）

这些坑都是真实踩出来的，很多反直觉：

- **Dock 条目的 `book` 书签字段**：用命令行改 Dock 配置时，条目里还有一份 712 字节的书签数据（`book`）指向原 app。只改路径字段没用——macOS 会在 webapp 启停时按书签把条目"纠正"回去（表现为图标忽明忽暗/点错东西）。要么清掉 `book` 让系统重建，要么最省事：**手动把 app 拖进 Dock**（系统原生添加，一劳永逸）。
- **Safari WebApp 的模板 icns 不能给普通 app 用**：直接拷贝 WebApp 壳的 `ApplicationIcon.icns`，普通 app 在 Dock 里会渲染空白。用 `sips` + `iconutil` 从 png 生成标准 icns（`make-app.sh` 已内置）。
- **`osascript` 判断 `application ... is running` 对刚退出的 app 有约 10 秒延迟**：用它做"窗口关了没"的判据，清理会迟 10 秒。改用纯进程检测（瞬时）。
- **只 `kill` 顶层进程会漏杀子孙**：`npx` 只是壳，真正的服务在 `npm exec → node` 里。用 `perl -e 'setpgrp(0,0); exec @ARGV'` 让整棵树同组，退出时 `kill -- -PGID` 连根拔。
- **启动瞬间的竞态**：`setpgrp` 生效前，进程组还不存在——检测逻辑要"组或 PID 任一存活即算活"。
- **`WebKit.WebContent` 渲染进程的 ppid 恒为 1**（XPC 服务），不是普通子进程，没有父子关系可查。识别它的办法是 `lsof` 看它打开的文件里有没有 WebApp 容器的 UUID。
- **守卫进程不能跑在 app bundle 里**：macOS 会把 bundle 内的任何进程算作"app 正在运行"，导致后续点击 Dock 图标被吞掉（只激活不执行）。从 app 外的脚本副本跑才行。
- **别用 `pkill -f <UUID>` 宽匹配**：会误杀任何命令行恰好含该 UUID 的进程（包括调试命令自己）。
- **从 Dock 启动的进程 PATH 极贫瘠**：不加载 `.zshrc`，`command -v node` 常常找不到（哪怕终端里明明有）。启动器必须自己补上常见 Node 路径（本脚本开头已内置）。
- **`qlmanage -t` 在某些 macOS 版本会挂起**，别拿它做图标自查。
- **改 Dock 的 plist 后要紧跟 `killall -9 Dock`**：普通 killall 会让 Dock 在退出时把内存里的旧配置回写，覆盖你的修改。

## License

[MIT](LICENSE)
