/**
 * 关卡系统 — 魂斗罗8关场景复刻
 * 1.丛林 2.瀑布 3.基地 4.桥梁 5.基地2 6.洞窟 7.最终基地 8.最终决战
 */
class Level {
    constructor(scene, levelData, levelIndex) {
        this.scene = scene;
        this.data = levelData;
        this.index = levelIndex;
        this.size = CONFIG.level.size;
        this.enemies = [];
        this.colliders = [];
        this.objects = []; // 可破坏/交互物体
        this.decor = [];   // 装饰物
        this.lights = [];

        // 关卡完成
        this.killedCount = 0;
        this.totalEnemies = 0;
        this.completed = false;

        this._build();
    }

    _build() {
        const env = this.data.env;

        // 环境光
        const ambient = new THREE.AmbientLight(0xffffff, 0.4);
        this.scene.add(ambient);
        this.lights.push(ambient);

        // 方向光（太阳）
        const sun = new THREE.DirectionalLight(0xffffff, 0.6);
        sun.position.set(50, 100, 50);
        this.scene.add(sun);
        this.lights.push(sun);

        // 天空盒颜色
        this.scene.background = new THREE.Color(env.bg);
        this.scene.fog = new THREE.FogExp2(env.fog, env.fogDensity);

        // 地面
        this._buildGround();

        // 根据布局生成场景
        const layout = this.data.layout;
        switch (layout) {
            case 'jungle':     this._buildJungle(); break;
            case 'waterfall':  this._buildWaterfall(); break;
            case 'base':       this._buildBase(); break;
            case 'bridge':     this._buildBridge(); break;
            case 'base2':      this._buildBase2(); break;
            case 'cave':       this._buildCave(); break;
            case 'finalbase':  this._buildFinalbase(); break;
            case 'finalarena': this._buildFinalarena(); break;
            default:           this._buildJungle(); break;
        }

        // 生成敌人
        this._spawnEnemies();

        // 更新总数
        this.totalEnemies = this.enemies.length;
        document.getElementById('enemyTotal').textContent = this.totalEnemies;
    }

    _buildGround() {
        const geo = new THREE.PlaneGeometry(this.size, this.size);
        const mat = new THREE.MeshLambertMaterial({ color: this.data.env.ground });
        const ground = new THREE.Mesh(geo, mat);
        ground.rotation.x = -Math.PI / 2;
        this.scene.add(ground);
        this.decor.push(ground);

        // 地面网格纹理（简单线条）
        const gridHelper = new THREE.GridHelper(this.size, 50, 0x333333, 0x222222);
        gridHelper.position.y = 0.01;
        this.scene.add(gridHelper);
        this.decor.push(gridHelper);
    }

    // ===== 通用辅助方法 =====

    _addWall(x, z, w, d, h, color) {
        h = h || CONFIG.level.wallHeight;
        color = color || 0x555555;
        const geo = new THREE.BoxGeometry(w, h, d);
        const mat = new THREE.MeshLambertMaterial({ color });
        const wall = new THREE.Mesh(geo, mat);
        wall.position.set(x, h / 2, z);
        this.scene.add(wall);
        this.colliders.push({ type: 'box', x, z, w, d, h });
        this.objects.push(wall);
        return wall;
    }

    _addBox(x, z, w, d, h, color) {
        h = h || 1.5;
        color = color || 0x886644;
        const geo = new THREE.BoxGeometry(w, h, d);
        const mat = new THREE.MeshLambertMaterial({ color });
        const box = new THREE.Mesh(geo, mat);
        box.position.set(x, h / 2, z);
        this.scene.add(box);
        this.colliders.push({ type: 'box', x, z, w, d, h });
        this.objects.push(box);
        return box;
    }

