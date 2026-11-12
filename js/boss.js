/**
 * Boss — 部件制，8 关各不相同（按 FC 原作）：
 * defenseWall 防御壁（先塔后芯）/ baseCore 基地独眼核心 / gromaides 异形魔像（开口才可伤）/
 * godomuga 分幻鬼（四影对齐真身现形）/ guldaf 反重力飞碟（投放孢子）/
 * gordea 巨型装甲兵（掷圆盘+跳砸）/ finalGate 最终闸门（先塔后门芯）/ alienHeart 龙神+异形心脏
 * 部件即 可击目标：{ alive, hitX, hitY, hitZ, hitR, onHit }
 */
class Boss {
    constructor(scene, bossId, x, y, z, ctx) {
        this.scene = scene;
        this.id = bossId;
        this.ctx = ctx; // { projectiles, onScore, onDefeated, spawnMinion }
        this.position = { x, y, z };
        this.alive = true;
        this.active = false;
        this.t = 0;
        this._defeatT = -1;
        this._defeatCalled = false;
        this.parts = [];
        this.group = new THREE.Group();
        this.group.position.set(x, y, z);
        this.scene.add(this.group);
        this._mats = [];
        this['_' + 'build_' + bossId] ? this['_build_' + bossId]() : this._build_defenseWall();
        // 统一生成目标适配器
        this.targets = this.parts.map((p) => {
            const ad = {
                alive: true, hitX: 0, hitY: 0, hitZ: 0, hitR: p.r, bossPart: true,
                onHit: (dmg) => this._damagePart(p, dmg),
            };
            p.adapter = ad;
            return ad;
        });
    }

    _M(c, e) { const m = new THREE.MeshLambertMaterial({ color: c, emissive: e || 0x000000 }); this._mats.push(m); return m; }
    _box(parent, w, h, d, m, x, y, z) {
        const ms = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
        ms.position.set(x, y, z); parent.add(ms); return ms;
    }
    _sph(parent, r, m, x, y, z, seg) {
        const ms = new THREE.Mesh(new THREE.SphereGeometry(r, seg || 10, seg || 8), m);
        ms.position.set(x, y, z); parent.add(ms); return ms;
    }
    _part(name, mesh, off, r, hp, opts) {
        const p = Object.assign({
            name, mesh, off: new THREE.Vector3(off[0], off[1], off[2]), r, hp, maxHp: hp,
            alive: true, fireTimer: Utils.randomRange(0.8, 1.8), countsForHp: true, invulnWhen: null, dmgMul: 1,
        }, opts || {});
        this.parts.push(p);
        return p;
    }
    _partBy(name) { return this.parts.find((p) => p.name === name); }

