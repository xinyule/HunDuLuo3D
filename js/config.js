/**
 * 魂斗罗3D 重制版 — 全局配置
 * 关卡/敌人/Boss 严格按 FC 版魂斗罗原作；镜头按 GTA 式第三人称。
 */
const CONFIG = {
    renderer: { fov: 70, aimFov: 58, near: 0.1, far: 600, antialias: true },

    // GTA 式越肩镜头
    camera: {
        distance: 5.2,        // 平时镜头距
        aimDistance: 3.2,     // 瞄准时镜头距
        shoulder: 0.9,        // 右肩偏移
        height: 0.55,         // 镜头相对胸口上抬
        targetHeight: 1.45,   // 角色注视点高度（站立）
        targetHeightProne: 0.5,
        pitchMin: -0.6,       // 俯角（弧度，约 -35°）
        pitchMax: 1.05,       // 仰角（约 +60°）
        smooth: 9,            // 位置阻尼系数 /s
        collisionPad: 0.35,   // 镜头撞墙回退余量
    },

    player: {
        height: 1.7,
        proneHeight: 0.55,
        radius: 0.38,
        walkSpeed: 7.5,
        runSpeed: 11.5,
        proneSpeed: 3.2,
        jumpVelocity: 7.4,
        gravity: 19,
        maxCells: 3,          // 折中档：3 格血
        startLives: 3,        // 命数（含首条）
        extendScore: 10000,   // 每攒满此分数 +1 命
        hitInvuln: 0.9,       // 受击后无敌（秒）
        respawnInvuln: 2.5,   // 复活后无敌闪烁（秒）
    },
};

// 魂斗罗武器（无限弹药、无换弹；靠飞鹰道具换枪，阵亡掉回普通枪）
// kind: normal / machine / fire / laser / spread ； R=加速修饰，B=防护罩，+=回血（非武器，见 pickups）
const WEAPON_DATA = {
    N: { name: '步枪',   letter: 'N', damage: 34, fireRate: 0.16, bulletSpeed: 95,  pellets: 1, spread: 0.006, color: 0xffe08a, pierce: false },
    M: { name: '机枪',   letter: 'M', damage: 30, fireRate: 0.075, bulletSpeed: 95, pellets: 1, spread: 0.012, color: 0x7ac7ff, pierce: false },
    F: { name: '火球枪', letter: 'F', damage: 55, fireRate: 0.22, bulletSpeed: 55,  pellets: 1, spread: 0.0,   color: 0xff7a33, pierce: true, wave: true },
    L: { name: '激光枪', letter: 'L', damage: 46, fireRate: 0.13, bulletSpeed: 240, pellets: 1, spread: 0.0,   color: 0xff4d6d, pierce: true },
    S: { name: '散射枪', letter: 'S', damage: 26, fireRate: 0.24, bulletSpeed: 85,  pellets: 5, spread: 0.16,  color: 0xa8ff7a, pierce: false },
};
const RAPID_FACTOR = 0.62; // R 道具：射击间隔倍率

// 敌人（hp 为受击点数口径，与武器 damage 对齐：普通枪 3 发一个步兵）
const ENEMY_DATA = {
    rifleman:  { hp: 70,  speed: 0,   radius: 0.5,  score: 100, fireInterval: 1.7, orbSpeed: 17, range: 46 },
    runner:    { hp: 45,  speed: 6.4, radius: 0.5,  score: 150, meleeRange: 1.7, meleeCooldown: 0.9 },
    sniper:    { hp: 45,  speed: 0,   radius: 0.5,  score: 300, fireInterval: 2.4, orbSpeed: 27, range: 60 },
    mortar:    { hp: 80,  speed: 0,   radius: 0.55, score: 250, fireInterval: 3.1, range: 52 },
    statue:    { hp: 110, speed: 0,   radius: 0.8,  score: 250, fireInterval: 3.0, range: 50 },
    turret:    { hp: 120, speed: 0,   radius: 0.85, score: 200, fireInterval: 0.42, burst: 3, burstPause: 1.5, orbSpeed: 18, range: 44 },
    roller:    { hp: 30,  speed: 7.5, radius: 0.45, score: 100, explodeRange: 1.9 },
    spore:     { hp: 35,  speed: 5.4, radius: 0.42, score: 150, meleeRange: 1.5, meleeCooldown: 0.8 },
    tank:      { hp: 700, speed: 2.2, radius: 1.9,  score: 1500, fireInterval: 1.1, orbSpeed: 19, range: 46 },
};

