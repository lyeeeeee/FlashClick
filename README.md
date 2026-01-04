# FlashClick

低延迟键盘驱动点击，只作用于光标所在前台 App。

## 特性

*   **性能好、延迟低**：毫秒级响应，专为效率优化。
*   **多屏支持**：适配任意窗口与多显示器；只在当前屏幕显示标签。
*   **只操作光标所在 App**：仅作用于前台应用，通过 PID 校验避免误操作。
*   **可靠点击**：优先使用 AXPress，失败后自动回退到 CGEvent 模拟点击。
*   **后台运行**：单实例、低资源占用，日志可查。

## 快速使用

- **激活**: `Cmd + Shift + Space`
- **点击**: 输入目标标签
- **取消**: `ESC` 或点击鼠标

## 构建与运行

```bash
git clone https://github.com/lyeeeeee/FlashClick.git
cd FlashClick
swift run
```

## 权限

需要“辅助功能”和“输入监视”权限，首次运行会提示授权。
