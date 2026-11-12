/**
 * 敌人AI系统 — 巡逻、追击、射击、死亡
 */
class Enemy {
    constructor(scene, type, x, z, level) {
        this.scene = scene;
        this.type = type; // soldier, gunner, sniper, boss
        this.level = level;
        this.position = { x, y: 1.0, z };
        this.alive = true;
        this.health = 0;
        this.speed = 0;
        this.radius = 0;
        this.damage = 0;
        this.fireRate = 0;
        this.detectionRange = 0;
        this.shootRange = 0;
        this.scoreValue = 0;

        // 设置类型属性
        if (type === 'boss') {
            const b = CONFIG.boss;
            this.health = b.health; this.speed = b.speed; this.chaseSpeed = b.chaseSpeed;
            this.radius = b.radius; this.damage = b.damage; this.fireRate = b.fireRate;
            this.detectionRange = b.detectionRange; this.shootRange = b.shootRange;
            this.scoreValue = b.scoreValue;
        } else {
            const e = CONFIG.enemy;
            this.health = e.health; this.speed = e.speed; this.chaseSpeed = e.chaseSpeed;
            this.radius = e.radius; this.damage = e.damage; this.fireRate = e.fireRate;
            this.detectionRange = e.detectionRange; this.shootRange = e.shootRange;
            this.scoreValue = e.scoreValue;

            // 特殊敌人微调
            if (type === 'gunner') { this.health = 90; this.damage = 12; this.fireRate = 0.5; this.scoreValue = 150; }
            if (type === 'sniper') { this.health = 40; this.damage = 35; this.fireRate = 1.5; this.detectionRange = 60; this.shootRange = 50; this.scoreValue = 200; }
        }
        this.maxHealth = this.health;

        // AI 状态
        this.state = 'patrol'; // patrol, chase, attack, dead
        this.patrolTarget = { x, z };
        this.patrolTimer = 0;
        this.lastShotTime = 0;
        this.lastSeenTime = 0;
        this.facing = 0; // 朝向角度

        // 创建3D模型
        this.mesh = this._createMesh(type);
        this.mesh.position.set(x, this.position.y, z);
        this.scene.add(this.mesh);

        // 血条
        this.healthBar = null;
        this._createHealthBar();

        // 死亡动画
        this.deathTimer = 0;
        this.hitFlashTimer = 0;
    }

    _createMesh(type) {
        const group = new THREE.Group();

        if (type === 'boss') {
            // Boss：大型机甲
            const bodyMat = new THREE.MeshLambertMaterial({ color: 0x8b0000 });
            const body = new THREE.Mesh(new THREE.BoxGeometry(2, 2.5, 1.5), bodyMat);
            body.position.y = 2;
            group.add(body);

            const headMat = new THREE.MeshLambertMaterial({ color: 0xff3333, emissive: 0x330000 });
            const head = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), headMat);
            head.position.y = 3.5;
            group.add(head);

