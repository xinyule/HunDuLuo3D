/**
 * 关卡 — 线性走廊推进（修旧版方形竞技场随机撒怪）
 * 玩家从 z=26 向 -Z 推进至 length 米处 Boss 竞技段；
 * 敌人按路段触发分批生成；基地关有电网门+感应器， 能量区有火焰喷口，
 * 仓库有尖刺矿车，瀑布关有台阶攀爬+落石，雪原有装甲车中Boss。
 */
class GateSensor {
    constructor(scene, x, y, z, onOpen, onScore) {
        this.hp = 130; this.alive = true;
        this.hitX = x; this.hitY = y; this.hitZ = z; this.hitR = 0.85;
        this.onOpen = onOpen; this.onScore = onScore;
        const g = new THREE.Group();
        const ring = new THREE.Mesh(new THREE.TorusGeometry(0.62, 0.1, 8, 18),
            new THREE.MeshLambertMaterial({ color: 0x888888 }));
        g.add(ring);
        this.core = new THREE.Mesh(new THREE.SphereGeometry(0.42, 10, 8),
            new THREE.MeshBasicMaterial({ color: 0xff2222 }));
        g.add(this.core);
        g.position.set(x, y, z);
        this.mesh = g;
        scene.add(g);
        this.scene = scene;
    }
    onHit(dmg) {
        if (!this.alive) return;
        this.hp -= dmg;
        this.core.scale.setScalar(1 + Math.max(0, this.hp / 130) * 0.15);
        if (this.hp <= 0) {
            this.alive = false;
            this.onScore(300);
            AudioManager.gateOpen();
            this.onOpen();
        }
    }
    destroy() { if (this.mesh) { this.scene.remove(this.mesh); Utils.disposeObject(this.mesh); } }
}

class Level {
    constructor(scene, data, index, ctx) {
        this.scene = scene;
        this.data = data;
        this.index = index;
        this.ctx = ctx; // { projectiles, onScore, onPickup, onCheckpoint, onBossActivated, onBossDefeated }
        this.width = data.width;
        this.length = data.length;
        this.colliders = [];
        this.enemies = [];
        this.decor = [];
        this.objects = [];
        this.lights = [];
        this.sensors = [];
        this.gates = [];
        this.flames = [];
        this.carts = [];
        this.crushers = [];
        this.rocks = [];
        this.snow = null;
        this.bridgeCollapsed = false;
        this._bridgeMesh = null;
        this.boss = null;
        this.bossActivated = false;
        this.time = 0;
        this._rockTimer = 2.5;
        this._healDropped = false;

        this.pickups = new PickupSystem(scene, { onPickup: ctx.onPickup, onScore: ctx.onScore });
        this.enemyCtx = { projectiles: ctx.projectiles, onScore: ctx.onScore };

        // 触发队列（按推进米数）
        this.spawnQueue = data.spawns.map((s) => ({ dist: s[0], type: s[1], x: s[2], done: false }));
        if (data.midTank) this.spawnQueue.push({ dist: data.midTank, type: 'tank', x: 0, done: false });
        this.spawnQueue.sort((a, b) => a.dist - b.dist);
        this.falconQueue = (data.falcons || []).map((d, i) => ({ dist: d, letter: (data.letters || ['S'])[i % (data.letters || ['S']).length], done: false }));

        // 检查点：起点 + 每道门后 + Boss 竞技段入口
        this.checkpoints = [{ x: 0, y: 0, z: 26 }];
        (data.gates || []).forEach((gd) => this.checkpoints.push({ x: 0, y: 0, z: 26 - gd - 4, dist: gd + 4 }));
        this.checkpoints.push({ x: 0, y: 0, z: 26 - (data.length - 44), dist: data.length - 44 });
        this._cpIndex = 0;

        this._build();
    }

    playerDist(player) { return 26 - player.position.z; }

    getSupportY(x, z, fromY) {
        let best = 0;
        for (const c of this.colliders) {
            if (c.disabled || c.noCollide) continue;
            const top = (c.y0 || 0) + (c.h || 6);
            if (top > fromY + 0.55 || top <= best) continue;
            if (c.type === 'box') {
                if (Math.abs(x - c.x) <= c.w / 2 + 0.05 && Math.abs(z - c.z) <= c.d / 2 + 0.05) best = top;
            } else if (c.type === 'circle') {
                const dx = x - c.x, dz = z - c.z;
                if (dx * dx + dz * dz <= (c.r + 0.05) ** 2) best = top;
            }
        }
        return best;
    }