    _addTree(x, z) {
        const trunkMat = new THREE.MeshLambertMaterial({ color: 0x4a3020 });
        const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.3, 3, 6), trunkMat);
        trunk.position.set(x, 1.5, z);
        this.scene.add(trunk);

        const leafMat = new THREE.MeshLambertMaterial({ color: 0x2a5a1a });
        const leaves = new THREE.Mesh(new THREE.SphereGeometry(1.5, 8, 8), leafMat);
        leaves.position.set(x, 3.5, z);
        this.scene.add(leaves);

        this.colliders.push({ type: 'circle', x, z, r: 0.5, h: 3 });
        this.decor.push(trunk, leaves);
    }

    _addBuilding(x, z, w, d, h, color) {
        h = h || 4;
        color = color || 0x666666;
        const geo = new THREE.BoxGeometry(w, h, d);
        const mat = new THREE.MeshLambertMaterial({ color });
        const b = new THREE.Mesh(geo, mat);
        b.position.set(x, h / 2, z);
        this.scene.add(b);
        this.colliders.push({ type: 'box', x, z, w, d, h });
        this.objects.push(b);
        return b;
    }

    _addCrate(x, z, size, color) {
        size = size || 1.0;
        color = color || 0xaa7744;
        const geo = new THREE.BoxGeometry(size, size, size);
        const mat = new THREE.MeshLambertMaterial({ color });
        const c = new THREE.Mesh(geo, mat);
        c.position.set(x, size / 2, z);
        this.scene.add(c);
        this.colliders.push({ type: 'box', x, z, w: size, d: size, h: size });
        this.objects.push(c);
        return c;
    }

    _addBarrel(x, z, color) {
        color = color || 0xcc4422;
        const barrel = new THREE.Mesh(
            new THREE.CylinderGeometry(0.4, 0.4, 1.2, 8),
            new THREE.MeshLambertMaterial({ color })
        );
        barrel.position.set(x, 0.6, z);
        this.scene.add(barrel);
        this.colliders.push({ type: 'circle', x, z, r: 0.5, h: 1.2 });
        this.objects.push(barrel);
        return barrel;
    }

    _addRock(x, z, scale) {
        scale = scale || 1;
        const rock = new THREE.Mesh(
            new THREE.DodecahedronGeometry(scale, 0),
            new THREE.MeshLambertMaterial({ color: 0x6a6a6a, flatShading: true })
        );
        rock.position.set(x, scale * 0.4, z);
        rock.rotation.set(Math.random(), Math.random(), Math.random());
        this.scene.add(rock);
        this.colliders.push({ type: 'circle', x, z, r: scale * 0.6, h: scale });
        this.decor.push(rock);
        return rock;
    }

    _addPillar(x, z, h, color) {
        h = h || 6;
        color = color || 0x554433;
        const pillar = new THREE.Mesh(
            new THREE.CylinderGeometry(0.4, 0.5, h, 8),
            new THREE.MeshLambertMaterial({ color })
        );
        pillar.position.set(x, h / 2, z);
        this.scene.add(pillar);
        this.colliders.push({ type: 'circle', x, z, r: 0.5, h });
        this.decor.push(pillar);
        return pillar;
    }

    // ===== 第1关: 丛林 =====
    _buildJungle() {
        // 大量树木 — 魂斗罗风格的密林
        for (let i = 0; i < 40; i++) {
            const x = Utils.randomRange(-this.size/2 + 5, this.size/2 - 5);
            const z = Utils.randomRange(-this.size/2 + 5, this.size/2 - 5);
            // 避开中央通道
            if (Math.abs(x) < 5 && z > -10 && z < 20) continue;
            this._addTree(x, z);
        }
        // 灌木丛/石头
        for (let i = 0; i < 15; i++) {
            this._addRock(
                Utils.randomRange(-this.size/2 + 5, this.size/2 - 5),
                Utils.randomRange(-this.size/2 + 5, this.size/2 - 5),
                Utils.randomRange(0.5, 1.5)
            );
        }
        // 木箱
        for (let i = 0; i < 10; i++) {
            this._addCrate(Utils.randomRange(-30, 30), Utils.randomRange(-30, 30));
        }
        // 外围栅栏
        this._addWall(-55, 0, 0.5, 110, 2, 0x5a4a30);
        this._addWall(55, 0, 0.5, 110, 2, 0x5a4a30);
        this._addWall(0, -55, 110, 0.5, 2, 0x5a4a30);
        this._addWall(0, 55, 110, 0.5, 2, 0x5a4a30);
    }

    // ===== 第2关: 瀑布 =====
    _buildWaterfall() {
        // 瀑布水体 — 大块蓝色平面
        const waterGeo = new THREE.PlaneGeometry(30, 50);
        const waterMat = new THREE.MeshLambertMaterial({
            color: 0x2a5a8a,
            transparent: true,
            opacity: 0.8,
        });
        const water = new THREE.Mesh(waterGeo, waterMat);
        water.rotation.x = -Math.PI / 2;
        water.position.set(-10, 0.05, 0);
        this.scene.add(water);
        this.decor.push(water);

        // 瀑布后方的水帘
        const curtainGeo = new THREE.PlaneGeometry(30, 20);
        const curtainMat = new THREE.MeshLambertMaterial({
            color: 0x6ab0ff,
            transparent: true,
            opacity: 0.5,
            side: THREE.DoubleSide,
        });
        const curtain = new THREE.Mesh(curtainGeo, curtainMat);
        curtain.position.set(-25, 10, 0);
        this.scene.add(curtain);
        this.decor.push(curtain);

        // 岩石群
        for (let i = 0; i < 20; i++) {
            const side = Math.random() > 0.3 ? 1 : -1;
            this._addRock(
                side * Utils.randomRange(5, 50),
                Utils.randomRange(-25, 25),
                Utils.randomRange(1, 3)
            );
        }

        // 石桥
        this._addBox(0, 0, 4, 30, 0.5, 0x7a6a50);

        // 树木在远处
        for (let i = 0; i < 15; i++) {
            const side = Math.random() > 0.5 ? 1 : -1;
            this._addTree(side * Utils.randomRange(35, 50), Utils.randomRange(-40, 40));
        }

        // 木箱
        for (let i = 0; i < 8; i++) {
            this._addCrate(Utils.randomRange(-30, 30), Utils.randomRange(-30, 30));
        }

        // 外围栅栏
        this._addWall(-55, 0, 0.5, 110, 2, 0x4a3a20);
        this._addWall(55, 0, 0.5, 110, 2, 0x4a3a20);
        this._addWall(0, -55, 110, 0.5, 2, 0x4a3a20);
        this._addWall(0, 55, 110, 0.5, 2, 0x4a3a20);
    }

    // ===== 第3关: 基地 =====
    _buildBase() {
        // 营房
        this._addBuilding(-20, -15, 12, 8, 4, 0x6a5a30);
        this._addBuilding(20, 15, 10, 10, 4, 0x6a5a30);
        this._addBuilding(0, -25, 8, 8, 4, 0x5a4a20);

        // 围墙
        this._addWall(-55, 0, 0.5, 110, 4, 0x666666);
        this._addWall(55, 0, 0.5, 110, 4, 0x666666);
        this._addWall(0, -55, 110, 0.5, 4, 0x666666);
        this._addWall(0, 55, 110, 0.5, 4, 0x666666);

        // 哨塔（4个角落）
        for (let i = 0; i < 4; i++) {
            const x = (i % 2 === 0 ? -45 : 45);
            const z = (i < 2 ? -45 : 45);
            this._addBuilding(x, z, 4, 4, 6, 0x444444);
        }

        // 油桶
        for (let i = 0; i < 8; i++) {
            this._addBarrel(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40));
        }

        // 木箱
        for (let i = 0; i < 12; i++) {
            this._addCrate(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40));
        }
    }

    // ===== 第4关: 桥梁 =====
    _buildBridge() {
        // 桥面
        const bridgeGeo = new THREE.BoxGeometry(10, 0.3, 100);
        const bridgeMat = new THREE.MeshLambertMaterial({ color: 0x7a5a30 });
        const bridge = new THREE.Mesh(bridgeGeo, bridgeMat);
        bridge.position.set(0, 0.15, 0);
        this.scene.add(bridge);
        this.decor.push(bridge);

        // 桥栏杆
        this._addWall(-5, 0, 0.2, 100, 1.5, 0x5a4020);
        this._addWall(5, 0, 0.2, 100, 1.5, 0x5a4020);

        // 桥下河流
        const riverGeo = new THREE.PlaneGeometry(60, 100);
        const riverMat = new THREE.MeshLambertMaterial({ color: 0x1a3a5a });
        const river = new THREE.Mesh(riverGeo, riverMat);
        river.rotation.x = -Math.PI / 2;
        river.position.set(0, -3, 0);
        this.scene.add(river);
        this.decor.push(river);

        // 远处建筑
        this._addBuilding(-30, -35, 8, 8, 5, 0x666666);
        this._addBuilding(30, 35, 8, 8, 5, 0x666666);
        this._addBuilding(-25, 30, 6, 6, 4, 0x556655);
        this._addBuilding(25, -30, 6, 6, 4, 0x556655);

        // 桥头堡
        this._addBuilding(0, -50, 6, 10, 5, 0x5a4a30);
        this._addBuilding(0, 50, 6, 10, 5, 0x5a4a30);

        // 木箱
        for (let i = 0; i < 8; i++) {
            this._addCrate(Utils.randomRange(-30, 30), Utils.randomRange(-40, 40));
        }
    }

    // ===== 第5关: 基地2 =====
    _buildBase2() {
        // 铁丝网围栏（用柱子+墙表示）
        for (let i = 0; i < 22; i++) {
            this._addPillar(-50 + i * 5, -50, 3, 0x666666);
            this._addPillar(-50 + i * 5, 50, 3, 0x666666);
        }
        this._addWall(-50, 0, 0.5, 100, 2, 0x777777);
        this._addWall(50, 0, 0.5, 100, 2, 0x777777);
        this._addWall(0, -50, 100, 0.5, 2, 0x777777);
        this._addWall(0, 50, 100, 0.5, 2, 0x777777);

        // 哨塔（6个）
        for (let i = 0; i < 6; i++) {
            const angle = (i / 6) * Math.PI * 2;
            const x = Math.cos(angle) * 40;
            const z = Math.sin(angle) * 40;
            this._addBuilding(x, z, 4, 4, 7, 0x444444);
        }

        // 建筑
        this._addBuilding(-25, 0, 14, 8, 5, 0x556655);
        this._addBuilding(25, 0, 14, 8, 5, 0x556655);
        this._addBuilding(0, -25, 10, 8, 4, 0x445544);

        // 油桶
        for (let i = 0; i < 10; i++) {
            this._addBarrel(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40), 0xcc6622);
        }

        // 木箱
        for (let i = 0; i < 10; i++) {
            this._addCrate(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40));
        }
    }

    // ===== 第6关: 洞窟 =====
    _buildCave() {
        // 洞窟内部 — 较暗，用点光源补充
        const caveLight = new THREE.PointLight(0xffaa66, 0.8, 50);
        caveLight.position.set(0, 10, 0);
        this.scene.add(caveLight);
        this.lights.push(caveLight);

        // 钟乳石（从上方垂下）
        for (let i = 0; i < 15; i++) {
            const x = Utils.randomRange(-40, 40);
            const z = Utils.randomRange(-40, 40);
            const stalactite = new THREE.Mesh(
                new THREE.ConeGeometry(Utils.randomRange(0.2, 0.5), Utils.randomRange(2, 5), 6),
                new THREE.MeshLambertMaterial({ color: 0x4a4a3a })
            );
            stalactite.position.set(x, Utils.randomRange(4, 8), z);
            this.scene.add(stalactite);
            this.decor.push(stalactite);
        }

        // 石柱
        for (let i = 0; i < 12; i++) {
            const angle = (i / 12) * Math.PI * 2;
            const r = Utils.randomRange(15, 35);
            this._addPillar(Math.cos(angle) * r, Math.sin(angle) * r, Utils.randomRange(5, 8), 0x554433);
        }

        // 岩石
        for (let i = 0; i < 20; i++) {
            this._addRock(
                Utils.randomRange(-45, 45),
                Utils.randomRange(-45, 45),
                Utils.randomRange(1, 3)
            );
        }

        // 岩壁（不规则围墙）
        for (let i = 0; i < 30; i++) {
            const angle = (i / 30) * Math.PI * 2;
            const r = 50 + Utils.randomRange(-3, 5);
            this._addWall(
                Math.cos(angle) * r,
                Math.sin(angle) * r,
                0.5,
                0.5,
                Utils.randomRange(5, 10),
                0x3a3a2a
            );
        }

        // 地面裂缝效果（深色方块）
        for (let i = 0; i < 10; i++) {
            this._addBox(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40), 1, 1, 0.1, 0x1a1a0a);
        }
    }

    // ===== 第7关: 最终基地 =====
    _buildFinalbase() {
        // 红色主题的最终基地
        // 外墙
        this._addWall(-55, 0, 0.5, 110, 5, 0x442222);
        this._addWall(55, 0, 0.5, 110, 5, 0x442222);
        this._addWall(0, -55, 110, 0.5, 5, 0x442222);
        this._addWall(0, 55, 110, 0.5, 5, 0x442222);

        // 主建筑
        this._addBuilding(0, -30, 20, 12, 6, 0x553322);
        this._addBuilding(-30, 10, 10, 10, 5, 0x442222);
        this._addBuilding(30, 10, 10, 10, 5, 0x442222);

        // 哨塔
        for (let i = 0; i < 4; i++) {
            const x = (i % 2 === 0 ? -45 : 45);
            const z = (i < 2 ? -45 : 45);
            this._addBuilding(x, z, 5, 5, 8, 0x331111);
        }

        // 油桶（红色）
        for (let i = 0; i < 12; i++) {
            this._addBarrel(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40), 0xaa2222);
        }

        // 木箱
        for (let i = 0; i < 10; i++) {
            this._addCrate(Utils.randomRange(-40, 40), Utils.randomRange(-40, 40), Utils.randomRange(0.8, 1.5), 0x8a5a20);
        }

        // 红色警戒灯
        const warnLight1 = new THREE.PointLight(0xff0000, 0.5, 30);
        warnLight1.position.set(-30, 8, -30);
        this.scene.add(warnLight1);
        this.lights.push(warnLight1);

        const warnLight2 = new THREE.PointLight(0xff0000, 0.5, 30);
        warnLight2.position.set(30, 8, 30);
        this.scene.add(warnLight2);
        this.lights.push(warnLight2);
    }

    // ===== 第8关: 最终决战（Boss竞技场） =====
    _buildFinalarena() {
        // 红色围墙
        this._addWall(-55, 0, 0.5, 110, 6, 0x331111);
        this._addWall(55, 0, 0.5, 110, 6, 0x331111);
        this._addWall(0, -55, 110, 0.5, 6, 0x331111);
        this._addWall(0, 55, 110, 0.5, 6, 0x331111);

        // Boss出场标记（红色圆环）
        const markerGeo = new THREE.RingGeometry(6, 7, 32);
        const markerMat = new THREE.MeshBasicMaterial({ color: 0xff0000, side: THREE.DoubleSide });
        const marker = new THREE.Mesh(markerGeo, markerMat);
        marker.rotation.x = -Math.PI / 2;
        marker.position.set(0, 0.02, -30);
        this.scene.add(marker);
        this.decor.push(marker);

        // 玩家区域标记
        const pMarkerGeo = new THREE.RingGeometry(3, 3.5, 32);
        const pMarkerMat = new THREE.MeshBasicMaterial({ color: 0x00ff00, side: THREE.DoubleSide });
        const pMarker = new THREE.Mesh(pMarkerGeo, pMarkerMat);
        pMarker.rotation.x = -Math.PI / 2;
        pMarker.position.set(0, 0.02, 25);
        this.scene.add(pMarker);
        this.decor.push(pMarker);

        // 竞技场柱子
        for (let i = 0; i < 4; i++) {
            const angle = (i / 4) * Math.PI * 2 + Math.PI / 4;
            const x = Math.cos(angle) * 20;
            const z = Math.sin(angle) * 20;
            this._addPillar(x, z, 8, 0x442222);
        }

        // 远景血红色灯光
        const arenaLight1 = new THREE.PointLight(0xff2200, 0.8, 40);
        arenaLight1.position.set(0, 15, -20);
        this.scene.add(arenaLight1);
        this.lights.push(arenaLight1);

        const arenaLight2 = new THREE.PointLight(0xff0000, 0.5, 30);
        arenaLight2.position.set(-30, 10, 0);
        this.scene.add(arenaLight2);
        this.lights.push(arenaLight2);

        const arenaLight3 = new THREE.PointLight(0xff0000, 0.5, 30);
        arenaLight3.position.set(30, 10, 0);
        this.scene.add(arenaLight3);
        this.lights.push(arenaLight3);
    }

    // ===== 敌人生成 =====
    _spawnEnemies() {
        const data = this.data;
        const half = this.size / 2 - 10;

        for (let i = 0; i < data.enemyCount; i++) {
            const type = data.enemyTypes[i % data.enemyTypes.length];
            // 随机位置，远离玩家初始位置
            let x, z, tries = 0;
            do {
                x = Utils.randomRange(-half, half);
                z = Utils.randomRange(-half, half);
                tries++;
            } while (Utils.dist2({ x, z }, { x: 0, z: 30 }) < 200 && tries < 20);

            const enemy = new Enemy(this.scene, type, x, z, this);
            enemy.player = Game.player;
            this.enemies.push(enemy);
        }

        // Boss
        if (data.boss) {
            const bossType = data.boss === 'redfalcon' ? 'redFalcon' : 'bossTurret';
            const boss = new Enemy(this.scene, bossType, 0, -30, this);
            boss.player = Game.player;
            this.enemies.push(boss);
        }
    }

    // ===== 更新 =====
    update(deltaTime) {
        let aliveCount = 0;
        for (const enemy of this.enemies) {
            enemy.update(deltaTime, Game.player);
            if (enemy.alive) aliveCount++;
        }

        // 检查关卡完成
        if (!this.completed && aliveCount === 0) {
            this.completed = true;
            this.onComplete();
        }

        // 更新进度
        this.killedCount = this.totalEnemies - aliveCount;
        const pct = this.totalEnemies > 0 ? (this.killedCount / this.totalEnemies) * 100 : 0;
        const fillEl = document.getElementById('objectiveFill');
        const killedEl = document.getElementById('enemyKilled');
        if (fillEl) fillEl.style.width = pct + '%';
        if (killedEl) killedEl.textContent = this.killedCount;
    }

    onComplete() {
        AudioManager.levelComplete();
        Game.onLevelComplete();
    }

    // ===== 清理 =====
    destroy() {
        for (const enemy of this.enemies) {
            enemy.destroy();
        }
        for (const obj of this.objects) {
            this.scene.remove(obj);
        }
        for (const d of this.decor) {
            this.scene.remove(d);
        }
        // 移除灯光
        for (const l of this.lights) {
            this.scene.remove(l);
        }
        // 移除雾和背景
        this.scene.fog = null;
    }
}