// Boss（部件制：parts 在 boss.js 内按 id 拼装；这里只给总血量与分数口径）
const BOSS_DATA = {
    defenseWall: { name: '防御壁',        score: 3000 },
    baseCore:    { name: '基地核心·独眼', score: 4000 },
    gromaides:   { name: '异形魔像',      score: 5000 },
    godomuga:    { name: '分幻鬼核心',    score: 6000 },
    guldaf:      { name: '反重力飞碟',    score: 7000 },
    gordea:      { name: '巨型装甲兵',    score: 8000 },
    finalGate:   { name: '最终闸门',      score: 9000 },
    alienHeart:  { name: '异形心脏',      score: 15000 },
};

// FC 原作 8 关：丛林 / 基地1 / 瀑布 / 基地2 / 雪原 / 能量地带 / 仓库 / 异形巢穴
// length=走廊长度（玩家从 z=26 出发向 -z 推进），width=走廊宽度
// spawns: [距起点米数, 类型, 横向偏移]（米数越大越靠关底）
// falcons: 在推进到该米数时放飞飞鹰，letters 按顺序发放
const LEVELS_DATA = [
    {
        name: '第1关: 丛林', theme: 'jungle', boss: 'defenseWall',
        story: '公元2633年，红隼占领加瓦隆岛。Bill Rizer 独自潜入丛林，穿过河桥，摧毁关底的防御壁！',
        env: { bg: 0x16281a, ground: 0x2d4a1a, side: 0x24401c, fog: 0x16281a, fogDensity: 0.012, sun: 0xfff2cc },
        width: 26, length: 190,
        spawns: [
            [30, 'rifleman', -5], [38, 'runner', 4], [52, 'rifleman', 6], [60, 'sniper', -8],
            [74, 'runner', -3], [74, 'runner', 3], [88, 'turret', 7], [96, 'rifleman', -6],
            [110, 'mortar', 8], [118, 'runner', 0], [126, 'sniper', 7], [134, 'turret', -7],
            [146, 'rifleman', 5], [146, 'rifleman', -5], [156, 'runner', 2],
        ],
        falcons: [45, 105, 150], letters: ['S', 'R', 'M'],
    },
    {
        name: '第2关: 基地1', theme: 'base', boss: 'baseCore',
        story: '潜入敌方基地。走廊被电网门封锁——打掉墙上的红色感应器核心，电网才会落下。小心皇家卫兵！',
        env: { bg: 0x101018, ground: 0x3a3f4a, side: 0x2c3038, fog: 0x101018, fogDensity: 0.014, sun: 0xbfd4ff },
        width: 18, length: 200,
        gates: [55, 100, 145],
        spawns: [
            [24, 'rifleman', -4], [32, 'rifleman', 4], [44, 'runner', 0],
            [66, 'rifleman', 5], [74, 'turret', -5], [84, 'rifleman', -3], [90, 'runner', 3],
            [112, 'rifleman', -5], [112, 'rifleman', 5], [124, 'mortar', 4], [134, 'runner', -2],
            [156, 'turret', 5], [164, 'rifleman', -5], [172, 'runner', 0], [172, 'runner', 4],
        ],
        falcons: [70, 130], letters: ['M', 'B'],
    },
    {
        name: '第3关: 瀑布', theme: 'waterfall', boss: 'gromaides',
        story: '沿瀑布岩壁向上攀爬！当心落石和喷火石像，瀑布顶端有异形魔像守着通往基地2的入口。',
        env: { bg: 0x14202e, ground: 0x4a4a42, side: 0x3c3a30, fog: 0x14202e, fogDensity: 0.016, sun: 0xd6ecff },
        width: 22, length: 195, terraces: true,
        spawns: [
            [26, 'rifleman', -5], [40, 'sniper', 6], [54, 'runner', 3], [66, 'rifleman', -6],
            [80, 'turret', 6], [92, 'sniper', -7], [104, 'runner', -2], [104, 'runner', 4],
            [118, 'statue', -6], [130, 'rifleman', 5], [142, 'statue', 6], [154, 'sniper', 6],
            [162, 'runner', 0], [170, 'rifleman', -4],
        ],
        falcons: [60, 125], letters: ['F', 'S'],
    },
    {
        name: '第4关: 基地2', theme: 'base2', boss: 'godomuga',
        story: '第二座基地，防线更密：滚雷、榴弹和更快的卫兵。关底的分幻鬼核心会分裂幻影，真身只在四影对齐的一瞬现形！',
        env: { bg: 0x14101c, ground: 0x403a4c, side: 0x2e2838, fog: 0x14101c, fogDensity: 0.015, sun: 0xd8c8ff },
        width: 18, length: 210,
        gates: [50, 92, 134, 172],
        spawns: [
            [22, 'rifleman', 4], [30, 'roller', -3], [38, 'rifleman', -5], [46, 'runner', 2],
            [62, 'turret', 5], [72, 'mortar', -5], [82, 'roller', 0], [86, 'rifleman', 4],
            [104, 'rifleman', -5], [112, 'runner', -2], [112, 'runner', 3], [122, 'turret', -5],
            [146, 'mortar', 5], [154, 'roller', -3], [160, 'rifleman', 5], [166, 'sniper', -5],
            [182, 'rifleman', 0], [186, 'runner', 4],
        ],
        falcons: [66, 120, 168], letters: ['L', 'R', 'S'],
    },
    {
        name: '第5关: 雪原', theme: 'snow', boss: 'guldaf',
        story: '冰天雪地。雪堆里藏着榴弹手，路上还有装甲扫讨车巡逻。关底的反重力飞碟会投放孢子舱，打它的底部核心！',
        env: { bg: 0x1c2634, ground: 0xb9c6d4, side: 0x8fa2b5, fog: 0x1c2634, fogDensity: 0.02, sun: 0xffffff },
        width: 28, length: 200,
        midTank: 118,
        spawns: [
            [26, 'rifleman', -6], [36, 'mortar', 8], [48, 'runner', 3], [58, 'sniper', -9],
            [70, 'mortar', -8], [80, 'rifleman', 6], [90, 'roller', 0], [100, 'rifleman', -5],
            [132, 'mortar', 7], [142, 'runner', -3], [142, 'runner', 3], [152, 'turret', -8],
            [162, 'sniper', 8], [170, 'rifleman', 0],
        ],
        falcons: [55, 105, 155], letters: ['S', 'B', 'F'],
    },
    {
        name: '第6关: 能量地带', theme: 'energy', boss: 'gordea',
        story: '能量地带，火焰喷口按节拍封锁通道——看准节奏再通过。关底是投掷圆盘的巨型装甲兵！',
        env: { bg: 0x180c08, ground: 0x3d2c20, side: 0x2c1c12, fog: 0x180c08, fogDensity: 0.014, sun: 0xffd9a8 },
        width: 22, length: 200,
        flames: [62, 84, 108, 132, 154],
        spawns: [
            [24, 'rifleman', -5], [34, 'runner', 4], [46, 'turret', 6],
            [70, 'rifleman', 5], [76, 'runner', -3], [94, 'mortar', -6], [100, 'rifleman', 6],
            [118, 'turret', -6], [126, 'runner', 2], [142, 'rifleman', -5], [148, 'sniper', 6],
            [164, 'rifleman', 4], [170, 'runner', -2],
        ],
        falcons: [50, 115, 160], letters: ['L', 'S', 'R'],
    },
    {
        name: '第7关: 仓库', theme: 'hangar', boss: 'finalGate',
        story: '红隼的仓库，尖刺矿车在轨道上往复冲撞，压顶机随时落下。打穿尽头的最终闸门，就能进入异形巢穴！',
        env: { bg: 0x12120e, ground: 0x44423a, side: 0x302e28, fog: 0x12120e, fogDensity: 0.013, sun: 0xffe9b0 },
        width: 24, length: 205,
        carts: [70, 112, 150],
        crushers: [88, 132, 172],
        spawns: [
            [24, 'turret', -7], [34, 'rifleman', 5], [44, 'runner', -3], [54, 'turret', 7],
            [82, 'rifleman', -6], [90, 'mortar', 6], [98, 'runner', 0],
            [124, 'turret', -7], [132, 'rifleman', 6], [140, 'sniper', -6],
            [162, 'rifleman', 5], [168, 'runner', -4], [168, 'runner', 4], [176, 'turret', 0],
        ],
        falcons: [58, 120, 165], letters: ['F', 'B', 'L'],
    },
    {
        name: '第8关: 异形巢穴', theme: 'alien', boss: 'alienHeart',
        story: '异形巢穴——整面墙都在蠕动。先斩守巢的龙神，再打爆那颗异形心脏，终结红隼！',
        env: { bg: 0x16040c, ground: 0x381826, side: 0x2a0e1c, fog: 0x16040c, fogDensity: 0.017, sun: 0xffb3c8 },
        width: 24, length: 185,
        spawns: [
            [24, 'spore', -4], [30, 'spore', 4], [42, 'rifleman', -6], [52, 'spore', 0],
            [64, 'turret', 7], [76, 'spore', -5], [76, 'spore', 5], [88, 'mortar', -7],
            [100, 'spore', 2], [110, 'sniper', 7], [120, 'spore', -3], [120, 'spore', 3],
            [132, 'rifleman', 6], [142, 'spore', 0],
        ],
        falcons: [48, 100, 140], letters: ['S', 'L', 'B'],
    },
];