    // ---------- 各 Boss 建模 ----------
    _build_defenseWall() {
        const wallM = this._M(0x5a4a30), darkM = this._M(0x3a2f1c), redM = this._M(0x8a1a1a);
        this._box(this.group, 13, 7, 1.6, wallM, 0, 3.5, 0);
        this._box(this.group, 13, 0.8, 2.0, darkM, 0, 7.2, 0);
        [-4.2, 4.2].forEach((tx, i) => {
            const tur = new THREE.Group(); tur.position.set(tx, 5.4, 0.9); this.group.add(tur);
            this._box(tur, 1.7, 1.4, 1.2, darkM, 0, 0, 0);
            const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.14, 0.14, 1.1, 8), this._M(0x1a1a1a));
            barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0, 0.8); tur.add(barrel);
            this._part('turret' + i, tur, [tx, 5.4, 0.9], 1.15, 260);
        });
        const coreMesh = this._sph(this.group, 0.85, new THREE.MeshBasicMaterial({ color: 0xff2222 }), 0, 1.6, 1.0, 12);
        this._part('core', coreMesh, [0, 1.6, 1.0], 1.0, 420, {
            invulnWhen: () => this.parts.some((p) => p.name.startsWith('turret') && p.alive),
        });
        const guard = this._box(this.group, 0.6, 0.9, 0.5, redM, 0, 7.9, 0);
        guard.name = 'decor';
    }

    _build_baseCore() {
        const m = this._M(0x3c4658), dark = this._M(0x232a38);
        this._box(this.group, 11, 8, 1.6, m, 0, 4, 0);
        [-3.8, 3.8].forEach((px, i) => {
            const pod = new THREE.Group(); pod.position.set(px, 3.2, 0.9); this.group.add(pod);
            this._box(pod, 1.6, 1.6, 1.1, dark, 0, 0, 0);
            const eye = this._sph(pod, 0.42, new THREE.MeshBasicMaterial({ color: 0xffaa00 }), 0, 0, 0.6, 8);
            eye.name = 'podEye';
            this._part('pod' + i, pod, [px, 3.2, 0.9], 1.05, 240);
        });
        const eyeMesh = this._sph(this.group, 1.15, new THREE.MeshBasicMaterial({ color: 0xff3333 }), 0, 5.6, 1.0, 14);
        this._part('eye', eyeMesh, [0, 5.6, 1.0], 1.3, 520);
        this._box(this.group, 3.2, 0.5, 0.6, dark, 0, 4.15, 1.0);
    }

    _build_gromaides() {
        const stone = this._M(0x5c5548), glow = 0xff7722;
        const head = new THREE.Group(); head.position.set(0, 5.2, 0); this.group.add(head);
        this._box(head, 3.6, 3.4, 2.2, stone, 0, 0, 0);
        [-1.2, 1.2].forEach((ex) => {
            const eye = this._sph(head, 0.28, new THREE.MeshBasicMaterial({ color: 0xffff44 }), ex, 0.7, 1.12, 8);
            eye.name = 'eye';
        });
        const mouth = this._box(head, 1.7, 0.35, 0.3, new THREE.MeshBasicMaterial({ color: 0x220a00 }), 0, -0.95, 1.12);
        mouth.name = 'mouth';
        this.mouthMesh = mouth;
        this._part('mouthCore', mouth, [0, 4.25, 1.12], 1.0, 460, {
            invulnWhen: () => !this._mouthOpen,
        });
        this._mouthOpen = false; this._mouthCycle = 0;
        [-3.4, 3.4].forEach((ax, i) => {
            const arm = new THREE.Group(); arm.position.set(ax, 3.4, 0.4); this.group.add(arm);
            this._box(arm, 1.1, 2.6, 1.1, stone, 0, -0.6, 0);
            const hand = this._sph(arm, 0.62, this._M(0x6c5a3a, 0x331a00), 0, -2.1, 0.2, 8);
            hand.name = 'hand';
            this._part('arm' + i, arm, [ax, 1.6, 0.6], 1.05, 260);
        });
        this._box(this.group, 8.5, 1.6, 2.4, stone, 0, 0.8, 0);
    }

    _build_godomuga() {
        const frame = this._M(0x3c3050);
        this._box(this.group, 10, 7.5, 1.6, frame, 0, 3.75, 0);
        this.phantoms = [];
        for (let i = 0; i < 4; i++) {
            const a = (i / 4) * Math.PI * 2;
            const g = new THREE.Group();
            g.position.set(Math.cos(a) * 2.6, 4 + Math.sin(a) * 1.6, 1.0);
            this.group.add(g);
            const core = this._sph(g, 0.72, new THREE.MeshBasicMaterial({ color: 0xbb66ff }), 0, 0, 0, 10);
            core.name = 'phantom';
            this.phantoms.push(g);
            this._part('phantom' + i, g, [g.position.x, g.position.y, 1.0], 0.9, 99999, {
                countsForHp: false,
                invulnWhen: () => true, // 幻影永远打不死，只在对齐时真身现形
            });
        }
        const trueMesh = this._sph(this.group, 0.95, new THREE.MeshBasicMaterial({ color: 0xffcc33 }), 0, 4, 1.1, 12);
        trueMesh.visible = false;
        this.trueCoreMesh = trueMesh;
        this._part('trueCore', trueMesh, [0, 4, 1.1], 1.1, 520, {
            invulnWhen: () => !this._aligned,
        });
        this._aligned = false; this._alignCycle = 3;
    }

    _build_guldaf() {
        const hullM = this._M(0x6a7a8c), dark = this._M(0x39434e);
        const ship = new THREE.Group(); ship.position.set(0, 6.2, 0); this.group.add(ship);
        this.shipGroup = ship;
        const hull = this._sph(ship, 2.5, hullM, 0, 0, 0, 14);
        hull.scale.set(1.5, 0.5, 1.1);
        this._box(ship, 7.6, 0.5, 3.4, dark, 0, -0.5, 0);
        const coreMesh = this._sph(ship, 0.95, new THREE.MeshBasicMaterial({ color: 0xff3333 }), 0, -1.15, 0, 12);
        this._part('core', coreMesh, [0, 5.05, 0], 1.15, 560);
        [-3.1, 3.1].forEach((px, i) => {
            const pod = this._sph(ship, 0.62, this._M(0x8a9aaa), px, -0.8, 0, 8);
            this._part('pod' + i, pod, [px, 5.4, 0], 0.8, 200);
        });
        this._dropTimer = 3;
    }

    _build_gordea() {
        const armor = this._M(0x7a3a22), dark = this._M(0x40241a), skin = this._M(0x9a6a4a);
        const bodyG = new THREE.Group(); this.group.add(bodyG);
        this.bodyGroup = bodyG;
        this._box(bodyG, 1.9, 2.3, 1.05, armor, 0, 2.9, 0);
        this._box(bodyG, 1.5, 1.1, 0.9, dark, 0, 1.45, 0);
        this._box(bodyG, 0.75, 0.75, 0.75, skin, 0, 4.45, 0);
        this._box(bodyG, 0.85, 0.3, 0.85, this._M(0xaa2222), 0, 4.9, 0);
        [-1.25, 1.25].forEach((ax) => this._box(bodyG, 0.5, 1.9, 0.5, armor, ax, 3.1, 0));
        [-0.55, 0.55].forEach((lx) => this._box(bodyG, 0.6, 1.6, 0.6, dark, lx, 0.1 + 0.7, 0));
        const gem = this._sph(bodyG, 0.42, new THREE.MeshBasicMaterial({ color: 0xffcc33 }), 0, 3.3, 0.58, 10);
        this._part('body', bodyG, [0, 2.9, 0], 1.75, 780);
        this._part('gem', gem, [0, 3.3, 0.58], 0.62, 780, { countsForHp: false, dmgMul: 2.2, linkedTo: 'body' });
        this._slamTimer = 4; this._slamAnim = 0; this._baseZ = this.position.z;
    }

    _build_finalGate() {
        const m = this._M(0x4c4438), dark = this._M(0x2e2a22), red = this._M(0x7a1a1a);
        this._box(this.group, 14, 8.5, 1.8, m, 0, 4.25, 0);
        [-5, 5].forEach((tx, i) => {
            const tur = new THREE.Group(); tur.position.set(tx, 6.4, 1.0); this.group.add(tur);
            this._box(tur, 1.9, 1.6, 1.3, dark, 0, 0, 0);
            const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 1.3, 8), this._M(0x111111));
            barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0, 0.9); tur.add(barrel);
            this._part('turret' + i, tur, [tx, 6.4, 1.0], 1.25, 320);
        });
        const door = this._box(this.group, 4.4, 5.6, 0.7, red, 0, 2.8, 1.0);
        door.name = 'door';
        const coreMesh = this._sph(this.group, 0.95, new THREE.MeshBasicMaterial({ color: 0xff2222 }), 0, 3.4, 1.5, 12);
        this._part('core', coreMesh, [0, 3.4, 1.5], 1.15, 520, {
            invulnWhen: () => this.parts.some((p) => p.name.startsWith('turret') && p.alive),
        });
        const mortarMesh = this._box(this.group, 1.1, 0.9, 1.1, dark, 0, 9.0, 0.6);
        this._part('mortarTop', mortarMesh, [0, 9.0, 0.6], 0.9, 220);
    }

    _build_alienHeart() {
        const flesh = this._M(0x7a1e3c, 0x1c020a), darkFlesh = this._M(0x4c1030);
        // 龙神加瓦（中Boss）：长颈龙头
        const java = new THREE.Group(); java.position.set(0, 0, 6); this.group.add(java);
        this.javaGroup = java;
        for (let i = 0; i < 4; i++) {
            const seg = this._sph(java, 0.55 - i * 0.06, darkFlesh, 0, 1 + i * 0.85, -i * 0.35, 8);
            seg.name = 'neck';
        }
        const headG = new THREE.Group(); headG.position.set(0, 4.6, -1.6); java.add(headG);
        this.javaHead = headG;
        this._box(headG, 1.15, 0.85, 1.7, flesh, 0, 0, 0);
        const jaw = this._box(headG, 0.95, 0.25, 1.4, darkFlesh, 0, -0.55, 0.15);
        jaw.name = 'jaw';
        [-0.3, 0.3].forEach((ex) => {
            const eye = this._sph(headG, 0.13, new THREE.MeshBasicMaterial({ color: 0xffff44 }), ex, 0.3, 0.7, 8);
            eye.name = 'eye';
        });
        this._part('java', headG, [0, 4.6, 4.4], 1.15, 620);
        // 异形心脏
        const heart = this._sph(this.group, 2.1, flesh, 0, 3.6, -2, 14);
        heart.scale.set(1, 1.15, 0.9);
        this.heartMesh = heart;
        this._part('heart', heart, [0, 3.6, -2], 2.2, 700, {
            invulnWhen: () => { const j = this._partBy('java'); return j && j.alive; },
        });
        [-4.6, 4.6].forEach((px, i) => {
            const pod = this._sph(this.group, 0.85, darkFlesh, px, 1.1, 1.2, 10);
            this._part('pod' + i, pod, [px, 1.1, 1.2], 1.0, 240);
        });
        this._spawnTimer = 4;
    }

    // ---------- 伤害与死亡 ----------
    _damagePart(p, dmg) {
        if (!this.alive || !p.alive) return;
        if (p.invulnWhen && p.invulnWhen()) return; // 无敌期：弹丸被挡下但不掉血
        const target = p.linkedTo ? this._partBy(p.linkedTo) : p;
        target.hp -= dmg * (p.dmgMul || 1);
        this._mats.forEach((m) => { if (m.emissive && m.emissive.getHex() === 0) m.emissive.setHex(0x333333); });
        if (target.hp <= 0 && target.alive) this._killPart(target);
        if (p !== target && p.hp <= 0 && p.alive) this._killPart(p);
    }

    _killPart(p) {
        p.alive = false;
        if (p.adapter) p.adapter.alive = false;
        if (p.mesh) {
            this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(
                this.position.x + p.off.x, this.position.y + p.off.y, this.position.z + p.off.z), 2.0);
            p.mesh.visible = false;
        }
        // 终结判定
        const finisher = {
            defenseWall: 'core', baseCore: 'eye', gromaides: 'mouthCore', godomuga: 'trueCore',
            guldaf: 'core', gordea: 'body', finalGate: 'core', alienHeart: 'heart',
        }[this.id];
        if (p.name === finisher) this._startDefeat();
    }

    _startDefeat() {
        this.alive = false;
        this._defeatT = 1.4;
        this.ctx.onScore(BOSS_DATA[this.id].score);
        for (let i = 0; i < 5; i++) {
            setTimeout(() => {
                this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(
                    this.position.x + Utils.randomRange(-3, 3),
                    this.position.y + Utils.randomRange(1, 5),
                    this.position.z + Utils.randomRange(-1, 1)), 2.6);
            }, i * 160);
        }
    }

    get hpFraction() {
        let hp = 0, max = 0;
        for (const p of this.parts) {
            if (!p.countsForHp) continue;
            max += p.maxHp; hp += Math.max(0, p.hp);
        }
        return max > 0 ? hp / max : 0;
    }

    activate() {
        if (this.active) return;
        this.active = true;
        AudioManager.bossWarn();
    }

    // ---------- 攻击工具 ----------
    _orbAt(player, from, speed, inaccuracy) {
        const target = new THREE.Vector3(
            player.position.x + Utils.randomRange(-inaccuracy, inaccuracy || 0),
            player.chestY,
            player.position.z + Utils.randomRange(-inaccuracy, inaccuracy || 0)
        );
        const dir = target.sub(from).normalize();
        this.ctx.projectiles.spawnOrb(from, dir, speed, 1);
        AudioManager.enemyShoot();
    }
    _partWorld(p, yOff) {
        return new THREE.Vector3(this.position.x + p.off.x, this.position.y + p.off.y + (yOff || 0), this.position.z + p.off.z + 0.6);
    }
    _grenadeAt(player, from) {
        const T = 1.3, G = 16;
        const vel = new THREE.Vector3(
            (player.position.x - from.x) / T,
            ((player.position.y + 0.3 - from.y) + 0.5 * G * T * T) / T,
            (player.position.z - from.z) / T
        );
        this.ctx.projectiles.spawnGrenade(from, vel, false);
        AudioManager.enemyShoot();
    }

    update(dt, player) {
        if (this._defeatT > 0) {
            this._defeatT -= dt;
            this.group.position.y = this.position.y - (1.4 - Math.max(0, this._defeatT)) * 0.8;
            if (this._defeatT <= 0 && !this._defeatCalled) {
                this._defeatCalled = true;
                this.ctx.onDefeated();
            }
            return;
        }
        if (!this.alive) return;
        this.t += dt;
        // 受击闪烁复位
        this._mats.forEach((m) => { if (m.emissive && m.emissive.getHex() !== 0) m.emissive.setHex(0x000000); });

        // 同步目标适配器
        for (const p of this.parts) {
            if (!p.adapter) continue;
            p.adapter.alive = p.alive;
            p.adapter.hitX = this.position.x + p.off.x;
            p.adapter.hitY = this.position.y + p.off.y;
            p.adapter.hitZ = this.position.z + p.off.z;
        }
        if (!this.active || !player.alive) return;

        const P = (n) => this._partBy(n);
        const fire = (p, fn) => {
            if (!p || !p.alive) return;
            p.fireTimer -= dt;
            if (p.fireTimer <= 0) fn();
        };

        switch (this.id) {
            case 'defenseWall':
            case 'finalGate': {
                ['turret0', 'turret1'].forEach((n) => fire(P(n), () => {
                    const p = P(n); p.fireTimer = Utils.randomRange(1.3, 2.0);
                    this._orbAt(player, this._partWorld(p), 18, 0.4);
                }));
                if (this.id === 'finalGate') fire(P('mortarTop'), () => {
                    const p = P('mortarTop'); p.fireTimer = 3.4;
                    this._grenadeAt(player, this._partWorld(p));
                });
                break;
            }
            case 'baseCore': {
                ['pod0', 'pod1'].forEach((n) => fire(P(n), () => {
                    const p = P(n); p.fireTimer = Utils.randomRange(1.6, 2.4);
                    this._orbAt(player, this._partWorld(p), 18, 0.4);
                }));
                fire(P('eye'), () => {
                    const p = P('eye'); p.fireTimer = 2.1;
                    const from = this._partWorld(p);
                    for (let i = -2; i <= 2; i++) {
                        const dir = new THREE.Vector3(player.position.x - from.x, player.chestY - from.y, player.position.z - from.z).normalize();
                        dir.x += i * 0.09; dir.normalize();
                        this.ctx.projectiles.spawnOrb(from.clone(), dir, 19, 1);
                    }
                    AudioManager.enemyShoot();
                });
                break;
            }
            case 'gromaides': {
                this._mouthCycle += dt;
                const cycle = this._mouthCycle % 6.5;
                this._mouthOpen = cycle > 4;
                if (this.mouthMesh) {
                    this.mouthMesh.scale.y = this._mouthOpen ? 3.2 : 1;
                    this.mouthMesh.material.color.setHex(this._mouthOpen ? 0xff5510 : 0x220a00);
                }
                ['arm0', 'arm1'].forEach((n, i) => fire(P(n), () => {
                    const p = P(n); p.fireTimer = 3.0 + i * 0.7;
                    this._grenadeAt(player, this._partWorld(p, -1.4));
                }));
                fire(P('mouthCore'), () => {
                    if (!this._mouthOpen) { P('mouthCore').fireTimer = 0.5; return; }
                    const p = P('mouthCore'); p.fireTimer = 1.5;
                    this._orbAt(player, this._partWorld(p), 20, 0.3);
                });
                break;
            }
            case 'godomuga': {
                this._alignCycle += dt;
                const cyc = this._alignCycle % 7;
                this._aligned = cyc > 5.2;
                if (this.trueCoreMesh) this.trueCoreMesh.visible = this._aligned;
                this.phantoms.forEach((g, i) => {
                    const a = (i / 4) * Math.PI * 2 + (this._aligned ? 0 : this.t * 0.9);
                    g.position.set(Math.cos(a) * (this._aligned ? 0 : 2.6), 4 + Math.sin(a) * (this._aligned ? 0 : 1.6), 1.0);
                    const part = P('phantom' + i);
                    if (part) { part.off.x = g.position.x; part.off.y = g.position.y; }
                });
                for (let i = 0; i < 4; i++) fire(P('phantom' + i), () => {
                    const p = P('phantom' + i); p.fireTimer = 2.6;
                    this._orbAt(player, this._partWorld(p), 18, 0.5);
                });
                break;
            }
            case 'guldaf': {
                if (this.shipGroup) {
                    this.shipGroup.position.x = Math.sin(this.t * 0.6) * 5.5;
                    this.shipGroup.position.y = 6.2 + Math.sin(this.t * 1.7) * 0.4;
                    const core = P('core');
                    if (core) { core.off.x = this.shipGroup.position.x; core.off.y = this.shipGroup.position.y - 1.15; }
                    ['pod0', 'pod1'].forEach((n, i) => {
                        const p = P(n);
                        if (p) { p.off.x = this.shipGroup.position.x + (i === 0 ? -3.1 : 3.1); p.off.y = this.shipGroup.position.y - 0.8; }
                    });
                }
                fire(P('core'), () => {
                    const p = P('core'); p.fireTimer = 1.9;
                    this._orbAt(player, this._partWorld(p), 19, 0.4);
                });
                this._dropTimer -= dt;
                if (this._dropTimer <= 0) {
                    this._dropTimer = P('pod0') && P('pod0').alive || P('pod1') && P('pod1').alive ? 3.2 : 5.5;
                    const from = new THREE.Vector3(this.position.x + (this.shipGroup ? this.shipGroup.position.x : 0), this.position.y + 5.2, this.position.z);
                    const vel = new THREE.Vector3(Utils.randomRange(-1, 1), -1, Utils.randomRange(2, 4));
                    this.ctx.projectiles.spawnGrenade(from, vel, false);
                }
                break;
            }
            case 'gordea': {
                // 缓步逼近 + 掷圆盘 + 近身跳砸
                const dx = player.position.x - this.position.x;
                const dz = player.position.z - this.position.z;
                const dist = Math.sqrt(dx * dx + dz * dz);
                if (this._slamAnim > 0) {
                    this._slamAnim -= dt;
                    const k = 1 - Math.max(0, this._slamAnim) / 0.55;
                    this.group.position.y = this.position.y + Math.sin(k * Math.PI) * 2.2;
                    if (this._slamAnim <= 0) {
                        this.group.position.y = this.position.y;
                        this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(this.position.x, this.position.y + 0.4, this.position.z), 3.4, 0xffaa33);
                        if (dist < 5.2 && player.grounded) player.takeDamage(1);
                    }
                } else {
                    if (dist > 7) {
                        this.position.x += (dx / dist) * 1.7 * dt;
                        this.position.z += (dz / dist) * 1.7 * dt;
                        this.group.position.x = this.position.x;
                        this.group.position.z = this.position.z;
                    }
                    this._slamTimer -= dt;
                    if (dist < 6.5 && this._slamTimer <= 0) { this._slamTimer = 4.5; this._slamAnim = 0.55; }
                }
                fire(P('body'), () => {
                    const p = P('body'); p.fireTimer = 2.3;
                    const from = new THREE.Vector3(this.position.x, this.position.y + 3.4, this.position.z + 0.8);
                    const dir = new THREE.Vector3(player.position.x - from.x, player.chestY - from.y, player.position.z - from.z).normalize();
                    this.ctx.projectiles.spawnDisc(from, dir, 16);
                    AudioManager.enemyShoot();
                });
                break;
            }
            case 'alienHeart': {
                if (this.heartMesh) {
                    const s = 1 + Math.sin(this.t * 2.4) * 0.05;
                    this.heartMesh.scale.set(s, 1.15 * s, 0.9 * s);
                }
                const java = P('java');
                if (java && java.alive) {
                    fire(java, () => {
                        java.fireTimer = 2.4;
                        const from = new THREE.Vector3(this.position.x, this.position.y + 4.4, this.position.z + 4.6);
                        this._grenadeAt(player, from);
                        this._orbAt(player, from.clone(), 18, 0.3);
                    });
                } else {
                    ['pod0', 'pod1'].forEach((n) => fire(P(n), () => {
                        const p = P(n); p.fireTimer = 2.8;
                        this._orbAt(player, this._partWorld(p), 18, 0.4);
                    }));
                    this._spawnTimer -= dt;
                    if (this._spawnTimer <= 0) {
                        this._spawnTimer = 5.5;
                        if (this.ctx.spawnMinion) {
                            this.ctx.spawnMinion('spore', this.position.x + Utils.randomRange(-4, 4), this.position.z + 7);
                        }
                    }
                    fire(P('heart'), () => {
                        const p = P('heart'); p.fireTimer = 3.4;
                        this._grenadeAt(player, this._partWorld(p));
                    });
                }
                break;
            }
        }
    }

    destroy() {
        if (this.group) { this.scene.remove(this.group); Utils.disposeObject(this.group); }
    }
}