    // ---------------- 建造 ----------------
    _build() {
        const env = this.data.env;
        const ambient = new THREE.AmbientLight(0xffffff, 0.5);
        this.scene.add(ambient); this.lights.push(ambient);
        const sun = new THREE.DirectionalLight(env.sun, 0.75);
        sun.position.set(30, 80, 40);
        this.scene.add(sun); this.lights.push(sun);
        this.scene.background = new THREE.Color(env.bg);
        this.scene.fog = new THREE.FogExp2(env.fog, env.fogDensity);

        this._buildGroundAndWalls();
        const theme = this.data.theme;
        if (theme === 'jungle') this._themeJungle();
        else if (theme === 'base' || theme === 'base2') this._themeBase();
        else if (theme === 'waterfall') this._themeWaterfall();
        else if (theme === 'snow') this._themeSnow();
        else if (theme === 'energy') this._themeEnergy();
        else if (theme === 'hangar') this._themeHangar();
        else if (theme === 'alien') this._themeAlien();

        if (this.data.gates) this.data.gates.forEach((gd) => this._buildGate(gd));
        if (this.data.flames) this.data.flames.forEach((fd, i) => this._buildFlame(fd, i));
        if (this.data.carts) this.data.carts.forEach((cd, i) => this._buildCart(cd, i));
        if (this.data.crushers) this.data.crushers.forEach((cd, i) => this._buildCrusher(cd, i));

        // Boss（竞技段尽头）
        const bossZ = -this.length + 10;
        const bossY = this.getSupportY(0, bossZ, 999);
        const bossCtx = {
            projectiles: this.ctx.projectiles,
            onScore: this.ctx.onScore,
            onDefeated: () => this.ctx.onBossDefeated(),
            spawnMinion: (type, x, z) => this._spawnEnemy(type, x, z),
        };
        this.boss = new Boss(this.scene, this.data.boss, 0, bossY, bossZ, bossCtx);
        this.bossZ = bossZ;
        this.bossY = bossY;
    }

    _addCollider(c) { this.colliders.push(c); return c; }
    _mesh(geo, color, x, y, z, opts) {
        const m = new THREE.Mesh(geo, new THREE.MeshLambertMaterial(Object.assign({ color }, (opts && opts.mat) || {})));
        m.position.set(x, y, z);
        if (opts && opts.rot) m.rotation.set(opts.rot[0] || 0, opts.rot[1] || 0, opts.rot[2] || 0);
        this.scene.add(m);
        (opts && opts.list ? this[opts.list] : this.decor).push(m);
        return m;
    }
    _box(x, z, w, d, h, color, opts) {
        opts = opts || {};
        const y0 = opts.y0 || 0;
        const m = this._mesh(new THREE.BoxGeometry(w, h, d), color, x, y0 + h / 2, z, opts);
        if (!opts.noCollider) this._addCollider({ type: 'box', x, z, w, d, h, y0 });
        return m;
    }

    _buildGroundAndWalls() {
        const env = this.data.env;
        const L = this.length, W = this.width;
        const centerZ = 26 - L / 2;
        const ground = new THREE.Mesh(new THREE.PlaneGeometry(W + 46, L + 90),
            new THREE.MeshLambertMaterial({ color: env.ground }));
        ground.rotation.x = -Math.PI / 2;
        ground.position.set(0, -0.02, centerZ);
        this.scene.add(ground); this.decor.push(ground);

        // 两侧 containment 墙（碰撞），外观由主题装饰覆盖
        this._addCollider({ type: 'box', x: -(W / 2 + 0.6), z: centerZ, w: 1.2, d: L + 60, h: 30, y0: 0 });
        this._addCollider({ type: 'box', x: (W / 2 + 0.6), z: centerZ, w: 1.2, d: L + 60, h: 30, y0: 0 });
        this._addCollider({ type: 'box', x: 0, z: 34, w: W + 10, d: 1.2, h: 30, y0: 0 }); // 身后
        this._addCollider({ type: 'box', x: 0, z: -L - 2, w: W + 10, d: 1.2, h: 30, y0: 0 }); // 关底
    }

