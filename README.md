# HunDuLuo3D

魂斗罗3D — 经典魂斗罗 1-8 关的真 3D 第一人称重制版，基于 Three.js 构建。

## 玩法

- 第一人称视角，WASD 移动，鼠标视角（点击锁定指针）
- 3 种武器：步枪（自动）、霰弹枪（半自动）、冲锋枪（自动）
- 4 种敌人：士兵、机枪手、狙击手、Boss
- 8 关经典剧情：丛林 → 河流 → 基地 → 桥梁 → 基地2 → 仓库 → 反应堆 → 最终Boss
- 支持安卓触屏（虚拟摇杆 + 射击按钮）和 Windows 键鼠

## 操作

| 操作 | 键鼠 | 触屏 |
|------|------|------|
| 移动 | WASD | 虚拟摇杆 |
| 视角 | 鼠标移动 | 拖拽屏幕 |
| 射击 | 鼠标左键 | 射击按钮 |
| 换弹 | R | 换弹按钮 |
| 切武器 | 1/2/3 | 武器按钮 |
| 奔跑 | Shift | - |

## 运行

直接用浏览器打开 `index.html`，或启动本地服务器：

```bash
python -m http.server 8080
```

然后访问 `http://localhost:8080`。

## 技术栈

- Three.js (WebGL 3D 渲染)
- Web Audio API (程序化音效，无音频文件)
- 纯 JavaScript，无构建工具，无依赖

## GitHub Pages

仓库已配置 GitHub Pages，可通过 `https://xinyule.github.io/HunDuLuo3D/` 在线游玩。
