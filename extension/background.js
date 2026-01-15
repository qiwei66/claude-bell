/**
 * Claude Bell - Background Service Worker
 */

// 监听来自 content script 的消息
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'TASK_COMPLETE') {
    console.log('[Claude Bell] Task complete received:', message.data);

    // 可以在这里添加额外的处理逻辑
    // 例如：播放声音、更新 badge 等

    // 更新扩展图标 badge
    chrome.action.setBadgeText({ text: '!' });
    chrome.action.setBadgeBackgroundColor({ color: '#7c3aed' });

    // 5秒后清除 badge
    setTimeout(() => {
      chrome.action.setBadgeText({ text: '' });
    }, 5000);
  }

  sendResponse({ received: true });
  return true;
});

// 扩展安装时
chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    console.log('[Claude Bell] Extension installed');

    // 设置默认配置
    chrome.storage.sync.set({
      barkEnabled: true,
      desktopEnabled: true,
      barkServer: 'https://api.day.app',
      barkKey: ''
    });
  }
});

console.log('[Claude Bell] Background service worker started');
