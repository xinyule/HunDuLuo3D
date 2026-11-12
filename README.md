# 魂斗罗 3D · Contra 3D（Godot 引擎版 v3）

把 FC《魂斗罗》按原作复原成真 3D 第三人称射击：人物、场景、敌人、Boss、功能逐项对照原作重做，镜头是 GTA 式越肩视角。用 **Godot 4.3 + GDScript** 开发，一份工程构建 **Web / Android / Windows** 三端。

## 立即玩

- **网页版（GitHub Pages）**：https://xinyule.github.io/HunDuLuo3D/ — 打开即玩（首次加载约 65MB，请耐心等进度条）
- **Android APK / Windows 版**：到 [Releases](../../releases) 下载（APK 为本地自签，安卓需允许「安装未知应用」；Windows 解压后 exe 与 pck 须放在同一目录）

## 原作复原要点

- **人物**：比尔·雷泽（红头巾 + 白背心 + 蓝裤）与兰斯·比恩（长发 + 红头巾 + 红裤 + 裸上身）可选，同为海兵队魂斗罗部队上等兵；188cm 壮实体型按官方设定建模
- **8 关原作复刻**：丛林（爆裂木桥 + 突击水兵 Akbar）→ 基地1（电网门 + 独炎眼）→ 瀑布（台阶攀爬 + 喷火石像 + 魔神像）→ 基地2（自走弹 + 装甲步兵 Garth + 分幻鬼四影对齐）→ 雪原（猎步兵 Langel + 扫讨车 Dogra + 反重力飞碟投放孢子）→ 能量地带（火焰喷口节拍 + 巨神兵掷圆盘）→ 仓库（尖刺矿车 + 压顶机 + 最终闸门）→ 异形巢穴（妖卵孵化 + 龙神守巢 + 天王创魔心）
- **日版独有动态也复原了**（美版删减的那些）：丛林树冠摇动、瀑布流水、雪原吹雪、异形肉壁蠕动、基地灯带明暗
- **敌人名册按官方名**：Ledder 突枪射击兵、Greeder 红衣突击兵、回转炮台、榴弹兵、Daru 电光自走弹、Bugger 把妖虫……全员发射实体红弹，可跳可趴躲
- **功能**：飞鹰徽章打字母换枪（M 机枪 / F 火球 / L 激光 / S 散射 / R 加速 / B 防护罩）、翻跟头跳、趴射、检查点、过关奖励；**命数主菜单可选 3/5/10/30/∞，命尽可续关 3 次**；每 10000 分延长一命；科乐美秘籍 ↑↑↓↓←→←→BA = 30 命；最高分本地存档
- **唯一经批准偏离原作**：3 格血（原作一击必死），受击无敌 0.9 秒、无自动回血

## 操作

| 键位 | 功能 |
|---|---|
| WASD | 移动（相对镜头） |
| 鼠标 | 越肩镜头（点击画面锁定指针） |
| 左键 | 射击（按准星，可瞄高低） |
| 右键 | 瞄准（镜头收紧、FOV 58） |
| 空格 | 翻跟头跳（空中可开火） |
| C / Ctrl | 趴下（躲高弹道） |
| Shift | 疾跑 |
| M | 音乐开关 |
| 手机 | 左摇杆移动 · 右侧按钮射击/跳/趴 · 拖屏转镜头 |

## 技术与素材

- 渲染：PBR 材质 + HDRI 环境光/反射、ACES 色调映射、实时阴影、辉光、雾效；网页版为 Compatibility 管线，原生版 Forward+
- 素材：Poly Haven CC0 实拍贴图与 HDRI；敌人骨骼士兵为 threejs.org 示例 Mixamo 模型（按兵种染色）；音效与 BGM 为程序合成 WAV（无版权素材）
- 架构：数据驱动——关卡/敌人/Boss/武器全在 `godot/scripts/data.gd`；关卡推进器、弹丸池、部件制 Boss 框架、关节枢轴主角动画，状态只归主状态机改

## 本地构建

1. 安装 Godot 4.3 与导出模板，打开 `godot/project.godot`
2. 导出预设已备好（Web / Windows Desktop / Android）：`godot --headless --path godot --export-release "Web"` 等
3. Android 正式签名需自备 keystore 并在预设里临时填 `keystore/release*`（切勿提交进仓库）
4. 无头冒烟：`godot --headless --path godot --script res://test/smoke.gd --fixed-fps 60`（21 项检查）；全关覆盖：`res://test/coverage.gd`

## 目录

- 仓库根目录：网页版构建产物（GitHub Pages 直接托管）
- `godot/`：Godot 工程源码
