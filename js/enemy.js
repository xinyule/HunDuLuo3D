/**
 * 敌人 — 岗位制 AI，全类型发射实体弹丸（慢速红弹，可躲）
 * 类型：rifleman 步兵 / runner 红衣冲锋 / sniper 狙击手 / mortar 迫击炮 /
 *       turret 地堡炮台 / roller 滚雷 / spore 异形幼体 / tank 装甲扫讨车（中Boss）
 * 可击接口：alive / hitX / hitY / hitZ / hitR / onHit(dmg, point)
 */
class Enemy {
    constructor(scene, type, x, y, z, ctx) {
        this.scene = scene;
        this.type = type;
        this.ctx = ctx; // { projectiles, onScore }
        this.position = { x, y, z };
        const d = ENEMY_DATA[type];
        this.hp = d.hp; this.maxHp = d.hp;
        this.radius = d.radius; this.scoreValue = d.score;
        this.alive = true;
        this.deathT = 0;
        this.t = Math.random() * 10;
        this.fireTimer = Utils.randomRange(0.5, 1.4);
        this.burstLeft = 0;
        this.meleeTimer = 0;
        this.facing = Math.PI;
        this._flashT = 0;
        this._scored = false;

        this.hitX = x; this.hitY = y + 1; this.hitZ = z; this.hitR = d.radius + 0.3;
        if (type === 'tank') { this.hitY = y + 1.7; this.hitR = 2.1; }
        if (type === 'turret') { this.hitY = y + 0.9; this.hitR = 1.0; }

        this.mesh = this._buildMesh();
        this.mesh.position.set(x, y, z);
        this.scene.add(this.mesh);
        this._buildHealthBar();
    }

