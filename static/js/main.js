document.addEventListener('DOMContentLoaded', function() {
    // 电池高度动态设置
    const batteryLevels = document.querySelectorAll('.battery-level');
    batteryLevels.forEach(levelElement => {
        const batteryText = levelElement.textContent.trim();
        if (batteryText && batteryText !== '未知') {
            const level = parseInt(batteryText.replace('%', ''));
            if (!isNaN(level)) {
                levelElement.style.height = level + '%';
                levelElement.style.background = level > 20 ? 
                    'linear-gradient(to top, #2ecc71, #27ae60)' : 
                    'linear-gradient(to top, #e74c3c, #c0392b)';
            }
        }
    });
    
    // 表单提交处理
    const forms = document.querySelectorAll('form');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            const submitBtn = this.querySelector('button[type="submit"]');
            if (submitBtn) {
                const originalText = submitBtn.innerHTML;
                submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span> 处理中...';
                submitBtn.disabled = true;
                
                // 3秒后恢复，防止长时间无响应
                setTimeout(() => {
                    if (submitBtn.disabled) {
                        submitBtn.innerHTML = originalText;
                        submitBtn.disabled = false;
                    }
                }, 3000);
            }
        });
    });
    
    // 刷新按钮处理
    window.refreshBattery = function() {
        fetch('/api/battery')
            .then(response => response.json())
            .then(data => {
                if (data.code === 200 && data.data) {
                    const battery = data.data;
                    const batteryLevelElement = document.getElementById('battery-level');
                    
                    if (batteryLevelElement) {
                        batteryLevelElement.textContent = battery.level || '未知';
                        
                        if (battery.level && battery.level !== '未知') {
                            const level = parseInt(battery.level.replace('%', ''));
                            if (!isNaN(level)) {
                                batteryLevelElement.style.height = level + '%';
                                batteryLevelElement.style.background = level > 20 ? 
                                    'linear-gradient(to top, #2ecc71, #27ae60)' : 
                                    'linear-gradient(to top, #e74c3c, #c0392b)';
                            }
                        }
                    }
                    
                    // 更新其他电池信息
                    updateBatteryInfo(battery);
                } else {
                    alert('刷新电量失败: ' + (data.msg || '未知错误'));
                }
            })
            .catch(error => {
                alert('网络请求失败: ' + error.message);
            });
    };
    
    window.refreshLocation = function() {
        fetch('/api/location')
            .then(response => response.json())
            .then(data => {
                if (data.code === 200 && data.data) {
                    window.location.reload();
                } else {
                    alert('刷新定位失败: ' + (data.msg || '未知错误'));
                }
            })
            .catch(error => {
                alert('网络请求失败: ' + error.message);
            });
    };
    
    function updateBatteryInfo(battery) {
        const infoElements = document.querySelectorAll('.battery-info');
        infoElements.forEach(element => {
            const key = element.dataset.key;
            if (battery[key]) {
                element.textContent = battery[key];
            }
        });
    }
});

// 全局函数，用于模板中的 onclick 调用
function showNotification(message, type = 'info') {
    // 简单的通知函数
    alert(`${type.toUpperCase()}: ${message}`);
}