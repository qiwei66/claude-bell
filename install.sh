#!/bin/bash
# =============================================================================
# Claude Bell - 一键安装脚本
# 让 Claude 的每一次完成都不被错过
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_header() {
    echo ""
    echo -e "${PURPLE}╔════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║${NC}     🔔 ${BLUE}Claude Bell${NC} 安装程序          ${PURPLE}║${NC}"
    echo -e "${PURPLE}║${NC}     让 Claude 的每一次完成都不被错过   ${PURPLE}║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# 安装目录
INSTALL_DIR="$HOME/.claude-bell"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

print_header

# 检查依赖
print_step "检查依赖..."

# 检查 jq
if ! command -v jq &> /dev/null; then
    print_warning "jq 未安装，正在安装..."
    if command -v brew &> /dev/null; then
        brew install jq
    else
        print_error "请先安装 Homebrew: https://brew.sh"
        exit 1
    fi
fi
print_success "jq 已安装"

# 检查 Python3
if ! command -v python3 &> /dev/null; then
    print_error "Python3 未安装，请先安装 Python3"
    exit 1
fi
print_success "Python3 已安装"

# 创建安装目录
print_step "创建安装目录..."
mkdir -p "$INSTALL_DIR"
print_success "安装目录: $INSTALL_DIR"

# 下载或复制文件
print_step "安装 Claude Bell 脚本..."

# 如果是从 GitHub 安装，这里会使用 curl 下载
# 如果是本地安装，直接使用现有文件
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/claude-bell.sh" ]]; then
    # 本地安装模式
    cp "$SCRIPT_DIR/claude-bell.sh" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/extract-summary.py" "$INSTALL_DIR/"
    if [[ ! -f "$INSTALL_DIR/config.json" ]]; then
        cp "$SCRIPT_DIR/config.json" "$INSTALL_DIR/"
    fi
else
    # GitHub 安装模式
    GITHUB_RAW="https://raw.githubusercontent.com/qiwei66/claude-bell/main"
    curl -sSL "$GITHUB_RAW/claude-bell.sh" -o "$INSTALL_DIR/claude-bell.sh"
    curl -sSL "$GITHUB_RAW/extract-summary.py" -o "$INSTALL_DIR/extract-summary.py"
    curl -sSL "$GITHUB_RAW/config.example.json" -o "$INSTALL_DIR/config.json"
fi

# 设置执行权限
chmod +x "$INSTALL_DIR/claude-bell.sh"
chmod +x "$INSTALL_DIR/extract-summary.py"
print_success "脚本已安装"

# 配置 Claude Code hooks
print_step "配置 Claude Code hooks..."

if [[ -f "$CLAUDE_SETTINGS" ]]; then
    # 检查是否已经配置了 hooks
    if jq -e '.hooks.Stop' "$CLAUDE_SETTINGS" &>/dev/null; then
        print_warning "Claude Code hooks 已存在，跳过配置"
    else
        # 添加 hooks 配置
        TMP_FILE=$(mktemp)
        jq '. + {
            "hooks": {
                "Stop": [{
                    "hooks": [{
                        "type": "command",
                        "command": "$HOME/.claude-bell/claude-bell.sh"
                    }]
                }]
            }
        }' "$CLAUDE_SETTINGS" > "$TMP_FILE"
        mv "$TMP_FILE" "$CLAUDE_SETTINGS"
        print_success "hooks 已配置"
    fi
else
    # 创建新的 settings.json
    mkdir -p "$(dirname "$CLAUDE_SETTINGS")"
    cat > "$CLAUDE_SETTINGS" << 'SETTINGS'
{
    "hooks": {
        "Stop": [{
            "hooks": [{
                "type": "command",
                "command": "$HOME/.claude-bell/claude-bell.sh"
            }]
        }]
    }
}
SETTINGS
    print_success "创建了新的 Claude Code 配置"
fi

# 配置 Bark
echo ""
print_step "配置 Bark (iOS 推送通知)..."
echo ""
echo -e "  Bark 是一个免费的 iOS 推送服务"
echo -e "  下载地址: ${BLUE}https://github.com/Finb/Bark${NC}"
echo -e "  App Store: ${BLUE}https://apps.apple.com/app/bark-customed-notifications/id1403753865${NC}"
echo ""

read -p "请输入你的 Bark Key (回车跳过): " BARK_KEY

if [[ -n "$BARK_KEY" ]]; then
    # 更新配置文件
    TMP_FILE=$(mktemp)
    jq --arg key "$BARK_KEY" '.bark_key = $key' "$INSTALL_DIR/config.json" > "$TMP_FILE"
    mv "$TMP_FILE" "$INSTALL_DIR/config.json"
    print_success "Bark Key 已保存"

    # 测试 Bark
    echo ""
    read -p "是否发送测试通知? (y/N): " TEST_BARK
    if [[ "$TEST_BARK" =~ ^[Yy]$ ]]; then
        BARK_SERVER=$(jq -r '.bark_server // "https://api.day.app"' "$INSTALL_DIR/config.json")
        curl -s -X POST "$BARK_SERVER/$BARK_KEY" \
            -H "Content-Type: application/json" \
            -d '{"title":"🔔 Claude Bell","body":"安装成功！欢迎使用 Claude Bell","sound":"minuet"}' &>/dev/null
        print_success "测试通知已发送，请检查你的 iPhone"
    fi
else
    print_warning "跳过 Bark 配置，你可以稍后编辑 $INSTALL_DIR/config.json"
fi

# 完成
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}     🎉 ${BLUE}Claude Bell 安装完成！${NC}          ${GREEN}║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo "接下来："
echo "  1. 使用 Claude Code CLI 完成任务时，你会自动收到通知"
echo "  2. 配置文件位置: $INSTALL_DIR/config.json"
echo "  3. 日志文件位置: $INSTALL_DIR/notify.log"
echo ""
echo "Chrome 扩展 (Web/Desktop 支持):"
echo "  1. 打开 Chrome，访问 chrome://extensions/"
echo "  2. 开启「开发者模式」"
echo "  3. 点击「加载已解压的扩展程序」"
echo "  4. 选择目录: $INSTALL_DIR/extension"
echo ""
echo -e "更多信息: ${BLUE}https://github.com/qiwei66/claude-bell${NC}"
echo ""
