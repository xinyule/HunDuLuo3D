/**
 * 游戏全局配置
 */
const CONFIG = {
    // 渲染
    renderer: {
        fov: 75,
        near: 0.1,
        far: 500,
        antialias: true,
    },
    // 玩家
    player: {
        height: 1.7,          // 眼睛高度
        speed: 8,             // 移动速度 m/s
        runSpeed: 14,         // 奔跑速度
        turnSpeed: 0.0024,    // 鼠标灵敏度
        radius: 0.4,          // 碰撞半径
        health: 100,
        healthRegen: 0,       // 不自动回血
        regenDelay: 8,        // 受伤后多少秒开始回血
        regenRate: 3,         // 每秒回血
        jumpForce: 0,         // 不做跳跃
    },
    // 武器配置
    weapons: {
        0: { name: '步枪', damage: 34, fireRate: 0.12, magSize: 30, reserveAmmo: 90, reloadTime: 2.0, spread: 0.01, auto: true, color: 0xffaa44, range: 200 },
        1: { name: '霰弹枪', damage: 50, fireRate: 0.6, magSize: 6, reserveAmmo: 24, reloadTime: 1.5, spread: 0.08, pellets: 5, auto: false, color: 0xff6644, range: 50 },
        2: { name: '冲锋枪', damage: 18, fireRate: 0.06, magSize: 40, reserveAmmo: 120, reloadTime: 1.8, spread: 0.03, auto: true, color: 0x44aaff, range: 150 },
    },
    // 敌人
    enemy: {
        height: 1.8,
        speed: 3.5,
        chaseSpeed: 6,
        radius: 0.5,
        health: 60,
        damage: 8,
        fireRate: 0.8,
        detectionRange: 40,
        attackRange: 30,
        shootRange: 25,
        scoreValue: 100,
    },
    boss: {
        height: 4,
        speed: 1.5,
        chaseSpeed: 3,
        radius: 1.5,
        health: 500,
        damage: 25,
        fireRate: 0.4,
        detectionRange: 60,
        shootRange: 40,
        scoreValue: 5000,
    },
    // 关卡
    level: {
        size: 100,            // 关卡地图大小
        wallHeight: 6,
    },
};

// 8关剧情数据
const LEVELS_DATA = [
    {
        name: '第1关: 丛林',
        story: '上级命令我潜入敌占区的丛林地带，摧毁敌军的前哨基地。这里是敌人的第一道防线，必须小心前进。',
        storyAfter: '前哨基地已被摧毁！继续深入，下一站——渡河点。',
        env: { bg: 0x1a3320, ground: 0x2d4a1a, fog: 0x1a3320, fogDensity: 0.015 },
        enemyCount: 8,
        enemyTypes: ['soldier'],
        boss: false,
        layout: 'jungle',
    },
    {
        name: '第2关: 渡河',
        story: '敌军在河流沿线部署了重兵。我需要穿越河流，消灭河岸哨所的敌人，找到通往敌营的道路。',
        storyAfter: '渡河成功！敌营就在前方。',
        env: { bg: 0x1a2a3a, ground: 0x3a4a3a, fog: 0x1a2a3a, fogDensity: 0.02 },
        enemyCount: 10,
        enemyTypes: ['soldier', 'gunner'],
        boss: false,
        layout: 'river',
    },
    {
        name: '第3关: 敌营',
        story: '敌军营地就在前方。这里兵力密集，还有重机枪阵地。必须小心渗透，逐一消灭。',
        storyAfter: '敌营已清剿完毕！前方有一座桥梁，那是必经之路。',
        env: { bg: 0x2a2a1a, ground: 0x4a4020, fog: 0x2a2a1a, fogDensity: 0.02 },
        enemyCount: 12,
        enemyTypes: ['soldier', 'gunner', 'gunner'],
        boss: false,
        layout: 'base',
    },
    {
        name: '第4关: 桥梁',
        story: '桥梁是通往敌基地的要道，敌人在这里部署了狙击手和重兵把守。突破桥梁，就能直插敌后。',
        storyAfter: '桥梁已夺下！前方就是敌方基地外围。',
        env: { bg: 0x3a2a1a, ground: 0x5a4a30, fog: 0x3a2a1a, fogDensity: 0.018 },
        enemyCount: 14,
        enemyTypes: ['soldier', 'gunner', 'sniper'],
        boss: false,
        layout: 'bridge',
    },
    {
        name: '第5关: 基地外围',
        story: '敌方基地外围戒备森严，铁丝网和哨塔林立。我需要突破外围防线，进入基地内部。',
        storyAfter: '基地外围已突破！深入基地，找到仓库。',
        env: { bg: 0x2a2a2a, ground: 0x4a4a4a, fog: 0x2a2a2a, fogDensity: 0.022 },
        enemyCount: 14,
        enemyTypes: ['soldier', 'gunner', 'sniper', 'gunner'],
        boss: false,
        layout: 'base2',
    },
    {
        name: '第6关: 仓库',
        story: '仓库里储存着敌军的弹药和装备，有大量守卫。清剿仓库，夺取关键物资，然后前往反应堆。',
        storyAfter: '仓库已清空！最终目标——反应堆核心。',
        env: { bg: 0x2a2a3a, ground: 0x3a3a4a, fog: 0x2a2a3a, fogDensity: 0.025 },
        enemyCount: 16,
        enemyTypes: ['soldier', 'gunner', 'sniper', 'gunner'],
        boss: false,
        layout: 'warehouse',
    },
    {
        name: '第7关: 反应堆',
        story: '敌方基地的核反应堆是他们的核心设施。摧毁反应堆，彻底瘫痪敌人的防御系统！',
        storyAfter: '反应堆已摧毁！最终Boss——敌军指挥官出现了！',
        env: { bg: 0x1a1a2a, ground: 0x2a2a3a, fog: 0x1a1a2a, fogDensity: 0.03 },
        enemyCount: 8,
        enemyTypes: ['soldier', 'gunner'],
        boss: false,
        layout: 'reactor',
    },
    {
        name: '第8关: 最终决战',
        story: '敌军指挥官驾驶巨型机甲出现在基地顶部。这是最后的决战——消灭他，终结这场战争！',
        storyAfter: '',
        env: { bg: 0x2a0a0a, ground: 0x3a1a1a, fog: 0x2a0a0a, fogDensity: 0.02 },
        enemyCount: 4,
        enemyTypes: ['gunner', 'sniper'],
        boss: true,
        layout: 'final',
    },
];
