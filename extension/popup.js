/**
 * Claude Bell - Popup Script
 */

// DOM 元素
const elements = {
  desktopEnabled: document.getElementById('desktopEnabled'),
  barkEnabled: document.getElementById('barkEnabled'),
  barkKey: document.getElementById('barkKey'),
  barkServer: document.getElementById('barkServer'),
  saveButton: document.getElementById('save'),
  testButton: document.getElementById('test'),
  status: document.getElementById('status')
};

// 显示状态消息
function showStatus(message, type = 'success') {
  elements.status.textContent = message;
  elements.status.className = `status ${type}`;

  setTimeout(() => {
    elements.status.className = 'status';
  }, 3000);
}

// 加载保存的设置
async function loadSettings() {
  try {
    const data = await chrome.storage.sync.get([
      'barkKey',
      'barkServer',
      'barkEnabled',
      'desktopEnabled'
    ]);

    elements.barkKey.value = data.barkKey || '';
    elements.barkServer.value = data.barkServer || 'https://api.day.app';
    elements.barkEnabled.checked = data.barkEnabled !== false;
    elements.desktopEnabled.checked = data.desktopEnabled !== false;
  } catch (e) {
    console.error('Failed to load settings:', e);
  }
}

// 保存设置
async function saveSettings() {
  const settings = {
    barkKey: elements.barkKey.value.trim(),
    barkServer: elements.barkServer.value.trim() || 'https://api.day.app',
    barkEnabled: elements.barkEnabled.checked,
    desktopEnabled: elements.desktopEnabled.checked
  };

  try {
    await chrome.storage.sync.set(settings);
    showStatus('设置已保存', 'success');
  } catch (e) {
    showStatus('保存失败', 'error');
    console.error('Failed to save settings:', e);
  }
}

// 测试通知
async function testNotifications() {
  const barkKey = elements.barkKey.value.trim();
  const barkServer = elements.barkServer.value.trim() || 'https://api.day.app';
  const desktopEnabled = elements.desktopEnabled.checked;
  const barkEnabled = elements.barkEnabled.checked;

  let success = true;

  // 测试桌面通知
  if (desktopEnabled) {
    if (Notification.permission === 'granted') {
      new Notification('Claude Bell 测试', {
        body: '如果你看到这条消息，桌面通知正常工作！',
        icon: 'icons/icon128.png'
      });
    } else if (Notification.permission === 'default') {
      const permission = await Notification.requestPermission();
      if (permission === 'granted') {
        new Notification('Claude Bell 测试', {
          body: '如果你看到这条消息，桌面通知正常工作！',
          icon: 'icons/icon128.png'
        });
      } else {
        showStatus('桌面通知权限被拒绝', 'error');
        success = false;
      }
    } else {
      showStatus('桌面通知权限被拒绝', 'error');
      success = false;
    }
  }

  // 测试 Bark
  if (barkEnabled && barkKey) {
    try {
      const response = await fetch(`${barkServer}/${barkKey}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          title: 'Claude Bell 测试',
          body: '如果你收到这条推送，Bark 配置正确！',
          sound: 'minuet',
          group: 'claude-test'
        })
      });

      if (!response.ok) {
        showStatus('Bark 请求失败', 'error');
        success = false;
      }
    } catch (e) {
      showStatus('Bark 连接失败', 'error');
      success = false;
      console.error('Bark test failed:', e);
    }
  } else if (barkEnabled && !barkKey) {
    showStatus('请先填写 Bark Key', 'error');
    success = false;
  }

  if (success) {
    showStatus('测试通知已发送', 'success');
  }
}

// 事件监听
elements.saveButton.addEventListener('click', saveSettings);
elements.testButton.addEventListener('click', testNotifications);

// 页面加载时读取设置
loadSettings();