    _scatterCover(rand, count, maker) {
        for (let i = 0; i < count; i++) {
            const dist = 24 + rand() * (this.length - 55);
            const x = (rand() > 0.5 ? 1 : -1) * (3.5 + rand() * (this.width / 2 - 4.5));
            maker(x, 26 - dist, rand);
        }
    }

    _tree(x, z, rand, snow) {
        const trunk = this._mesh(new THREE.CylinderGeometry(0.22, 0.32, 3, 6), 0x4a3020, x, 1.5, z);
        const leafColor = snow ? 0xdfe9f2 : 0x2a5a1a;
        const leaves = this._mesh(new THREE.ConeGeometry(1.7, 3.6, 7), leafColor, x, 4.4, z);
        leaves.rotation.y = rand() * 3;
        this._addCollider({ type: 'circle', x, z, r: 0.5, h: 3 });
        return [trunk, leaves];
    }

    _themeJungle() {
        const rand = Utils.seededRandom(1101 + this.index * 77);
        const W = this.width, L = this.length;
        for (let d = 6; d < L + 20; d += 7) {
            [-1, 1].forEach((s) => {
                if (rand() > 0.25) this._tree(s * (W / 2 + 2.4 + rand() * 3), 26 - d, rand, false);
            });
        }
        this._scatterCover(rand, 12, (x, z) => this._box(x, z, 1.1, 1.1, 1.1, 0x8a6a3a));
        this._scatterCover(rand, 8, (x, z) => {
            const rock = this._mesh(new THREE.DodecahedronGeometry(0.9, 0), 0x6a6a5a, x, 0.4, z, { mat: { flatShading: true } });
            rock.rotation.set(rand() * 3, rand() * 3, 0);
            this._addCollider({ type: 'circle', x, z, r: 0.75, h: 0.9 });
        });
        // 河面 + 木桥（推进 70 米处横贯）
        const riverZ = 26 - 70;
        const river = this._mesh(new THREE.PlaneGeometry(W + 30, 11), 0x1d4e6b, 0, 0.01, riverZ, { mat: { transparent: true, opacity: 0.9 } });
        river.rotation.x = -Math.PI / 2;
        // 木桥：玩家过桥后会坍塌（原作第1关标志桥段）
        this._bridgeMesh = this._box(0, riverZ, 5.5, 12.5, 0.35, 0x7a5c33, { list: 'objects' });
        this._bridgeZ = riverZ;
    }

    _themeBase() {
        const rand = Utils.seededRandom(2202 + this.index * 77);
        const W = this.width, L = this.length;
        // 两侧金属墙面
        for (let d = 0; d < L + 30; d += 15) {
            [-1, 1].forEach((s) => {
                this._box(s * (W / 2 + 1.4), 26 - d - 7.5, 1.6, 15, 6.5, this.data.env.side, { noCollider: true });
            });
        }
        // 顶部横梁与灯带
        for (let d = 14; d < L; d += 22) {
            this._box(0, 26 - d, W + 2, 0.8, 0.5, 0x22262e, { y0: 6.2, noCollider: true });
        }
        this._scatterCover(rand, 10, (x, z) => this._box(x, z, 1.2, 1.2, 1.2, 0x707a68));
        this._scatterCover(rand, 6, (x, z) => {
            const barrel = this._mesh(new THREE.CylinderGeometry(0.42, 0.42, 1.15, 8), 0x9a3324, x, 0.58, z);
            this._addCollider({ type: 'circle', x, z, r: 0.5, h: 1.15 });
            return barrel;
        });
    }

