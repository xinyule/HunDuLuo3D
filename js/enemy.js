/**
 * 敌人AI系统 — 魂斗罗风格
 * soldier(远程射击) / runner(近战冲锋) / turret(固定炮台)
 * bossTurret(大型炮台Boss) / redFalcon(最终Boss)
 */
class Enemy {
    constructor(scene, type, x, z, level) {
        this.scene = scene;
        this.type = type;
        this.level = level;
        this.position = { x, y: 0, z };
        this.alive = true;
        this.health = 0;
        this.maxHealth = 0;
        this.speed = 0;
        this.chaseSpeed = 0;
        this.radius = 0;
        this.damage = 0;
        this.fireRate = 0;
        this.detectionRange = 0;
        this.shootRange = 0;
        this.scoreValue = 0;
        this.meleeRange = 0;

        // 类型属性
        this._applyType(type);

        // AI 状态
        this.state = 'patrol';
        this.patrolTarget = { x, z };
        this.patrolTimer = 0;
        this.lastShotTime = 0;
        this.lastSeenTime = 0;
        this.facing = 0;

        // 射击模式
        this.burstCount = 0;      // 当前点射剩余发数
        this.burstTimer = 0;      // 点射间隔
        this.burstCooldown = 0;   // 点射冷却

        // Boss 特殊攻击
        this.specialTimer = 0;
        this.phase = 0;

        // 模型
        this.mesh = this._createMesh(type);
        this.mesh.position.set(x, 0, z);
        this.scene.add(this.mesh);

        // 血条
        this.healthBar = null;
        this._createHealthBar();

        // 死亡/命中效果
        this.deathTimer = 0;
        this.hitFlashTimer = 0;
        this._hitFlash = null;
        this._bodyMats = []; // 用于命中闪白
    }

    _applyType(type) {
        const e = CONFIG.enemy;
        if (type === 'soldier') {
            this.health = e.soldier.health; this.speed = e.soldier.speed; this.chaseSpeed = e.soldier.chaseSpeed;
            this.radius = e.soldier.radius; this.damage = e.soldier.damage; this.fireRate = e.soldier.fireRate;
            this.detectionRange = e.soldier.detectionRange; this.shootRange = e.soldier.shootRange;
            this.scoreValue = e.soldier.scoreValue;
        } else if (type === 'runner') {
            this.health = e.runner.health; this.speed = e.runner.speed; this.chaseSpeed = e.runner.chaseSpeed;
            this.radius = e.runner.radius; this.damage = e.runner.damage; this.fireRate = e.runner.fireRate;
            this.detectionRange = e.runner.detectionRange; this.shootRange = e.runner.shootRange;
            this.scoreValue = e.runner.scoreValue; this.meleeRange = e.runner.meleeRange;
        } else if (type === 'turret') {
            this.health = e.turret.health; this.speed = e.turret.speed; this.chaseSpeed = e.turret.chaseSpeed;
            this.radius = e.turret.radius; this.damage = e.turret.damage; this.fireRate = e.turret.fireRate;
            this.detectionRange = e.turret.detectionRange; this.shootRange = e.turret.shootRange;
            this.scoreValue = e.turret.scoreValue;
        } else if (type === 'bossTurret') {
            const b = CONFIG.bossTurret;
            this.health = b.health; this.damage = b.damage; this.fireRate = b.fireRate;
            this.shootRange = b.shootRange; this.scoreValue = b.scoreValue; this.radius = b.radius;
            this.detectionRange = 80; this.speed = 0; this.chaseSpeed = 0;
        } else if (type === 'redFalcon') {
            const b = CONFIG.redFalcon;
            this.health = b.health; this.damage = b.damage; this.fireRate = b.fireRate;
            this.shootRange = b.shootRange; this.scoreValue = b.scoreValue; this.radius = b.radius;
            this.detectionRange = 100; this.speed = 1.5; this.chaseSpeed = 2.5;
        }
        this.maxHealth = this.health;
    }