            // 眼睛
            const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff0000 });
            const eye1 = new THREE.Mesh(new THREE.SphereGeometry(0.15, 8, 8), eyeMat);
            eye1.position.set(-0.25, 3.5, 0.5);
            group.add(eye1);
            const eye2 = new THREE.Mesh(new THREE.SphereGeometry(0.15, 8, 8), eyeMat);
            eye2.position.set(0.25, 3.5, 0.5);
            group.add(eye2);

            // 手臂
            const armMat = new THREE.MeshLambertMaterial({ color: 0x4a0000 });
            const arm1 = new THREE.Mesh(new THREE.BoxGeometry(0.5, 2, 0.5), armMat);
            arm1.position.set(-1.2, 2, 0);
            group.add(arm1);
            const arm2 = new THREE.Mesh(new THREE.BoxGeometry(0.5, 2, 0.5), armMat);
            arm2.position.set(1.2, 2, 0);
            group.add(arm2);

            // 腿
            const legMat = new THREE.MeshLambertMaterial({ color: 0x3a0000 });
            const leg1 = new THREE.Mesh(new THREE.BoxGeometry(0.6, 1.5, 0.6), legMat);
            leg1.position.set(-0.5, 0.75, 0);
            group.add(leg1);
            const leg2 = new THREE.Mesh(new THREE.BoxGeometry(0.6, 1.5, 0.6), legMat);
            leg2.position.set(0.5, 0.75, 0);
            group.add(leg2);
        } else {
            // 普通敌人：人形
            const color = type === 'sniper' ? 0x2a4a6a : (type === 'gunner' ? 0x6a2a2a : 0x4a4a2a);
            const bodyMat = new THREE.MeshLambertMaterial({ color });
            const body = new THREE.Mesh(new THREE.BoxGeometry(0.6, 0.9, 0.4), bodyMat);
            body.position.y = 1.05;
            group.add(body);

            // 头
            const headMat = new THREE.MeshLambertMaterial({ color: 0xccaa88 });
            const head = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.35, 0.35), headMat);
            head.position.y = 1.7;
            group.add(head);

            // 腿
            const legMat = new THREE.MeshLambertMaterial({ color: 0x2a2a2a });
            const leg1 = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.7, 0.2), legMat);
            leg1.position.set(-0.15, 0.35, 0);
            group.add(leg1);
            const leg2 = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.7, 0.2), legMat);
            leg2.position.set(0.15, 0.35, 0);
            group.add(leg2);

            // 枪
            const gunMat = new THREE.MeshLambertMaterial({ color: 0x333333 });
            const gun = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.08, 0.6), gunMat);
            gun.position.set(0, 1.1, 0.25);
            group.add(gun);
        }

        return group;
    }

    _createHealthBar() {
        const w = this.type === 'boss' ? 4 : 1.2;
        const barHeight = 0.12;
        const group = new THREE.Group();

        const bg = new THREE.Mesh(
            new THREE.PlaneGeometry(w, barHeight),
            new THREE.MeshBasicMaterial({ color: 0x330000, transparent: true, opacity: 0.7 })
        );
        bg.position.z = 0.01;
        group.add(bg);

        const fill = new THREE.Mesh(
            new THREE.PlaneGeometry(w, barHeight),
            new THREE.MeshBasicMaterial({ color: 0xff3333 })
        );
        fill.position.z = 0.02;
        fill.scale.x = 1;
        group.add(fill);
        this.healthBarFill = fill;

        this.healthBar = group;
        this.healthBar.visible = false;
        this.scene.add(this.healthBar);
    }

    _showHitEffect(point) {
        // 简单的闪光效果
        const flash = new THREE.Mesh(
            new THREE.SphereGeometry(0.3, 6, 6),
            new THREE.MeshBasicMaterial({ color: 0xff0000, transparent: true, opacity: 0.8 })
        );
        flash.position.copy(point);
        this.scene.add(flash);
        this.hitFlashTimer = 0.2;
        this._hitFlash = flash;
    }

    takeDamage(amount) {
        if (!this.alive) return;
        this.health -= amount;
        this.hitFlashTimer = 0.1;
        if (this.health <= 0) {
            this._die();
        }
    }

    _die() {
        this.alive = false;
        this.state = 'dead';
        this.deathTimer = 2.0; // 死亡动画持续时间
        AudioManager.enemyDie();
        this.player.addScore(this.scoreValue);

        // 死亡动画：倒地 + 下沉
        this._deathAnimProgress = 0;
    }

    update(deltaTime, player) {
        if (!this.alive) {
            // 死亡动画
            if (this.deathTimer > 0) {
                this.deathTimer -= deltaTime;
                this._deathAnimProgress = (2.0 - this.deathTimer) / 2.0;
                // 倒地
                this.mesh.rotation.x = this._deathAnimProgress * Math.PI / 2;
                this.mesh.position.y = this.position.y * (1 - this._deathAnimProgress * 0.5);
                this.mesh.position.z += deltaTime * 0.5; // 向后倒

                if (this._hitFlash) {
                    this._hitFlash.material.opacity -= deltaTime * 3;
                    if (this._hitFlash.material.opacity <= 0) {
                        this.scene.remove(this._hitFlash);
                        this._hitFlash = null;
                    }
                }
            }
            return;
        }

        const distToPlayer = Utils.dist(this.position, player.position);

        // 检测玩家
        if (distToPlayer < this.detectionRange) {
            this.state = 'chase';
            this.lastSeenTime = performance.now();
        } else if (this.state === 'chase' && performance.now() - this.lastSeenTime > 5000) {
            this.state = 'patrol';
            this._setNewPatrolTarget();
        }

        // 状态机
        if (this.state === 'patrol') {
            this._patrol(deltaTime);
        } else if (this.state === 'chase') {
            this._chase(deltaTime, player, distToPlayer);
        }

        // 血条朝向相机
        if (this.healthBar) {
            const showDist = this.type === 'boss' ? 100 : 30;
            this.healthBar.visible = distToPlayer < showDist;
            if (this.healthBar.visible) {
                const pct = this.health / this.maxHealth;
                this.healthBarFill.scale.x = pct;
                this.healthBarFill.position.x = -(1 - pct) * (this.type === 'boss' ? 2 : 0.6);
                this.healthBar.position.set(this.mesh.position.x, this.type === 'boss' ? 4.5 : 2.1, this.mesh.position.z);
                this.healthBar.lookAt(player.camera.position);
            }
        }

        // 命中闪光
        if (this.hitFlashTimer > 0) {
            this.hitFlashTimer -= deltaTime;
            if (this._hitFlash) {
                this._hitFlash.material.opacity = this.hitFlashTimer / 0.1 * 0.8;
            }
        }

        // 受伤闪光
        if (this.mesh.children.length > 0 && this.type !== 'boss') {
            // 身体材质闪烁
        }
    }

    _setNewPatrolTarget() {
        const range = 15;
        this.patrolTarget = {
            x: Utils.clamp(this.position.x + Utils.randomRange(-range, range), -this.level.size/2 + 5, this.level.size/2 - 5),
            z: Utils.clamp(this.position.z + Utils.randomRange(-range, range), -this.level.size/2 + 5, this.level.size/2 - 5),
        };
        this.patrolTimer = Utils.randomRange(5, 15);
    }

    _patrol(deltaTime) {
        this.patrolTimer -= deltaTime;
        if (this.patrolTimer <= 0) {
            this._setNewPatrolTarget();
        }

        const dx = this.patrolTarget.x - this.position.x;
        const dz = this.patrolTarget.z - this.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);
        if (dist > 1) {
            const nx = this.position.x + (dx / dist) * this.speed * deltaTime;
            const nz = this.position.z + (dz / dist) * this.speed * deltaTime;
            this.position.x = nx;
            this.position.z = nz;
            this.facing = Math.atan2(dx, dz);
        }

        this._updateMesh();
    }

    _chase(deltaTime, player, distToPlayer) {
        const dx = player.position.x - this.position.x;
        const dz = player.position.z - this.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        if (dist > 1) {
            const speed = distToPlayer < this.shootRange ? this.speed : this.chaseSpeed;
            const nx = this.position.x + (dx / dist) * speed * deltaTime;
            const nz = this.position.z + (dz / dist) * speed * deltaTime;
            this.position.x = nx;
            this.position.z = nz;
            this.facing = Math.atan2(dx, dz);
        }

        // 射击
        if (distToPlayer < this.shootRange && this.type !== 'sniper') {
            this._tryShoot(player, distToPlayer);
        } else if (this.type === 'sniper' && distToPlayer < this.shootRange && distToPlayer > 15) {
            this._tryShoot(player, distToPlayer);
        }

        this._updateMesh();
    }

    _tryShoot(player, dist) {
        const now = performance.now();
        if (now - this.lastShotTime < this.fireRate * 1000) return;
        this.lastShotTime = now;

        // 命中概率（距离越远命中率越低）
        const hitChance = this.type === 'sniper' ? Utils.clamp(0.8 - dist / 100, 0.2, 0.8) : Utils.clamp(0.6 - dist / 80, 0.1, 0.5);
        if (Math.random() > hitChance) return;

        // 玩家受伤
        const damage = this.type === 'sniper' ? this.damage : this.damage * Utils.randomRange(0.8, 1.2);
        player.takeDamage(damage);

        // 射击音效（简单）
        AudioManager.shoot(this.type === 'sniper' ? 300 : 180, 'sawtooth');

        // 弹道线
        const from = new THREE.Vector3(this.position.x, this.position.y + 1.2, this.position.z);
        const to = player.camera.position.clone();
        const geo = new THREE.BufferGeometry().setFromPoints([from, to]);
        const mat = new THREE.LineBasicMaterial({ color: 0xff4444, transparent: true, opacity: 0.4 });
        const line = new THREE.Line(geo, mat);
        this.scene.add(line);
        // 自动清理
        setTimeout(() => { this.scene.remove(line); }, 200);
    }

    _updateMesh() {
        this.mesh.position.set(this.position.x, this.position.y, this.position.z);
        this.mesh.rotation.y = this.facing;
    }

    destroy() {
        if (this.mesh) this.scene.remove(this.mesh);
        if (this.healthBar) this.scene.remove(this.healthBar);
        if (this._hitFlash) this.scene.remove(this._hitFlash);
    }
}