    _themeWaterfall() {
        const rand = Utils.seededRandom(3303);
        const W = this.width, L = this.length;
        // 两侧岩壁
        for (let d = 0; d < L + 24; d += 12) {
            [-1, 1].forEach((s) => {
                const rock = this._mesh(new THREE.DodecahedronGeometry(2.6, 0), 0x55503f, s * (W / 2 + 2.6), 1.6, 26 - d, { mat: { flatShading: true } });
                rock.rotation.set(rand() * 2, rand() * 2, 0);
            });
        }
        // 台阶：从推进 28 米起，每 11 米升 1.05 米
        const stepDepth = 11, stepRise = 1.05;
        const steps = Math.floor((L - 45) / stepDepth);
        for (let i = 0; i < steps; i++) {
            const topH = (i + 1) * stepRise;
            const zC = 26 - 28 - i * stepDepth - stepDepth / 2;
            this._box(0, zC, W, stepDepth + 0.3, topH, i % 2 ? 0x605a48 : 0x57503f, { list: 'objects' });
        }
        this.terraceTopY = steps * stepRise;
        // 顶部平台（Boss 竞技段地面）：从最后一级台阶延伸到关底
        const platStartZ = 26 - 28 - steps * stepDepth;
        const platDepth = Math.abs(-L - 2 - platStartZ);
        this._box(0, platStartZ - platDepth / 2, W, platDepth, this.terraceTopY, 0x605a48, { list: 'objects' });
        // 瀑布水帘（关底岩壁前）
        const fall = this._mesh(new THREE.PlaneGeometry(9, 16), 0x6ab0ff, -W / 4, 8, -L + 4,
            { mat: { transparent: true, opacity: 0.45, side: THREE.DoubleSide } });
        fall.name = 'waterfall';
        const pool = this._mesh(new THREE.PlaneGeometry(W + 20, 12), 0x2a5a8a, 0, this.terraceTopY + 0.02, -L + 12,
            { mat: { transparent: true, opacity: 0.85 } });
        pool.rotation.x = -Math.PI / 2;
        this._scatterCover(rand, 8, (x, z) => this._box(x, z, 1.1, 1.1, 1.0, 0x6b5a35));
    }

    _themeSnow() {
        const rand = Utils.seededRandom(4404);
        const W = this.width, L = this.length;
        for (let d = 4; d < L + 20; d += 8) {
            [-1, 1].forEach((s) => {
                if (rand() > 0.3) this._tree(s * (W / 2 + 2.5 + rand() * 3), 26 - d, rand, true);
            });
        }
        // 雪堆掩体（可踩可挡）
        this._scatterCover(rand, 12, (x, z) => {
            const bank = this._mesh(new THREE.SphereGeometry(1.5, 8, 6), 0xe6eef6, x, -0.5, z);
            bank.scale.set(1.3, 0.75, 1);
            this._addCollider({ type: 'circle', x, z, r: 1.5, h: 1.1 });
        });
        this._scatterCover(rand, 6, (x, z) => this._box(x, z, 1.15, 1.15, 1.15, 0x7a6a4a));
        this._buildSnowfall();
    }

    _buildSnowfall() {
        const count = 320;
        const geo = new THREE.BufferGeometry();
        const positions = new Float32Array(count * 3);
        for (let i = 0; i < count; i++) {
            positions[i * 3] = Utils.randomRange(-this.width / 2 - 6, this.width / 2 + 6);
            positions[i * 3 + 1] = Utils.randomRange(0, 15);
            positions[i * 3 + 2] = Utils.randomRange(-this.length, 30);
        }
        geo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        const points = new THREE.Points(geo, new THREE.PointsMaterial({
            color: 0xffffff, size: 0.16, transparent: true, opacity: 0.85, depthWrite: false,
        }));
        this.scene.add(points);
        this.objects.push(points);
        this.snow = { points, positions, count };
    }

    _themeEnergy() {
        const rand = Utils.seededRandom(5505);
        const W = this.width, L = this.length;
        for (let d = 8; d < L + 16; d += 13) {
            [-1, 1].forEach((s) => {
                const pillar = this._mesh(new THREE.CylinderGeometry(0.55, 0.7, 7, 8), 0x4a3423, s * (W / 2 + 1.8), 3.5, 26 - d);
                return pillar;
            });
        }
        // 地面能量条（装饰发光线）
        for (let d = 16; d < L; d += 18) {
            const strip = this._mesh(new THREE.PlaneGeometry(W - 4, 0.5), 0xff7722, 0, 0.015, 26 - d,
                { mat: { emissive: 0x903500 } });
            strip.rotation.x = -Math.PI / 2;
        }
        this._scatterCover(rand, 8, (x, z) => this._box(x, z, 1.2, 1.2, 1.3, 0x5c4630));
    }

