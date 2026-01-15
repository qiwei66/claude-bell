/**
 * Claude Bell - Content Script
 * 监控 claude.ai 页面状态，检测任务完成并发送通知
 */

class ClaudeBellMonitor {
  constructor() {
    this.isProcessing = false;
    this.lastMessageCount = 0;
    this.checkInterval = null;
    this.debounceTimer = null;
    this.config = {
      barkEnabled: true,
      desktopEnabled: true,
      barkServer: 'https://api.day.app',
      barkKey: ''
    };

    this.init();
  }

  async init() {
    console.log('[Claude Bell] Initializing...');

    // 加载配置
    try {
      const stored = await chrome.storage.sync.get([
        'barkKey',
        'barkServer',
        'barkEnabled',
        'desktopEnabled'
      ]);
      Object.assign(this.config, stored);
    } catch (e) {
      console.log('[Claude Bell] Could not load config:', e);
    }

    // 监听配置变化
    chrome.storage.onChanged.addListener((changes) => {
      for (let key in changes) {
        this.config[key] = changes[key].newValue;
      }
      console.log('[Claude Bell] Config updated:', this.config);
    });

    // 开始监控
    this.startMonitoring();
  }

  startMonitoring() {
    // 方法1: MutationObserver 监控 DOM 变化
    this.setupMutationObserver();

    // 方法2: 定时检查状态作为备份
    this.checkInterval = setInterval(() => this.checkTaskStatus(), 2000);

    console.log('[Claude Bell] Monitoring started');
  }

  setupMutationObserver() {
    const observer = new MutationObserver((mutations) => {
      // 防抖处理
      if (this.debounceTimer) {
        clearTimeout(this.debounceTimer);
      }

      this.debounceTimer = setTimeout(() => {
        this.handleMutations(mutations);
      }, 500);
    });

    // 等待页面加载完成后开始监控
    const startObserving = () => {
      const chatContainer =
        document.querySelector('[data-testid="conversation"]') ||
        document.querySelector('.conversation-container') ||
        document.querySelector('main') ||
        document.body;

      observer.observe(chatContainer, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['class', 'data-state', 'disabled', 'aria-disabled']
      });

      console.log('[Claude Bell] Observer attached to:', chatContainer.tagName);
    };