    // ===== 模型创建 =====
    _createMesh(type) {
        const group = new THREE.Group();
        if (type === 'soldier') this._buildSoldier(group);
        else if (type === 'runner') this._buildRunner(group);
        else if (type === 'turret') this._buildTurret(group);
        else if (type === 'bossTurret') this._buildBossTurret(group);
        else if (type === 'redFalcon') this._buildRedFalcon(group);
        else this._buildSoldier(group);
        return group;
    }

    _buildSoldier(group) {
        // 魂斗罗敌兵：绿色军装 + 钢盔
        const uniformMat = new THREE.MeshLambertMaterial({ color: 0x4a5a2a });
        this._bodyMats.push(uniformMat);
        const body = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.7, 0.35), uniformMat);
        body.position.y = 1.05;
        group.add(body);

        // 头
        const skinMat = new THREE.MeshLambertMaterial({ color: 0xc9a06a });
        this._bodyMats.push(skinMat);
        const head = new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.32, 0.32), skinMat);
        head.position.y = 1.6;
        group.add(head);

        // 钢盔
        const helmetMat = new THREE.MeshLambertMaterial({ color: 0x556633 });
        this._bodyMats.push(helmetMat);
        const helmet = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.12, 0.38), helmetMat);
        helmet.position.y = 1.78;
        group.add(helmet);

        // 腿
        const legMat = new THREE.MeshLambertMaterial({ color: 0x3a3a1a });
        this._bodyMats.push(legMat);
        const legL = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.6, 0.18), legMat);
        legL.position.set(-0.14, 0.3, 0);
        group.add(legL);
        const legR = new THREE.Mesh(new THREE.BoxGeometry(0.18, 0.6, 0.18), legMat);
        legR.position.set(0.14, 0.3, 0);
        group.add(legR);

        // 枪
        const gunMat = new THREE.MeshLambertMaterial({ color: 0x222222 });
        const gun = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.1, 0.55), gunMat);
        gun.position.set(0.3, 1.15, 0.2);
        group.add(gun);
    }

    _buildRunner(group) {
        // 冲锋兵：红色装束，速度快，不射击
        const uniformMat = new THREE.MeshLambertMaterial({ color: 0x8a2020 });
        this._bodyMats.push(uniformMat);
        const body = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.65, 0.32), uniformMat);
        body.position.y = 1.0;
        group.add(body);

        const skinMat = new THREE.MeshLambertMaterial({ color: 0xc9a06a });
        this._bodyMats.push(skinMat);
        const head = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.3, 0.3), skinMat);
        head.position.y = 1.5;
        group.add(head);

        // 红色头巾
        const bandMat = new THREE.MeshLambertMaterial({ color: 0xcc1010 });
        this._bodyMats.push(bandMat);
        const band = new THREE.Mesh(new THREE.BoxGeometry(0.33, 0.1, 0.33), bandMat);
        band.position.y = 1.62;
        group.add(band);

        const legMat = new THREE.MeshLambertMaterial({ color: 0x5a1010 });
        this._bodyMats.push(legMat);
        const legL = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.55, 0.17), legMat);
        legL.position.set(-0.13, 0.27, 0);
        group.add(legL);
        const legR = new THREE.Mesh(new THREE.BoxGeometry(0.17, 0.55, 0.17), legMat);
        legR.position.set(0.13, 0.27, 0);
        group.add(legR);

        // 匕首
        const knifeMat = new THREE.MeshLambertMaterial({ color: 0xaaaaaa });
        const knife = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.04, 0.3), knifeMat);
        knife.position.set(0.25, 1.0, 0.25);
        group.add(knife);
    }

    _buildTurret(group) {
        // 固定炮台：底座 + 双管
        const baseMat = new THREE.MeshLambertMaterial({ color: 0x555555 });
        this._bodyMats.push(baseMat);
        const base = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 1.0, 0.6, 8), baseMat);
        base.position.y = 0.3;
        group.add(base);

        // 炮塔主体
        const turretMat = new THREE.MeshLambertMaterial({ color: 0x444444 });
        this._bodyMats.push(turretMat);
        const turret = new THREE.Mesh(new THREE.BoxGeometry(1.0, 0.7, 0.8), turretMat);
        turret.position.y = 1.0;
        group.add(turret);

        // 双管
        const barrelMat = new THREE.MeshLambertMaterial({ color: 0x222222 });
        const barrelL = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.7, 6), barrelMat);
        barrelL.rotation.x = Math.PI / 2;
        barrelL.position.set(-0.2, 1.0, 0.55);
        group.add(barrelL);
        const barrelR = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.7, 6), barrelMat);
        barrelR.rotation.x = Math.PI / 2;
        barrelR.position.set(0.2, 1.0, 0.55);
        group.add(barrelR);

        // 红色瞄准眼
        const eyeMat = new THREE.MeshBasicMaterial({ color: 0xff0000 });
        const eye = new THREE.Mesh(new THREE.SphereGeometry(0.1, 6, 6), eyeMat);
        eye.position.set(0, 1.15, 0.4);
        group.add(eye);
    }

    _buildBossTurret(group) {
        // 大型炮台Boss：巨型底座 + 多管 + 装甲
        const baseMat = new THREE.MeshLambertMaterial({ color: 0x6a1a1a });
        this._bodyMats.push(baseMat);
        const base = new THREE.Mesh(new THREE.CylinderGeometry(2.5, 3.0, 1.2, 8), baseMat);
        base.position.y = 0.6;
        group.add(base);

        // 装甲主体
        const armorMat = new THREE.MeshLambertMaterial({ color: 0x8a2a2a });
        this._bodyMats.push(armorMat);
        const armor = new THREE.Mesh(new THREE.BoxGeometry(3, 2, 2), armorMat);
        armor.position.y = 2.0;
        group.add(armor);

        // 三管炮
        const barrelMat = new THREE.MeshLambertMaterial({ color: 0x1a1a1a });
        for (let i = 0; i < 3; i++) {
            const barrel = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 1.2, 8), barrelMat);
            barrel.rotation.x = Math.PI / 2;
            barrel.position.set((i - 1) * 0.5, 2.2, 1.3);
            group.add(barrel);
        }

        // 红色核心
        const coreMat = new THREE.MeshBasicMaterial({ color: 0xff3300 });
        const core = new THREE.Mesh(new THREE.SphereGeometry(0.4, 8, 8), coreMat);
        core.position.set(0, 2.5, 0.8);
        group.add(core);

        // 炮塔可旋转部分引用
        this._turretHead = armor;
    }

    _buildRedFalcon(group) {
        // 红隼：巨型异星生物，多眼 + 触手 + 红色甲壳
        // 主体（甲壳）
        const shellMat = new THREE.MeshLambertMaterial({ color: 0x8a0a2a, emissive: 0x2a0008 });
        this._bodyMats.push(shellMat);
        const shell = new THREE.Mesh(new THREE.SphereGeometry(1.8, 10, 8), shellMat);
        shell.position.y = 2.5;
        shell.scale.y = 0.8;
        group.add(shell);

        // 头部
        const headMat = new THREE.MeshLambertMaterial({ color: 0xaa1a3a, emissive: 0x330011 });
        this._bodyMats.push(headMat);
        const head = new THREE.Mesh(new THREE.SphereGeometry(1.0, 8, 8), headMat);
        head.position.y = 3.8;
        group.add(head);

        // 多眼
        const eyeMat = new THREE.MeshBasicMaterial({ color: 0xffff00 });
        const eyePositions = [
            [-0.35, 3.9, 0.7], [0.35, 3.9, 0.7], [0, 4.1, 0.6],
            [-0.2, 3.7, 0.85], [0.2, 3.7, 0.85],
        ];
        eyePositions.forEach(pos => {
            const eye = new THREE.Mesh(new THREE.SphereGeometry(0.14, 6, 6), eyeMat);
            eye.position.set(pos[0], pos[1], pos[2]);
            group.add(eye);
        });

        // 触手/臂
        const armMat = new THREE.MeshLambertMaterial({ color: 0x6a0a1a });
        this._bodyMats.push(armMat);
        for (let i = 0; i < 4; i++) {
            const angle = (i / 4) * Math.PI * 2;
            const arm = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.35, 2.2, 6), armMat);
            arm.position.set(Math.cos(angle) * 1.8, 2.2, Math.sin(angle) * 1.8);
            arm.rotation.z = Math.cos(angle) * 0.4;
            arm.rotation.x = Math.sin(angle) * 0.4;
            group.add(arm);
        }

        // 下部支撑腿
        const legMat = new THREE.MeshLambertMaterial({ color: 0x4a0a1a });
        this._bodyMats.push(legMat);
        for (let i = 0; i < 3; i++) {
            const angle = (i / 3) * Math.PI * 2;
            const leg = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.5, 1.5, 6), legMat);
            leg.position.set(Math.cos(angle) * 1.2, 0.75, Math.sin(angle) * 1.2);
            group.add(leg);
        }

        // 嘴/獠牙
        const mouthMat = new THREE.MeshLambertMaterial({ color: 0x1a0000 });
        const mouth = new THREE.Mesh(new THREE.BoxGeometry(0.8, 0.3, 0.4), mouthMat);
        mouth.position.set(0, 3.5, 0.8);
        group.add(mouth);
    }

    _createHealthBar() {
        const isBoss = this.type === 'bossTurret' || this.type === 'redFalcon';
        const w = isBoss ? 4 : 1.2;
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
        group.add(fill);
        this.healthBarFill = fill;

        this.healthBar = group;
        this.healthBar.visible = false;
        this.scene.add(this.healthBar);
    }

    _showHitEffect(point) {
        if (this._hitFlash) {
            this.scene.remove(this._hitFlash);
            this._hitFlash = null;
        }
        const flash = new THREE.Mesh(
            new THREE.SphereGeometry(0.3, 6, 6),
            new THREE.MeshBasicMaterial({ color: 0xffff00, transparent: true, opacity: 0.9 })
        );
        flash.position.copy(point);
        this.scene.add(flash);
        this.hitFlashTimer = 0.15;
        this._hitFlash = flash;
    }

    // 命中闪白（身体材质）
    _flashBody() {
        for (const mat of this._bodyMats) {
            mat.emissive = new THREE.Color(0x666666);
        }
    }
    _unflashBody() {
        for (const mat of this._bodyMats) {
            mat.emissive = new THREE.Color(0x000000);
        }
    }

    takeDamage(amount) {
        if (!this.alive) return;
        this.health -= amount;
        this.hitFlashTimer = 0.1;
        this._flashBody();
        setTimeout(() => { if (this.alive) this._unflashBody(); }, 80);
        if (this.health <= 0) {
            this._die();
        }
    }

    _die() {
        this.alive = false;
        this.state = 'dead';
        this.deathTimer = 2.0;
        AudioManager.enemyDie();
        if (this.player) this.player.addScore(this.scoreValue);
        this._deathAnimProgress = 0;

        // Boss 死亡特效
        if (this.type === 'bossTurret' || this.type === 'redFalcon') {
            this._spawnDeathExplosion();
        }
    }

    _spawnDeathExplosion() {
        // 简单爆炸：多个红色球扩散
        for (let i = 0; i < 8; i++) {
            const ball = new THREE.Mesh(
                new THREE.SphereGeometry(0.4, 6, 6),
                new THREE.MeshBasicMaterial({ color: 0xff4400, transparent: true, opacity: 0.9 })
            );
            ball.position.set(this.position.x, 1.5, this.position.z);
            this.scene.add(ball);
            const angle = (i / 8) * Math.PI * 2;
            const vx = Math.cos(angle) * 4;
            const vy = Math.random() * 5 + 2;
            const vz = Math.sin(angle) * 4;
            const start = performance.now();
            const animate = () => {
                const t = (performance.now() - start) / 1000;
                if (t > 0.8) { this.scene.remove(ball); return; }
                ball.position.x += vx * 0.016;
                ball.position.y += vy * 0.016;
                ball.position.z += vz * 0.016;
                vy -= 15 * 0.016;
                ball.material.opacity = 0.9 * (1 - t / 0.8);
                requestAnimationFrame(animate);
            };
            animate();
        }
    }

    update(deltaTime, player) {
        if (!this.alive) {
            if (this.deathTimer > 0) {
                this.deathTimer -= deltaTime;
                this._deathAnimProgress = (2.0 - this.deathTimer) / 2.0;
                this.mesh.rotation.x = this._deathAnimProgress * Math.PI / 2;
                this.mesh.position.y = this.position.y * (1 - this._deathAnimProgress * 0.5);
            }
            if (this._hitFlash) {
                this._hitFlash.material.opacity -= deltaTime * 6;
                if (this._hitFlash.material.opacity <= 0) {
                    this.scene.remove(this._hitFlash);
                    this._hitFlash = null;
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

        // 血条
        if (this.healthBar) {
            const isBoss = this.type === 'bossTurret' || this.type === 'redFalcon';
            const showDist = isBoss ? 100 : 30;
            this.healthBar.visible = distToPlayer < showDist;
            if (this.healthBar.visible) {
                const pct = this.health / this.maxHealth;
                this.healthBarFill.scale.x = pct;
                this.healthBarFill.position.x = -(1 - pct) * (isBoss ? 2 : 0.6);
                this.healthBar.position.set(this.mesh.position.x, isBoss ? 5.5 : 2.1, this.mesh.position.z);
                this.healthBar.lookAt(player.camera.position);
            }
        }

        // 命中闪光
        if (this.hitFlashTimer > 0) {
            this.hitFlashTimer -= deltaTime;
            if (this._hitFlash) {
                this._hitFlash.material.opacity = (this.hitFlashTimer / 0.15) * 0.9;
            }
        }

        // Boss 旋转炮塔朝向玩家
        if (this.type === 'bossTurret' && this._turretHead) {
            const dx = player.position.x - this.position.x;
            const dz = player.position.z - this.position.z;
            this._turretHead.rotation.y = Math.atan2(dx, dz);
        }
    }

    _setNewPatrolTarget() {
        const range = 15;
        const half = this.level.size / 2 - 5;
        this.patrolTarget = {
            x: Utils.clamp(this.position.x + Utils.randomRange(-range, range), -half, half),
            z: Utils.clamp(this.position.z + Utils.randomRange(-range, range), -half, half),
        };
        this.patrolTimer = Utils.randomRange(5, 15);
    }

    _patrol(deltaTime) {
        this.patrolTimer -= deltaTime;
        if (this.patrolTimer <= 0) this._setNewPatrolTarget();

        const dx = this.patrolTarget.x - this.position.x;
        const dz = this.patrolTarget.z - this.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);
        if (dist > 1) {
            this.position.x += (dx / dist) * this.speed * deltaTime;
            this.position.z += (dz / dist) * this.speed * deltaTime;
            this.facing = Math.atan2(dx, dz);
        }
        this._updateMesh();
    }

    _chase(deltaTime, player, distToPlayer) {
        const dx = player.position.x - this.position.x;
        const dz = player.position.z - this.position.z;
        const dist = Math.sqrt(dx * dx + dz * dz);

        if (this.type === 'runner') {
            // 近战冲锋：冲到玩家身边攻击
            if (dist > this.meleeRange) {
                this.position.x += (dx / dist) * this.chaseSpeed * deltaTime;
                this.position.z += (dz / dist) * this.chaseSpeed * deltaTime;
                this.facing = Math.atan2(dx, dz);
            } else {
                // 近战攻击
                const now = performance.now();
                if (now - this.lastShotTime > 800) {
                    this.lastShotTime = now;
                    player.takeDamage(this.damage);
                    AudioManager.hurt();
                }
            }
        } else if (this.type === 'turret' || this.type === 'bossTurret' || this.type === 'redFalcon') {
            // 固定/慢速Boss：原地射击
            if (this.type === 'redFalcon' && dist > 15) {
                this.position.x += (dx / dist) * this.chaseSpeed * deltaTime;
                this.position.z += (dz / dist) * this.chaseSpeed * deltaTime;
                this.facing = Math.atan2(dx, dz);
            }
            this._tryShoot(player, distToPlayer);
        } else {
            // soldier：保持距离射击，太近则后退
            if (dist > this.shootRange * 0.6) {
                this.position.x += (dx / dist) * this.chaseSpeed * deltaTime;
                this.position.z += (dz / dist) * this.chaseSpeed * deltaTime;
                this.facing = Math.atan2(dx, dz);
            } else if (dist < this.shootRange * 0.3) {
                this.position.x -= (dx / dist) * this.speed * deltaTime;
                this.position.z -= (dz / dist) * this.speed * deltaTime;
                this.facing = Math.atan2(dx, dz);
            }
            this._tryShoot(player, distToPlayer);
        }

        this._updateMesh();
    }

    _tryShoot(player, dist) {
        if (dist > this.shootRange) return;
        const now = performance.now();

        // 点射模式（turret/boss）
        if (this.type === 'turret' || this.type === 'bossTurret' || this.type === 'redFalcon') {
            if (this.burstCooldown > 0) {
                this.burstCooldown -= 1 / 60; // 粗略递减
            }
            if (this.burstCount > 0) {
                if (now - this.lastShotTime < this.fireRate * 1000) return;
                this.lastShotTime = now;
                this._fireBurst(player, dist);
                this.burstCount--;
                return;
            }
            if (this.burstCooldown <= 0) {
                this.burstCount = this.type === 'redFalcon' ? 5 : (this.type === 'bossTurret' ? 3 : 3);
                this.burstCooldown = this.type === 'redFalcon' ? 1.6 : (this.type === 'bossTurret' ? 1.4 : 1.8);
            }
            return;
        }

        // soldier 单发
        if (now - this.lastShotTime < this.fireRate * 1000) return;
        this.lastShotTime = now;
        this._fireSingle(player, dist);
    }

    _fireSingle(player, dist) {
        const hitChance = Utils.clamp(0.55 - dist / 100, 0.1, 0.5);
        const from = new THREE.Vector3(this.position.x, 1.2, this.position.z);
        const to = player.camera.position.clone();

        if (Math.random() < hitChance) {
            player.takeDamage(this.damage * Utils.randomRange(0.8, 1.2));
        }

        AudioManager.shoot(180, 'sawtooth');
        this._createTracer(from, to, 0xff4444);
    }

    _fireBurst(player, dist) {
        const from = new THREE.Vector3(this.position.x, this.type === 'redFalcon' ? 3.5 : 2.2, this.position.z);
        const to = player.camera.position.clone();

        // Boss 散射
        if (this.type === 'bossTurret' || this.type === 'redFalcon') {
            const spread = this.type === 'redFalcon' ? 5 : 3;
            for (let i = 0; i < spread; i++) {
                const angle = (i - (spread - 1) / 2) * 0.25;
                const dir = to.clone().sub(from).normalize();
                const right = new THREE.Vector3(1, 0, 0);
                right.applyQuaternion(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 1, 0), this.facing));
                dir.add(right.multiplyScalar(angle));
                dir.normalize();
                const end = from.clone().add(dir.multiplyScalar(60));

                const hitChance = Utils.clamp(0.4 - dist / 120, 0.08, 0.35);
                if (Math.random() < hitChance) {
                    player.takeDamage(this.damage * Utils.randomRange(0.8, 1.2));
                }
                this._createTracer(from, end, 0xff3300);
            }
        } else {
            // turret 单发点射
            const hitChance = Utils.clamp(0.5 - dist / 100, 0.1, 0.45);
            if (Math.random() < hitChance) {
                player.takeDamage(this.damage * Utils.randomRange(0.8, 1.2));
            }
            this._createTracer(from, to, 0xff4444);
        }

        AudioManager.shoot(this.type === 'redFalcon' ? 120 : 160, 'sawtooth');
    }

    _createTracer(from, to, color) {
        const geo = new THREE.BufferGeometry().setFromPoints([from, to]);
        const mat = new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.5 });
        const line = new THREE.Line(geo, mat);
        this.scene.add(line);
        setTimeout(() => { if (this.scene) this.scene.remove(line); }, 150);
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