    _themeHangar() {
        const rand = Utils.seededRandom(6606);
        const W = this.width, L = this.length;
        for (let d = 6; d < L + 20; d += 16) {
            [-1, 1].forEach((s) => {
                this._box(s * (W / 2 + 2.2), 26 - d - 4, 3.2, 7, 3 + (Math.floor(rand() * 2)), s > 0 ? 0x746a4c : 0x5e6a72, { noCollider: true });
            });
        }
        this._scatterCover(rand, 10, (x, z) => this._box(x, z, 1.25, 1.25, 1.25, 0x8a7a4a));
        // 矿车轨道（装饰横线）
        (this.data.carts || []).forEach((cd) => {
            const rail = this._mesh(new THREE.PlaneGeometry(W + 6, 1.6), 0x2c2c2c, 0, 0.012, 26 - cd);
            rail.rotation.x = -Math.PI / 2;
        });
    }

    _themeAlien() {
        const rand = Utils.seededRandom(7707);
        const W = this.width, L = this.length;
        for (let d = 5; d < L + 16; d += 9) {
            [-1, 1].forEach((s) => {
                const blob = this._mesh(new THREE.SphereGeometry(1.9 + rand() * 1.2, 9, 7), 0x5c1c38, s * (W / 2 + 2.2), 1.2, 26 - d,
                    { mat: { emissive: 0x1c020a } });
                blob.scale.y = 1.25;
            });
        }
        // 肋骨拱门
        for (let d = 20; d < L - 10; d += 26) {
            const arch = this._mesh(new THREE.TorusGeometry(W / 2 + 0.5, 0.35, 7, 14, Math.PI), 0x8a3a5c, 0, 0, 26 - d);
            arch.rotation.z = 0;
            arch.name = 'rib';
        }
        this._scatterCover(rand, 8, (x, z) => {
            const egg = this._mesh(new THREE.SphereGeometry(0.8, 8, 7), 0x9a4a6a, x, 0.55, z, { mat: { emissive: 0x22040e } });
            egg.scale.y = 1.25;
            this._addCollider({ type: 'circle', x, z, r: 0.8, h: 1.2 });
        });
    }

