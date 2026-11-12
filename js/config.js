/**
 * 魂斗罗3D — 全局配置
 * 严格按魂斗罗原作设计
 */
const CONFIG = {
    renderer: {
        fov: 70,
        near: 0.1,
        far: 500,
        antialias: true,
    },
    player: {
        height: 1.7,
        speed: 9,
        runSpeed: 15,
        radius: 0.4,
        health: 100,
        regenDelay: 8,
        regenRate: 3,
        cameraDistance: 5,
        cameraHeight: 2.5,
        cameraLookAhead: 4,
    },
    // 魂斗罗经典武器
    weapons: {
        0: { name: '步枪',     damage: 25, fireRate: 0.12, magSize: 30, reserveAmmo: 90,  reloadTime: 2.0, spread: 0.01, auto: true,  pellets: 1, color: 0xffaa44, range: 200 },
        1: { name: '机枪',     damage: 18, fireRate: 0.06, magSize: 50, reserveAmmo: 150, reloadTime: 2.5, spread: 0.02, auto: true,  pellets: 1, color: 0x44aaff, range: 180 },
        2: { name: '散弹枪',   damage: 28, fireRate: 0.5,  magSize: 6,  reserveAmmo: 30,  reloadTime: 1.5, spread: 0.10, auto: false, pellets: 5, color: 0xff6644, range: 45 },
        3: { name: '火焰喷射', damage: 12, fireRate: 0.08, magSize: 20, reserveAmmo: 60,  reloadTime: 2.0, spread: 0.15, auto: true,  pellets: 1, color: 0xff4400, range: 15, flame: true },
    },
    // 魂斗罗敌人
    enemy: {
        soldier: { health: 60,  speed: 3.5, chaseSpeed: 6,  radius: 0.5, damage: 8,  fireRate: 0.8, detectionRange: 40, shootRange: 25, scoreValue: 100 },
        runner:  { health: 40,  speed: 5,   chaseSpeed: 9,  radius: 0.5, damage: 15, fireRate: 0,   detectionRange: 50, shootRange: 0,  scoreValue: 150, meleeRange: 2.5 },
        turret:  { health: 100, speed: 0,   chaseSpeed: 0,  radius: 1.0, damage: 12, fireRate: 0.5, detectionRange: 50, shootRange: 40, scoreValue: 200 },
    },
    // Boss
    bossTurret: { health: 300, damage: 15, fireRate: 0.3, shootRange: 50, scoreValue: 2000, radius: 2 },
    redFalcon:  { health: 500, damage: 20, fireRate: 0.4, shootRange: 40, scoreValue: 10000, radius: 3 },
    // 关卡
    level: {
        size: 120,
        wallHeight: 6,
    },
};

// 魂斗罗8关剧情 — 严格按原作
const LEVELS_DATA = [
    {
        name: '第1关: 丛林',
        story: '公元2633年，外星侵略者「红隼」占领了加瓦隆岛。魂斗罗部队派出精英战士 Bill Rizer，独自潜入这座被敌军占据的岛屿。第一站——丛林，必须穿越这片密林，摧毁敌军的前哨炮台。',
        storyAfter: '前哨炮台已被摧毁！前方传来瀑布的水声，继续前进。',
        env: { bg: 0x1a3320, ground: 0x2d4a1a, fog: 0x1a3320, fogDensity: 0.015 },
        enemyCount: 10,
        enemyTypes: ['soldier', 'soldier', 'runner'],
        boss: 'turret',
        layout: 'jungle',
    },
    {
        name: '第2关: 瀑布',
        story: '瀑布挡住了去路，敌军在水帘后面架起了炮台。攀上岩石，穿过瀑布，消灭那里的守军！',
        storyAfter: '瀑布阵地已突破！前方就是敌军基地。',
        env: { bg: 0x1a2a3a, ground: 0x3a4a3a, fog: 0x1a2a3a, fogDensity: 0.02 },
        enemyCount: 12,
        enemyTypes: ['soldier', 'runner', 'runner'],
        boss: 'turret',
        layout: 'waterfall',
    },
    {
        name: '第3关: 基地',
        story: '敌军基地就在前方。这里兵力密集，还有重兵把守。渗透进去，摧毁基地内的炮台！',
        storyAfter: '基地已沦陷！一座桥梁横在面前，那是通往敌后的必经之路。',
        env: { bg: 0x2a2a1a, ground: 0x4a4020, fog: 0x2a2a1a, fogDensity: 0.02 },
        enemyCount: 14,
        enemyTypes: ['soldier', 'soldier', 'runner', 'runner'],
        boss: 'turret',
        layout: 'base',
    },
    {
        name: '第4关: 桥梁',
        story: '桥梁是通往敌后的要道，敌人在这里部署了重兵和狙击手。冲过桥梁，就能直插敌后！',
        storyAfter: '桥梁已夺下！前方是敌人的第二座基地。',
        env: { bg: 0x3a2a1a, ground: 0x5a4a30, fog: 0x3a2a1a, fogDensity: 0.018 },
        enemyCount: 16,
        enemyTypes: ['soldier', 'runner', 'runner', 'turret'],
        boss: 'turret',
        layout: 'bridge',
    },
    {
        name: '第5关: 基地2',
        story: '第二座敌军基地戒备森严，铁丝网和哨塔林立。突破外围防线，摧毁基地内的炮台！',
        storyAfter: '基地2已攻陷！前方是一片洞窟，红隼的巢穴就在洞穴深处。',
        env: { bg: 0x2a2a2a, ground: 0x4a4a4a, fog: 0x2a2a2a, fogDensity: 0.022 },
        enemyCount: 16,
        enemyTypes: ['soldier', 'soldier', 'runner', 'turret'],
        boss: 'turret',
        layout: 'base2',
    },
    {
        name: '第6关: 洞窟',
        story: '洞穴中阴暗潮湿，敌人在这里设立了隐蔽的火力点。在黑暗中穿行，消灭所有守卫，摧毁洞穴深处的炮台！',
        storyAfter: '洞窟已肃清！穿过洞穴，就是红隼的最终基地。',
        env: { bg: 0x1a1a2a, ground: 0x2a2a3a, fog: 0x1a1a2a, fogDensity: 0.03 },
        enemyCount: 14,
        enemyTypes: ['runner', 'runner', 'turret', 'soldier'],
        boss: 'turret',
        layout: 'cave',
    },
    {
        name: '第7关: 最终基地',
        story: '这是红隼的最终基地，防御火力空前猛烈。突破最后的防线，摧毁基地内的炮台，红隼就在眼前！',
        storyAfter: '最终基地已摧毁！红隼出现了——那个外星侵略者的首领，最后的决战开始了！',
        env: { bg: 0x2a0a0a, ground: 0x3a1a1a, fog: 0x2a0a0a, fogDensity: 0.02 },
        enemyCount: 12,
        enemyTypes: ['soldier', 'runner', 'turret', 'turret'],
        boss: 'turret',
        layout: 'finalbase',
    },
    {
        name: '第8关: 最终决战',
        story: '红隼——那个率领外星大军侵略地球的首领，终于现身了！这个巨大的异星生物拥有无比强大的力量。消灭它，拯救地球！',
        storyAfter: '',
        env: { bg: 0x1a0000, ground: 0x2a0a0a, fog: 0x1a0000, fogDensity: 0.02 },
        enemyCount: 6,
        enemyTypes: ['runner', 'turret'],
        boss: 'redfalcon',
        layout: 'finalarena',
    },
];