    // ---------- 建模（代码拼装低模） ----------
    _buildMesh() {
        const g = new THREE.Group();
        const mat = (c) => new THREE.MeshLambertMaterial({ color: c });
        this._mats = [];
        const M = (c) => { const m = mat(c); this._mats.push(m); return m; };
        const box = (w, h, d, m, x, y, z) => {
            const ms = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
            ms.position.set(x, y, z); g.add(ms); return ms;
        };
        if (this.type === 'rifleman' || this.type === 'sniper') {
            const uni = this.type === 'sniper' ? 0x5a4a6a : 0x4a5a2a;
            box(0.55, 0.7, 0.35, M(uni), 0, 1.05, 0);
            box(0.32, 0.32, 0.32, M(0xc9a06a), 0, 1.58, 0);
            box(0.38, 0.12, 0.38, M(0x556633), 0, 1.76, 0);
            box(0.18, 0.6, 0.18, M(0x3a3a1a), -0.14, 0.3, 0);
            box(0.18, 0.6, 0.18, M(0x3a3a1a), 0.14, 0.3, 0);
            const gun = box(0.08, 0.1, this.type === 'sniper' ? 0.95 : 0.55, M(0x222222), 0.3, 1.15, 0.3);
            if (this.type === 'sniper') gun.position.z = 0.5;
        } else if (this.type === 'runner') {
            box(0.5, 0.65, 0.32, M(0x8a2020), 0, 1.0, 0);
            box(0.3, 0.3, 0.3, M(0xc9a06a), 0, 1.5, 0);
            box(0.33, 0.1, 0.33, M(0xcc1010), 0, 1.62, 0);
            box(0.17, 0.55, 0.17, M(0x5a1010), -0.13, 0.27, 0);
            box(0.17, 0.55, 0.17, M(0x5a1010), 0.13, 0.27, 0);
            box(0.04, 0.04, 0.3, M(0xaaaaaa), 0.25, 1.0, 0.25);
        } else if (this.type === 'mortar') {
            box(0.6, 0.75, 0.4, M(0x6a5a2a), 0, 1.05, 0);
            box(0.32, 0.32, 0.32, M(0xc9a06a), 0, 1.6, 0);
            box(0.38, 0.14, 0.38, M(0x776644), 0, 1.78, 0);
            box(0.18, 0.6, 0.18, M(0x4a3a1a), -0.15, 0.3, 0);
            box(0.18, 0.6, 0.18, M(0x4a3a1a), 0.15, 0.3, 0);
            const tube = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.13, 0.8, 8), M(0x333333));
            tube.position.set(0.45, 0.75, 0.2); tube.rotation.z = -0.5; g.add(tube);
            box(0.5, 0.25, 0.5, M(0x444444), 0.45, 0.12, 0.2);
        } else if (this.type === 'turret') {
            const base = new THREE.Mesh(new THREE.CylinderGeometry(0.85, 1.05, 0.6, 8), M(0x555555));
            base.position.y = 0.3; g.add(base);
            const head = new THREE.Group(); head.position.y = 0.95; g.add(head);
            this.headGroup = head;
            const hb = new THREE.Mesh(new THREE.BoxGeometry(1.05, 0.65, 0.85), M(0x445544));
            head.add(hb);
            const bMat = M(0x222222);
            [-0.22, 0.22].forEach((bx) => {
                const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.75, 6), bMat);
                barrel.rotation.x = Math.PI / 2; barrel.position.set(bx, 0, 0.55); head.add(barrel);
            });
            const eye = new THREE.Mesh(new THREE.SphereGeometry(0.1, 6, 6), new THREE.MeshBasicMaterial({ color: 0xff2222 }));
            eye.position.set(0, 0.12, 0.43); head.add(eye);
        } else if (this.type === 'roller') {
            const ball = new THREE.Mesh(new THREE.SphereGeometry(0.45, 10, 8), M(0x3a3a3a));
            ball.position.y = 0.45; g.add(ball); this.rollerBall = ball;
            const eye = new THREE.Mesh(new THREE.SphereGeometry(0.12, 6, 6), new THREE.MeshBasicMaterial({ color: 0xff2222 }));
            eye.position.set(0, 0.55, 0.38); g.add(eye);
            for (let i = 0; i < 6; i++) {
                const a = (i / 6) * Math.PI * 2;
                const spike = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.25, 5), M(0x777777));
                spike.position.set(Math.cos(a) * 0.45, 0.45 + Math.sin(a) * 0.45, 0);
                spike.rotation.z = -a + Math.PI / 2;
                g.add(spike);
            }
        } else if (this.type === 'spore') {
            const bodyM = M(0x7a2a4a);
            const body = new THREE.Mesh(new THREE.SphereGeometry(0.42, 8, 7), bodyM);
            body.position.y = 0.55; body.scale.y = 0.85; g.add(body);
            const eyeM = new THREE.MeshBasicMaterial({ color: 0xffff66 });
            [-0.15, 0.15].forEach((ex) => {
                const eye = new THREE.Mesh(new THREE.SphereGeometry(0.07, 6, 6), eyeM);
                eye.position.set(ex, 0.68, 0.34); g.add(eye);
            });
            for (let i = 0; i < 4; i++) {
                const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.07, 0.55, 5), M(0x4a1030));
                const a = (i / 4) * Math.PI * 2 + 0.4;
                leg.position.set(Math.cos(a) * 0.35, 0.25, Math.sin(a) * 0.35);
                leg.rotation.z = Math.cos(a) * 0.5; leg.rotation.x = -Math.sin(a) * 0.5;
                g.add(leg);
            }
        } else if (this.type === 'tank') {
            const hull = box(3.6, 1.1, 2.4, M(0x5a4a6a), 0, 0.95, 0);
            hull.name = 'hull';
            box(3.9, 0.5, 2.7, M(0x333340), 0, 0.3, 0);
            const tur = new THREE.Group(); tur.position.set(0, 1.7, 0); g.add(tur);
            this.headGroup = tur;
            const tb = new THREE.Mesh(new THREE.BoxGeometry(1.6, 0.7, 1.4), M(0x6a5a7a));
            tur.add(tb);
            const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.13, 0.13, 1.5, 8), M(0x222222));
            barrel.rotation.x = Math.PI / 2; barrel.position.set(0, 0, 1.2); tur.add(barrel);
            const eye = new THREE.Mesh(new THREE.SphereGeometry(0.14, 6, 6), new THREE.MeshBasicMaterial({ color: 0xff2222 }));
            eye.position.set(0, 0.2, 0.72); tur.add(eye);
        }
        return g;
    }

    _buildHealthBar() {
        const isBig = this.type === 'tank';
        const w = isBig ? 3.4 : 1.15;
        const group = new THREE.Group();
        const bg = new THREE.Mesh(new THREE.PlaneGeometry(w, 0.13), new THREE.MeshBasicMaterial({ color: 0x220000, transparent: true, opacity: 0.75, depthWrite: false }));
        group.add(bg);
        const fill = new THREE.Mesh(new THREE.PlaneGeometry(w, 0.13), new THREE.MeshBasicMaterial({ color: 0xff4444, depthWrite: false }));
        fill.position.z = 0.01; group.add(fill);
        this.hpFill = fill; this.hpW = w;
        this.hpBar = group;
        group.visible = false;
        this.scene.add(group);
    }

    onHit(dmg) {
        if (!this.alive) return;
        this.hp -= dmg;
        this._flashT = 0.08;
        this._mats.forEach((m) => { if (m.emissive) m.emissive.setHex(0x555555); });
        if (this.hp <= 0) this._die();
    }

    _die() {
        this.alive = false;
        this.deathT = 0.85;
        AudioManager.enemyDie();
        if (!this._scored) { this._scored = true; this.ctx.onScore(this.scoreValue); }
        if (this.hpBar) this.hpBar.visible = false;
        if (this.type === 'roller') {
            // 滚雷被打爆也在原地炸开（不伤玩家除非贴身）
            this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(this.position.x, this.position.y + 0.5, this.position.z), 1.8);
        }
    }

    _muzzlePos(h) {
        const fx = Math.sin(this.facing), fz = Math.cos(this.facing);
        return new THREE.Vector3(this.position.x + fx * 0.6, this.position.y + h, this.position.z + fz * 0.6);
    }

    _fireOrb(player, speed, height, inaccuracy) {
        const from = this._muzzlePos(height);
        const target = new THREE.Vector3(
            player.position.x + Utils.randomRange(-inaccuracy, inaccuracy),
            player.chestY + Utils.randomRange(-0.15, 0.25),
            player.position.z + Utils.randomRange(-inaccuracy, inaccuracy)
        );
        const dir = target.sub(from).normalize();
        this.ctx.projectiles.spawnOrb(from, dir, speed, 1);
        AudioManager.enemyShoot();
    }

    _fireGrenade(player) {
        const from = this._muzzlePos(1.1);
        const T = 1.35, G = 16;
        const dx = player.position.x - from.x, dz = player.position.z - from.z;
        const dy = (player.position.y + 0.3) - from.y;
        const vel = new THREE.Vector3(dx / T, (dy + 0.5 * G * T * T) / T, dz / T);
        this.ctx.projectiles.spawnGrenade(from, vel, false);
        AudioManager.enemyShoot();
    }

    /** 返回 true 表示可清理 */
    update(dt, player, cameraPos) {
        if (!this.alive) {
            this.deathT -= dt;
            const k = Math.max(0, this.deathT / 0.85);
            this.mesh.rotation.x = (1 - k) * (Math.PI / 2) * 0.9;
            this.mesh.position.y = this.position.y - (1 - k) * 0.35;
            return this.deathT <= 0;
        }
        this.t += dt;
        if (this._flashT > 0) {
            this._flashT -= dt;
            if (this._flashT <= 0) this._mats.forEach((m) => { if (m.emissive) m.emissive.setHex(0x000000); });
        }
        if (this.meleeTimer > 0) this.meleeTimer -= dt;

        const dx = player.position.x - this.position.x;
        const dz = player.position.z - this.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);
        const d = ENEMY_DATA[this.type];
        this.facing = Math.atan2(dx, dz);

        switch (this.type) {
            case 'rifleman': {
                this.fireTimer -= dt;
                if (this.fireTimer <= 0 && dist < d.range && player.alive) {
                    this.fireTimer = d.fireInterval * Utils.randomRange(0.85, 1.2);
                    this._fireOrb(player, d.orbSpeed, 1.25, 0.5);
                }
                break;
            }
            case 'sniper': {
                this.fireTimer -= dt;
                if (this.fireTimer <= 0 && dist < d.range && player.alive) {
                    this.fireTimer = d.fireInterval;
                    this._fireOrb(player, d.orbSpeed, 1.3, 0.25);
                }
                break;
            }
            case 'mortar': {
                this.fireTimer -= dt;
                if (this.fireTimer <= 0 && dist < d.range && player.alive) {
                    this.fireTimer = d.fireInterval * Utils.randomRange(0.9, 1.15);
                    this._fireGrenade(player);
                }
                break;
            }
            case 'turret': {
                if (this.headGroup) this.headGroup.rotation.y = this.facing - this.mesh.rotation.y;
                if (dist < d.range && player.alive) {
                    if (this.burstLeft > 0) {
                        this.fireTimer -= dt;
                        if (this.fireTimer <= 0) {
                            this.fireTimer = d.fireInterval;
                            this.burstLeft--;
                            this._fireOrb(player, d.orbSpeed, 1.05, 0.4);
                        }
                    } else {
                        this.fireTimer -= dt;
                        if (this.fireTimer <= 0) { this.burstLeft = d.burst; this.fireTimer = 0; }
                    }
                    if (this.burstLeft === 0 && this.fireTimer <= 0) this.fireTimer = d.burstPause;
                }
                break;
            }
            case 'runner':
            case 'spore': {
                const meleeR = d.meleeRange || 1.6;
                if (dist > meleeR && player.alive) {
                    const sp = d.speed || 5;
                    this.position.x += (dx / dist) * sp * dt;
                    this.position.z += (dz / dist) * sp * dt;
                } else if (player.alive && this.meleeTimer <= 0) {
                    this.meleeTimer = d.meleeCooldown || 0.9;
                    player.takeDamage(1);
                }
                break;
            }
            case 'roller': {
                if (player.alive && dist > 0.01) {
                    const sp = d.speed;
                    this.position.x += (dx / dist) * sp * dt;
                    this.position.z += (dz / dist) * sp * dt;
                }
                if (this.rollerBall) this.rollerBall.rotation.x -= dt * 9;
                if (dist < (d.explodeRange || 1.9) && player.alive) {
                    this.ctx.projectiles.spawnExplosionFX(new THREE.Vector3(this.position.x, this.position.y + 0.5, this.position.z), 2.3);
                    if (dist < 2.4) player.takeDamage(1);
                    this.hp = 0; this._die();
                }
                break;
            }
            case 'tank': {
                // 在关底前横向巡逻，炮口对玩家三连散射
                this.position.x = Math.sin(this.t * 0.45) * 7.5;
                if (this.headGroup) this.headGroup.rotation.y = this.facing - this.mesh.rotation.y;
                this.fireTimer -= dt;
                if (this.fireTimer <= 0 && dist < d.range && player.alive) {
                    this.fireTimer = d.fireInterval;
                    for (let i = -1; i <= 1; i++) {
                        const from = this._muzzlePos(1.8);
                        const dir = new THREE.Vector3(dx, (player.chestY - from.y), dz).normalize();
                        const right = new THREE.Vector3(-dir.z, 0, dir.x);
                        dir.addScaledVector(right, i * 0.12).normalize();
                        this.ctx.projectiles.spawnOrb(from, dir, d.orbSpeed, 1);
                    }
                    AudioManager.enemyShoot();
                }
                break;
            }
        }

        // 同步变换与可击点
        this.mesh.position.set(this.position.x, this.position.y, this.position.z);
        this.mesh.rotation.y = (this.type === 'turret' || this.type === 'tank') ? 0 : this.facing;
        if (this.type === 'spore') this.mesh.position.y = this.position.y + Math.abs(Math.sin(this.t * 9)) * 0.22;
        this.hitX = this.position.x; this.hitZ = this.position.z;
        this.hitY = this.position.y + (this.type === 'tank' ? 1.7 : this.type === 'turret' ? 0.95 : 1.0);

        // 血条
        if (this.hpBar) {
            const show = this.hp < this.maxHp && dist < 55;
            this.hpBar.visible = show;
            if (show) {
                const pct = Math.max(0, this.hp / this.maxHp);
                this.hpFill.scale.x = pct;
                this.hpFill.position.x = -(1 - pct) * this.hpW / 2;
                this.hpBar.position.set(this.position.x, this.position.y + (this.type === 'tank' ? 3.1 : 2.15), this.position.z);
                this.hpBar.lookAt(cameraPos);
            }
        }
        return false;
    }

    destroy() {
        if (this.mesh) { this.scene.remove(this.mesh); Utils.disposeObject(this.mesh); }
        if (this.hpBar) { this.scene.remove(this.hpBar); Utils.disposeObject(this.hpBar); }
    }
}
