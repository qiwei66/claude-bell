# 🔔 Claude Bell

> 让 Claude 的每一次完成都不被错过 —— Mac + iOS 实时通知

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-macOS-blue.svg)]()
[![Claude Code](https://img.shields.io/badge/Claude%20Code-Compatible-purple.svg)]()

## ✨ 功能特点

- **🖥️ Mac 系统通知** - 任务完成时自动弹出系统通知
- **📱 iOS 推送** - 通过 Bark 推送到 iPhone，即使不在电脑前也能收到
- **🔍 智能摘要** - 自动提取任务描述和工作统计
- **🌐 全平台支持** - CLI + Web + Desktop 全覆盖
- **⚡ 零侵入** - 利用 Claude Code 原生 hooks，无需修改代码

## 📦 快速安装

### 方式一：一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/qiwei66/claude-bell/main/install.sh | bash
```

### 方式二：手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/qiwei66/claude-bell.git
cd claude-bell

# 2. 运行安装脚本
./install.sh
```

## 🔧 配置

### 1. 配置 Bark (iOS 推送)

[Bark](https://github.com/Finb/Bark) 是一个免费的 iOS 推送服务，让你的 iPhone 也能收到 Claude 任务完成通知。

#### 步骤：

1. **下载 Bark App**
   - App Store: [Bark - 自定义推送通知](https://apps.apple.com/app/bark-customed-notifications/id1403753865)
   - GitHub: https://github.com/Finb/Bark

2. **获取你的 Bark Key**
   - 打开 Bark App
   - 首页会显示你的推送 URL，格式如: `https://api.day.app/XXXXX`
   - `XXXXX` 就是你的 Bark Key

3. **配置 Claude Bell**

   编辑配置文件 `~/.claude-bell/config.json`:
   ```json
   {
     "bark_key": "你的-bark-key",
     "bark_server": "https://api.day.app",
     "bark_sound": "minuet",
     "mac_notification": true
   }
   ```

4. **测试推送**
   ```bash
   curl -X POST "https://api.day.app/你的KEY" \
     -H "Content-Type: application/json" \
     -d '{"title":"测试","body":"Claude Bell 配置成功！"}'
   ```

### 2. 配置 Chrome 扩展 (Web/Desktop)

1. 打开 Chrome，访问 `chrome://extensions/`
2. 开启右上角的「开发者模式」
3. 点击「加载已解压的扩展程序」
4. 选择目录: `~/.claude-bell/extension`
5. 点击扩展图标，配置 Bark Key

## 📖 使用

### CLI 模式 (Claude Code)

安装完成后，无需额外操作。当你使用 Claude Code 完成任务时，会自动收到通知。

```bash
# 推荐：跳过权限确认，体验更流畅
claude --dangerously-skip-permissions
```

### Web/Desktop 模式

1. 确保 Chrome 扩展已安装并启用
2. 打开 https://claude.ai
3. 正常使用 Claude，任务完成时会自动通知

## ⚙️ 配置文件说明

`~/.claude-bell/config.json`:

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `bark_key` | Bark 推送 Key | `""` |
| `bark_server` | Bark 服务器地址 | `"https://api.day.app"` |
| `bark_sound` | Bark 通知声音 | `"minuet"` |
| `bark_group` | Bark 通知分组 | `"claude"` |
| `mac_notification` | 是否启用 Mac 通知 | `true` |
| `mac_sound` | Mac 通知声音 | `"Glass"` |

### Bark 可用声音

`alarm`, `anticipate`, `bell`, `birdsong`, `bloom`, `calypso`, `chime`, `choo`, `descent`, `electronic`, `fanfare`, `glass`, `gotosleep`, `healthnotification`, `horn`, `ladder`, `mailsent`, `minuet`, `multiwayinvitation`, `newmail`, `newsflash`, `noir`, `paymentsuccess`, `shake`, `sherwoodforest`, `silence`, `spell`, `suspense`, `telegraph`, `tiptoes`, `typewriters`, `update`

## 🔍 通知内容

当任务完成时，你会收到类似这样的通知：

```
🔔 Claude Bell
项目名称

帮我重构登录模块... · 改3文件 | 执行5命令 · 耗时2分30秒
```

包含：
- 项目名称（从工作目录提取）
- 任务摘要（用户原始需求的前 60 字符）
- 工作统计（编辑文件数、执行命令数）
- 耗时

## 🏗️ 项目结构

```
~/.claude-bell/
├── claude-bell.sh        # 主通知脚本
├── extract-summary.py    # 摘要提取器
├── config.json           # 配置文件
├── notify.log            # 通知日志
├── install.sh            # 安装脚本
├── README.md             # 说明文档
└── extension/            # Chrome 扩展
    ├── manifest.json
    ├── content.js
    ├── background.js
    ├── popup.html
    ├── popup.js
    └── icons/
```

## ❓ 常见问题

### Q: 为什么收不到 Mac 通知？

1. 检查系统偏好设置 > 通知，确保终端/脚本有通知权限
2. 检查「勿扰模式」是否开启

### Q: Bark 推送失败？

1. 确认 Bark Key 正确
2. 测试网络连接: `curl https://api.day.app`
3. 检查日志: `tail -f ~/.claude-bell/notify.log`

### Q: Chrome 扩展不工作？

1. 确保在 claude.ai 页面上
2. 检查扩展是否启用
3. 打开开发者工具 Console 查看错误

### Q: 如何卸载？

```bash
# 删除安装目录
rm -rf ~/.claude-bell

# 从 Claude Code 配置中移除 hooks
# 编辑 ~/.claude/settings.json，删除 "hooks" 部分
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 License

MIT License - 详见 [LICENSE](LICENSE) 文件

## 🔗 相关链接

- [Claude Code](https://docs.anthropic.com/en/docs/build-with-claude/claude-code)
- [Bark - iOS 推送服务](https://github.com/Finb/Bark)
- [Claude Code Hooks 文档](https://docs.anthropic.com/en/docs/build-with-claude/claude-code/hooks)

---

**Made with ❤️ for Claude Code users**