    // ---------------- 机关 ----------------
    _buildGate(dist) {
        const z = 26 - dist, W = this.width;
        const frameM = 0x394048;
        this._box(-(W / 2 - 1), z, 2, 1, 6, frameM, { list: 'objects' });
        this._box((W / 2 - 1), z, 2, 1, 6, frameM, { list: 'objects' });
        this._box(0, z, W, 1, 1, frameM, { y0: 5, list: 'objects' });
        // 电网面
        const field = new THREE.Mesh(new THREE.PlaneGeometry(W - 4, 5),
            new THREE.MeshBasicMaterial({ color: 0x33ccff, transparent: true, opacity: 0.4, side: THREE.DoubleSide, depthWrite: false }));
        field.position.set(0, 2.5, z);
        this.scene.add(field); this.objects.push(field);
        const collider = this._addCollider({ type: 'box', x: 0, z, w: W - 3.4, d: 0.9, h: 5.2, y0: 0 });
        const sensor = new GateSensor(this.scene, 0, 3.1, z + 0.8, () => {
            collider.disabled = true;
            field.visible = false;
            sensor.mesh.visible = false;
            this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(0, 3, z + 0.8), 2.2, 0x66d9ff);
            this.pickups.spawnLetter(2.5, 3.4, z - 3.5, '+');
        }, this.ctx.onScore);
        this.sensors.push(sensor);
        this.gates.push({ dist, z, field, collider, sensor, open: false });
    }

    _buildFlame(dist, i) {
        const z = 26 - dist;
        const x = (i % 2 === 0 ? -1 : 1) * this.width * 0.18;
        const base = this._mesh(new THREE.CylinderGeometry(0.55, 0.7, 0.5, 8), 0x553311, x, 0.25, z);
        const flame = new THREE.Mesh(new THREE.ConeGeometry(0.85, 4.4, 8),
            new THREE.MeshBasicMaterial({ color: 0xff6a1a, transparent: true, opacity: 0.85 }));
        flame.position.set(x, 2.4, z);
        flame.visible = false;
        this.scene.add(flame); this.objects.push(flame);
        const warn = new THREE.Mesh(new THREE.SphereGeometry(0.3, 6, 6),
            new THREE.MeshBasicMaterial({ color: 0xffcc33, transparent: true, opacity: 0 }));
        warn.position.set(x, 0.8, z);
        this.scene.add(warn); this.objects.push(warn);
        this.flames.push({ x, z, flame, warn, period: 3.4, phase: i * 1.3, erupting: false });
    }

    _buildCart(dist, i) {
        const z = 26 - dist;
        const g = new THREE.Group();
        const bodyM = new THREE.MeshLambertMaterial({ color: 0x6a6a72 });
        const body = new THREE.Mesh(new THREE.BoxGeometry(3.2, 1.3, 1.9), bodyM);
        body.position.y = 0.95; g.add(body);
        const spikeM = new THREE.MeshLambertMaterial({ color: 0xb9b9c4 });
        [-1, 1].forEach((s) => {
            for (let k = -1; k <= 1; k++) {
                const spike = new THREE.Mesh(new THREE.ConeGeometry(0.16, 0.8, 6), spikeM);
                spike.rotation.z = s > 0 ? -Math.PI / 2 : Math.PI / 2;
                spike.position.set(s * 1.95, 0.95, k * 0.55);
                g.add(spike);
            }
        });
        [-1.1, 1.1].forEach((wx) => [-0.7, 0.7].forEach((wz) => {
            const wheel = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.15, 8), new THREE.MeshLambertMaterial({ color: 0x222222 }));
            wheel.rotation.x = Math.PI / 2;
            wheel.position.set(wx, 0.3, wz);
            g.add(wheel);
        }));
        g.position.set(0, 0, z);
        this.scene.add(g); this.objects.push(g);
        const collider = this._addCollider({ type: 'box', x: 0, z, w: 3.4, d: 2, h: 1.7, y0: 0 });
        this.carts.push({ group: g, collider, z, phase: i * 2.1, speed: 0.55 + i * 0.12, hitCooldown: 0 });
    }

    _buildCrusher(dist, i) {
        // 仓库压顶机：悬停→预警抖动→砸落→停留→升起，周期循环
        const z = 26 - dist;
        const g = new THREE.Group();
        const steel = new THREE.MeshLambertMaterial({ color: 0x7a4a2a });
        const dark = new THREE.MeshLambertMaterial({ color: 0x3a3630 });
        [-2.9, 2.9].forEach((px) => {
            const pillar = new THREE.Mesh(new THREE.BoxGeometry(0.6, 6.4, 0.6), dark);
            pillar.position.set(px, 3.2, 0); g.add(pillar);
        });
        const beam = new THREE.Mesh(new THREE.BoxGeometry(6.4, 0.7, 3.2), dark);
        beam.position.y = 6.4; g.add(beam);
        const press = new THREE.Group();
        const block = new THREE.Mesh(new THREE.BoxGeometry(5.2, 1.15, 3), steel);
        press.add(block);
        for (let k = -2; k <= 2; k++) {
            const tooth = new THREE.Mesh(new THREE.ConeGeometry(0.18, 0.5, 4), dark);
            tooth.rotation.x = Math.PI;
            tooth.position.set(k * 1.1, -0.8, 0);
            press.add(tooth);
        }
        press.position.y = 5.6;
        g.add(press);
        g.position.set(0, 0, z);
        this.scene.add(g); this.objects.push(g);
        this.crushers.push({ group: g, press, z, period: 4.4, phase: i * 1.5, state: 'up', groundY: 0 });
    }

    // ---------------- 生成 ----------------
    _spawnEnemy(type, x, z) {
        let y = this.getSupportY(x, z, 999);
        if (type === 'sniper') {
            // 狙击手上平台（平台基底坐在当前地面上）
            const plat = this._box(x, z, 1.9, 1.9, 2.2, 0x5c5648, { list: 'objects', y0: y });
            plat.name = 'sniperPlat';
            y = y + 2.2;
        }
        const e = new Enemy(this.scene, type, x, y, z, this.enemyCtx);
        this.enemies.push(e);
        return e;
    }

    spawnMinion(type, x, z) { return this._spawnEnemy(type, x, z); }

    getTargets() {
        const out = [];
        for (const e of this.enemies) if (e.alive) out.push(e);
        if (this.boss) out.push(...this.boss.targets);
        for (const s of this.sensors) if (s.alive) out.push(s);
        const f = this.pickups.getFalconTarget();
        if (f) out.push(f);
        return out;
    }

    get bossActive() { return this.bossActivated && this.boss && this.boss.alive; }
    get bossFraction() { return this.boss ? this.boss.hpFraction : 0; }
    get bossName() { return BOSS_DATA[this.data.boss].name; }

    // ---------------- 更新 ----------------
    update(dt, player, cameraPos) {
        this.time += dt;
        const dist = this.playerDist(player);

        // 敌人分批触发
        for (const s of this.spawnQueue) {
            if (!s.done && dist >= s.dist - 30) {
                s.done = true;
                this._spawnEnemy(s.type, s.x, 26 - s.dist);
            }
        }
        // 飞鹰触发
        for (const f of this.falconQueue) {
            if (!f.done && dist >= f.dist) {
                f.done = true;
                this.pickups.spawnFalcon(player.position.z - 20, f.letter, this.width / 2);
            }
        }
        // 检查点
        while (this._cpIndex < this.checkpoints.length - 1) {
            const cp = this.checkpoints[this._cpIndex + 1];
            if ((cp.dist !== undefined && dist >= cp.dist) || (cp.dist === undefined && dist >= 0)) {
                this._cpIndex++;
                const y = this.getSupportY(cp.x, cp.z, 999);
                this.ctx.onCheckpoint({ x: cp.x, y, z: cp.z });
            } else break;
        }

        // 敌人
        for (let i = this.enemies.length - 1; i >= 0; i--) {
            const e = this.enemies[i];
            if (e.update(dt, player, cameraPos)) {
                e.destroy();
                this.enemies.splice(i, 1);
            }
        }

        // Boss 竞技段触发
        if (!this.bossActivated && dist >= this.length - 42) {
            this.bossActivated = true;
            const barrierZ = this.bossZ + 27;
            const wall = new THREE.Mesh(new THREE.PlaneGeometry(this.width, 6),
                new THREE.MeshBasicMaterial({ color: 0xff3344, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false }));
            wall.position.set(0, this.bossY + 3, barrierZ);
            this.scene.add(wall); this.objects.push(wall);
            this._addCollider({ type: 'box', x: 0, z: barrierZ, w: this.width, d: 0.7, h: 8, y0: this.bossY });
            this.boss.activate();
            this.ctx.onBossActivated(this.boss);
            const y = this.getSupportY(0, barrierZ - 4, 999);
            this.ctx.onCheckpoint({ x: 0, y, z: barrierZ - 4 });
            this.pickups.spawnHeal(3, barrierZ - 6);
        }
        if (this.boss) this.boss.update(dt, player);

        // 电网脉动
        for (const g of this.gates) {
            if (g.sensor.alive) g.field.material.opacity = 0.3 + Math.sin(this.time * 7) * 0.12;
            if (!g.sensor.alive) g.open = true;
        }

        // 火焰喷口（节拍：预警→喷发→休止）
        for (const f of this.flames) {
            const t = (this.time + f.phase) % f.period;
            f.erupting = t > 1.3 && t < 2.5;
            f.warn.material.opacity = (t > 0.8 && t <= 1.3) ? 0.8 : 0;
            f.flame.visible = f.erupting;
            if (f.erupting && player.alive) {
                const dx = player.position.x - f.x, dz = player.position.z - f.z;
                const gy = this.getSupportY(f.x, f.z, 999);
                if (dx * dx + dz * dz < 1.7 && player.position.y < gy + 3.4) player.takeDamage(1);
            }
        }

        // 矿车往复
        for (const c of this.carts) {
            const x = Math.sin(this.time * c.speed + c.phase) * (this.width / 2 - 3.4);
            c.group.position.x = x;
            c.collider.x = x;
            if (c.hitCooldown > 0) c.hitCooldown -= dt;
            if (player.alive && c.hitCooldown <= 0) {
                const dx = player.position.x - x, dz = player.position.z - c.z;
                if (Math.abs(dx) < 2.2 && Math.abs(dz) < 1.9 && player.position.y < 1.9) {
                    c.hitCooldown = 1;
                    if (player.takeDamage(1)) player.position.z += 2.6;
                }
            }
        }

        // 瀑布落石
        if (this.data.theme === 'waterfall' && player.alive) {
            this._rockTimer -= dt;
            if (this._rockTimer <= 0 && dist > 20 && dist < this.length - 45) {
                this._rockTimer = Utils.randomRange(2.2, 3.6);
                const z = player.position.z - 26;
                const mesh = this._mesh(new THREE.DodecahedronGeometry(0.55, 0), 0x6a6250, Utils.randomRange(-this.width / 2 + 3, this.width / 2 - 3), 0, z, { mat: { flatShading: true }, list: 'objects' });
                this.rocks.push({ mesh, speed: 8.5, t: 0 });
            }
        }
        for (let i = this.rocks.length - 1; i >= 0; i--) {
            const r = this.rocks[i];
            r.t += dt;
            r.mesh.position.z += r.speed * dt;
            r.mesh.position.y = this.getSupportY(r.mesh.position.x, r.mesh.position.z, r.mesh.position.y + 2) + 0.5;
            r.mesh.rotation.x -= dt * 6;
            const dx = player.position.x - r.mesh.position.x, dz = player.position.z - r.mesh.position.z;
            if (player.alive && dx * dx + dz * dz < 1.15 && Math.abs(player.position.y - r.mesh.position.y) < 1.6) {
                player.takeDamage(1);
                this.scene.remove(r.mesh); Utils.disposeObject(r.mesh);
                this.rocks.splice(i, 1);
                continue;
            }
            if (r.t > 7 || r.mesh.position.z > player.position.z + 14) {
                this.scene.remove(r.mesh); Utils.disposeObject(r.mesh);
                this.rocks.splice(i, 1);
            }
        }

        // 丛林断桥：玩家过桥后坍塌
        if (this._bridgeMesh && !this.bridgeCollapsed && player.position.z < this._bridgeZ - 8) {
            this.bridgeCollapsed = true;
            this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(0, 0.6, this._bridgeZ), 2.4, 0x6ab0ff);
        }
        if (this._bridgeMesh && this.bridgeCollapsed && this._bridgeMesh.position.y > -1.6) {
            this._bridgeMesh.position.y -= dt * 1.8;
            this._bridgeMesh.rotation.x += dt * 0.25;
        }

        // 仓库压顶机周期
        for (const c of this.crushers) {
            const t = (this.time + c.phase) % c.period;
            let y;
            if (t < 1.7) { y = 5.6; c.state = 'up'; }
            else if (t < 2.1) { y = 5.6 + Math.sin(this.time * 40) * 0.05; c.state = 'warn'; }
            else if (t < 2.32) {
                y = 5.6 - (t - 2.1) / 0.22 * 4.45;
                if (c.state !== 'slam' && t > 2.26) {
                    c.state = 'slam';
                    if (player.alive) {
                        const dx = player.position.x, dz = player.position.z - c.z;
                        if (Math.abs(dx) < 2.9 && Math.abs(dz) < 1.9 && player.position.y < c.groundY + 1.3) {
                            player.takeDamage(1);
                        }
                    }
                    this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(0, c.groundY + 0.3, c.z), 1.6, 0xcc9966);
                }
            }
            else if (t < 3.0) { y = 1.15; c.state = 'hold'; }
            else { y = 1.15 + (t - 3.0) / (c.period - 3.0) * 4.45; c.state = 'rise'; }
            c.press.position.y = y;
        }

        // 雪原降雪
        if (this.snow) {
            const pos = this.snow.positions;
            for (let i = 0; i < this.snow.count; i++) {
                pos[i * 3 + 1] -= dt * 2.3;
                pos[i * 3] += Math.sin(this.time * 1.3 + i) * dt * 0.5;
                if (pos[i * 3 + 1] < 0) {
                    pos[i * 3 + 1] = 14;
                    pos[i * 3 + 2] = player.position.z + Utils.randomRange(-70, 15);
                    pos[i * 3] = player.position.x + Utils.randomRange(-this.width / 2 - 4, this.width / 2 + 4);
                }
            }
            this.snow.points.geometry.attributes.position.needsUpdate = true;
        }

        this.pickups.update(dt, player, this);
    }

    destroy() {
        for (const e of this.enemies) e.destroy();
        this.enemies = [];
        if (this.boss) { this.boss.destroy(); this.boss = null; }
        for (const s of this.sensors) s.destroy();
        this.pickups.destroy();
        for (const o of this.objects) { this.scene.remove(o); Utils.disposeObject(o); }
        for (const d of this.decor) { this.scene.remove(d); Utils.disposeObject(d); }
        for (const l of this.lights) this.scene.remove(l);
        this.scene.fog = null;
    }
}
