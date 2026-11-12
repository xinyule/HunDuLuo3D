/**
 * 关卡系统 — 地形生成、障碍物、敌人波次
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

        // 方向光（太阳）
        const sun = new THREE.DirectionalLight(0xffffff, 0.6);
        sun.position.set(50, 100, 50);
        this.scene.add(sun);

        // 天空盒颜色
        this.scene.background = new THREE.Color(env.bg);
        this.scene.fog = new THREE.FogExp2(env.fog, env.fogDensity);

        // 地面
        this._buildGround();

        // 根据布局生成场景
        const layout = this.data.layout;
        switch (layout) {
            case 'jungle': this._buildJungle(); break;
            case 'river': this._buildRiver(); break;
            case 'base': this._buildBase(); break;
            case 'bridge': this._buildBridge(); break;
            case 'base2': this._buildBase2(); break;
            case 'warehouse': this._buildWarehouse(); break;
            case 'reactor': this._buildReactor(); break;
            case 'final': this._buildFinal(); break;
            default: this._buildJungle(); break;
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

        // 地面网格纹理（简单线条）
        const gridHelper = new THREE.GridHelper(this.size, 50, 0x333333, 0x222222);
        gridHelper.position.y = 0.01;
        this.scene.add(gridHelper);
    }

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
        // 树干
        const trunkMat = new THREE.MeshLambertMaterial({ color: 0x4a3020 });
        const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.3, 3, 6), trunkMat);
        trunk.position.set(x, 1.5, z);
        this.scene.add(trunk);

        // 树冠
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

    // ===== 布局生成器 =====

    _buildJungle() {
        // 大量树木和灌木
        for (let i = 0; i < 30; i++) {
            const x = Utils.randomRange(-this.size/2 + 5, this.size/2 - 5);
            const z = Utils.randomRange(-this.size/2 + 5, this.size/2 - 5);
            this._addTree(x, z);
        }
        // 小路
        for (let i = 0; i < 10; i++) {
            this._addBox(Utils.randomRange(-30, 30), Utils.randomRange(-30, 30), 0.5, 0.5, 0.2, 0x554433);
        }
        // 围栏
        this._addWall(-30, 0, 0.5, 60, 2, 0x5a4a30);
        this._addWall(30, 0, 0.5, 60, 2, 0x5a4a30);
    }

    _buildRiver() {
        // 河流（用蓝色平面表示）
        const riverGeo = new THREE.PlaneGeometry(this.size * 0.6, 15);
        const riverMat = new THREE.MeshLambertMaterial({ color: 0x1a3a5a });
        const river = new THREE.Mesh(riverGeo, riverMat);
        river.rotation.x = -Math.PI / 2;
        river.position.set(0, 0.02, 0);
        this.scene.add(river);

        // 河岸
        this._addWall(-20, 0, 0.5, 30, 1.5, 0x4a3a20);
        this._addWall(20, 0, 0.5, 30, 1.5, 0x4a3a20);

        // 桥
        this._addBox(0, 0, 4, 20, 0.5, 0x8a6a40);

        // 树木
        for (let i = 0; i < 20; i++) {
            const side = Math.random() > 0.5 ? 1 : -1;
            this._addTree(side * Utils.randomRange(25, 45), Utils.randomRange(-35, 35));
        }
    }

    _buildBase() {
        // 营房
        this._addBuilding(-20, -10, 10, 8, 4, 0x6a5a40);
        this._addBuilding(20, 10, 8, 10, 4, 0x6a5a40);

        // 围墙
        this._addWall(-40, 0, 0.5, 80, 3, 0x666666);
        this._addWall(40, 0, 0.5, 80, 3, 0x666666);
        this._addWall(0, -40, 80, 0.5, 3, 0x666666);
        this._addWall(0, 40, 80, 0.5, 3, 0x666666);

        // 哨塔
        for (let i = 0; i < 4; i++) {
            const x = (i % 2 === 0 ? -35 : 35);
            const z = (i < 2 ? -35 : 35);
            this._addCrate(x, z, 2, 0x444444);
        }

        // 箱子
        for (let i = 0; i < 8; i++) {
            this._addCrate(Utils.randomRange(-30, 30), Utils.randomRange(-30, 30));
        }
    }

    _buildBridge() {
        // 桥面
        const bridgeGeo = new THREE.BoxGeometry(8, 0.3, 80);
        const bridgeMat = new THREE.MeshLambertMaterial({ color: 0x7a5a30 });
        const bridge = new THREE.Mesh(bridgeGeo, bridgeMat);
        bridge.position.set(0, 0.15, 0);
        this.scene.add(bridge);

        // 桥栏杆
        this._addWall(-4, 0, 0.2, 80, 1.5, 0x5a4020);
        this._addWall(4, 0, 0.2, 80, 1.5, 0x5a4020);

        // 桥下河流
        const riverGeo = new THREE.PlaneGeometry(40, 80);
        const riverMat = new THREE.MeshLambertMaterial({ color: 0x1a3a5a });
        const river = new THREE.Mesh(riverGeo, riverMat);
        river.rotation.x = -Math.PI / 2;
        river.position.set(0, -1, 0);
        this.scene.add(river);

        // 远处建筑
        this._addBuilding(-25, -30, 8, 8, 5, 0x666666);
        this._addBuilding(25, 30, 8, 8, 5, 0x666666);
    }

    _buildBase2() {
        // 铁丝网围栏
        for (let i = 0; i < 20; i++) {
            this._addCrate(-45 + i * 5, -45, 0.2, 0x888888);
        }
        for (let i = 0; i < 20; i++) {
            this._addCrate(-45 + i * 5, 45, 0.2, 0x888888);
        }
        this._addWall(-45, 0, 0.5, 90, 2, 0x777777);
        this._addWall(45, 0, 0.5, 90, 2, 0x777777);
        this._addWall(0, -45, 90, 0.5, 2, 0x777777);
        this._addWall(0, 45, 90, 0.5, 2, 0x777777);

        // 哨塔
        for (let i = 0; i < 6; i++) {
            const angle = (i / 6) * Math.PI * 2;
            const x = Math.cos(angle) * 35;
            const z = Math.sin(angle) * 35;
            this._addCrate(x, z, 2, 0x555555);
        }

        // 建筑
        this._addBuilding(-20, 0, 12, 8, 5, 0x556655);
        this._addBuilding(20, 0, 12, 8, 5, 0x556655);
    }

    _buildWarehouse() {
        // 大型仓库建筑
        this._addBuilding(0, 0, 30, 25, 8, 0x445566);

        // 内部隔断
        this._addWall(-10, 0, 20, 0.5, 4, 0x334455);
        this._addWall(10, 0, 20, 0.5, 4, 0x334455);
        this._addWall(0, -8, 0.5, 18, 4, 0x334455);

        // 箱子堆
        for (let i = 0; i < 20; i++) {
            this._addCrate(Utils.randomRange(-12, 12), Utils.randomRange(-8, 8), Utils.randomRange(0.8, 1.5));
        }

        // 油桶
        for (let i = 0; i < 8; i++) {
            const barrel = new THREE.Mesh(
                new THREE.CylinderGeometry(0.4, 0.4, 1.2, 8),
                new THREE.MeshLambertMaterial({ color: 0xcc4422 })
            );
            barrel.position.set(Utils.randomRange(-12, 12), 0.6, Utils.randomRange(-8, 8));
            this.scene.add(barrel);
            this.colliders.push({ type: 'circle', x: barrel.position.x, z: barrel.position.z, r: 0.5, h: 1.2 });
            this.objects.push(barrel);
        }
    }

    _buildReactor() {
        // 反应堆核心
        const reactorGeo = new THREE.CylinderGeometry(3, 4, 8, 8);
        const reactorMat = new THREE.MeshLambertMaterial({ color: 0x2255aa, emissive: 0x112244 });
        const reactor = new THREE.Mesh(reactorGeo, reactorMat);
        reactor.position.set(0, 4, 0);
        this.scene.add(reactor);
        this.colliders.push({ type: 'circle', x: 0, z: 0, r: 4, h: 8 });
        this.objects.push(reactor);

        // 反应堆发光环
        const ringGeo = new THREE.TorusGeometry(3.5, 0.2, 8, 32);
        const ringMat = new THREE.MeshBasicMaterial({ color: 0x4488ff });
        const ring = new THREE.Mesh(ringGeo, ringMat);
        ring.position.set(0, 6, 0);
        ring.rotation.x = Math.PI / 2;
        this.scene.add(ring);
        this.decor.push(ring);

        // 管道
        for (let i = 0; i < 6; i++) {
            const angle = (i / 6) * Math.PI * 2;
            const pipeGeo = new THREE.CylinderGeometry(0.15, 0.15, 10, 6);
            const pipeMat = new THREE.MeshLambertMaterial({ color: 0x666677 });
            const pipe = new THREE.Mesh(pipeGeo, pipeMat);
            pipe.position.set(Math.cos(angle) * 5, 2, Math.sin(angle) * 5);
            this.scene.add(pipe);
            this.decor.push(pipe);
        }

        // 墙壁
        this._addWall(-40, 0, 0.5, 80, 6, 0x334455);
        this._addWall(40, 0, 0.5, 80, 6, 0x334455);
        this._addWall(0, -40, 80, 0.5, 6, 0x334455);
        this._addWall(0, 40, 80, 0.5, 6, 0x334455);

        // 控制台
        this._addBuilding(-15, -10, 4, 3, 2, 0x446677);
        this._addBuilding(15, 10, 4, 3, 2, 0x446677);
    }

    _buildFinal() {
        // Boss 竞技场
        this._addWall(-40, 0, 0.5, 80, 6, 0x442222);
        this._addWall(40, 0, 0.5, 80, 6, 0x442222);
        this._addWall(0, -40, 80, 0.5, 6, 0x442222);
        this._addWall(0, 40, 80, 0.5, 6, 0x442222);

        // 地面标记
        const markerGeo = new THREE.RingGeometry(5, 5.5, 32);
        const markerMat = new THREE.MeshBasicMaterial({ color: 0xff3333, side: THREE.DoubleSide });
        const marker = new THREE.Mesh(markerGeo, markerMat);
        marker.rotation.x = -Math.PI / 2;
        marker.position.set(0, 0.02, 0);
        this.scene.add(marker);
        this.decor.push(marker);

        // 柱子
        for (let i = 0; i < 4; i++) {
            const angle = (i / 4) * Math.PI * 2 + Math.PI / 4;
            const x = Math.cos(angle) * 20;
            const z = Math.sin(angle) * 20;
            this._addCrate(x, z, 2, 0x552222);
        }
    }

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
            const boss = new Enemy(this.scene, 'boss', 0, -30, this);
            boss.player = Game.player;
            this.enemies.push(boss);
        }
    }

    update(deltaTime) {
        let aliveCount = 0;
        for (const enemy of this.enemies) {
            enemy.update(deltaTime, Game.player);
            if (!enemy.alive && enemy.deathTimer <= 0) {
                // 敌人完全死亡后清理
            }
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
        document.getElementById('objectiveFill').style.width = pct + '%';
        document.getElementById('enemyKilled').textContent = this.killedCount;
    }

    onComplete() {
        AudioManager.levelComplete();
        Game.onLevelComplete();
    }

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
        const lights = this.scene.children.filter(c => c.isLight);
        for (const l of lights) this.scene.remove(l);
        // 移除雾和背景
        this.scene.fog = null;
    }
}