    if (document.readyState === 'complete') {
      startObserving();
    } else {
      window.addEventListener('load', startObserving);
    }
  }

  handleMutations(mutations) {
    const wasProcessing = this.isProcessing;

    // 检测是否正在处理
    const isCurrentlyProcessing = this.detectProcessing();

    if (!wasProcessing && isCurrentlyProcessing) {
      // 任务开始
      this.isProcessing = true;
      console.log('[Claude Bell] Task started');
    } else if (wasProcessing && !isCurrentlyProcessing) {
      // 任务完成 - 再次确认
      setTimeout(() => {
        if (!this.detectProcessing()) {
          this.isProcessing = false;
          this.handleTaskComplete();
        }
      }, 1000);
    }
  }

  detectProcessing() {
    // 检测 Claude 是否正在生成响应的多个信号

    // 信号1: Stop 按钮存在
    const stopButton =
      document.querySelector('button[aria-label="Stop"]') ||
      document.querySelector('[data-testid="stop-button"]') ||
      document.querySelector('button:has(svg[data-icon="stop"])');

    if (stopButton && stopButton.offsetParent !== null) {
      return true;
    }

    // 信号2: 输入框被禁用
    const textarea = document.querySelector(
      'textarea[placeholder], div[contenteditable="true"]'
    );
    if (textarea && (textarea.disabled || textarea.getAttribute('aria-disabled') === 'true')) {
      return true;
    }

    // 信号3: 加载动画存在
    const loadingIndicator =
      document.querySelector('.animate-pulse') ||
      document.querySelector('[data-loading="true"]') ||
      document.querySelector('.typing-indicator');

    if (loadingIndicator && loadingIndicator.offsetParent !== null) {
      return true;
    }

    return false;
  }

  checkTaskStatus() {
    // 定时检查作为 MutationObserver 的备份
    const messages = document.querySelectorAll(
      '[data-testid="message"], [data-message-author]'
    );
    const currentCount = messages.length;

    if (this.isProcessing && currentCount > this.lastMessageCount) {
      if (!this.detectProcessing()) {
        setTimeout(() => {
          if (!this.detectProcessing()) {
            this.isProcessing = false;
            this.handleTaskComplete();
          }
        }, 1500);
      }
    }

    // 检测任务开始
    if (!this.isProcessing && this.detectProcessing()) {
      this.isProcessing = true;
      console.log('[Claude Bell] Task started (interval check)');
    }

    this.lastMessageCount = currentCount;
  }

  handleTaskComplete() {
    console.log('[Claude Bell] Task completed!');

    // 提取任务摘要
    const summary = this.extractTaskSummary();

    // 发送通知
    this.sendNotifications(summary);
  }

  extractTaskSummary() {
    // 获取对话标题
    const title =
      document.querySelector('h1')?.textContent ||
      document.querySelector('[data-testid="conversation-title"]')?.textContent ||
      'Claude 对话';

    // 获取最后的用户输入
    const userMessages = document.querySelectorAll(
      '[data-message-author="human"], [data-testid="user-message"]'
    );
    const lastUserMessage = userMessages[userMessages.length - 1];
    const userQuery = lastUserMessage?.textContent?.slice(0, 80) || '任务';

    // 获取 Claude 响应的前几行
    const assistantMessages = document.querySelectorAll(
      '[data-message-author="assistant"], [data-testid="assistant-message"]'
    );
    const lastAssistantMessage = assistantMessages[assistantMessages.length - 1];
    const responsePreview = lastAssistantMessage?.textContent?.slice(0, 100) || '';

    return {
      title: 'Claude Bell',
      subtitle: title.slice(0, 50),
      body: userQuery,
      preview: responsePreview
    };
  }

  async sendNotifications(summary) {
    console.log('[Claude Bell] Sending notifications:', summary);

    // 1. 发送浏览器桌面通知
    if (this.config.desktopEnabled) {
      this.sendDesktopNotification(summary);
    }

    // 2. 发送 Bark 推送
    if (this.config.barkEnabled && this.config.barkKey) {
      await this.sendBarkNotification(summary);
    }

    // 3. 通知 background script
    try {
      chrome.runtime.sendMessage({
        type: 'TASK_COMPLETE',
        data: summary
      });
    } catch (e) {
      console.log('[Claude Bell] Could not send to background:', e);
    }
  }

  sendDesktopNotification(summary) {
    if (Notification.permission === 'granted') {
      new Notification(summary.title, {
        body: `${summary.subtitle}\n${summary.body}`,
        icon: 'https://claude.ai/favicon.ico',
        tag: 'claude-bell-complete',
        requireInteraction: false
      });
    } else if (Notification.permission === 'default') {
      Notification.requestPermission().then((permission) => {
        if (permission === 'granted') {
          this.sendDesktopNotification(summary);
        }
      });
    }
  }

  async sendBarkNotification(summary) {
    try {
      const url = `${this.config.barkServer}/${this.config.barkKey}`;

      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: summary.title,
          body: `${summary.subtitle}: ${summary.body}`,
          sound: 'minuet',
          group: 'claude-web',
          level: 'timeSensitive',
          icon: 'https://claude.ai/favicon.ico'
        })
      });

      if (response.ok) {
        console.log('[Claude Bell] Bark notification sent');
      } else {
        console.error('[Claude Bell] Bark notification failed:', response.status);
      }
    } catch (error) {
      console.error('[Claude Bell] Bark notification error:', error);
    }
  }
}

// 初始化监控
if (window.location.hostname === 'claude.ai') {
  // 请求通知权限
  if (typeof Notification !== 'undefined' && Notification.permission === 'default') {
    Notification.requestPermission();
  }

  // 启动监控
  window.claudeBellMonitor = new ClaudeBellMonitor();
}
