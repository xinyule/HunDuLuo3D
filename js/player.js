/**
 * 玩家 — Bill Rizer
 * 动作：移动/疾跑/跳跃（翻跟头）/趴下；武器靠道具换枪、无限弹药；
 * 伤害走格血（折中档）；玩家只发事件回调，绝不直接改 Game.state（旧版致命 bug 的结构性修复）。
 */
class Player {
    constructor(scene) {
        this.scene = scene;
        this.position = { x: 0, y: 0, z: 26 };
        this.radius = CONFIG.player.radius;
        this.facing = Math.PI; // 朝 -Z
        this.vy = 0;
        this.grounded = true;
        this.prone = false;
        this.alive = true;

        this.hpCells = CONFIG.player.maxCells;
        this.weapon = 'N';
        this.rapid = false;
        this.barrier = 0;
        this.invuln = 0;
        this._blink = false;

        this.fireTimer = 0;
        this.walkPhase = 0;
        this._flip = 0;
        this._flashT = 0;

        // 事件回调（Game 赋值）
        this.onDeath = null;
        this.onDamaged = null;

        this._buildMesh();
    }

    _buildMesh() {
        const g = new THREE.Group();
        const body = new THREE.Group();
        g.add(body);
        this.bodyGroup = body;

        const skin = new THREE.MeshLambertMaterial({ color: 0xd4a574 });
        const blue = new THREE.MeshLambertMaterial({ color: 0x2244aa });
        const white = new THREE.MeshLambertMaterial({ color: 0xeeeeee });
        const dark = new THREE.MeshLambertMaterial({ color: 0x664422 });
        const gunMat = new THREE.MeshLambertMaterial({ color: 0x2a2a2a });

        const head = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.34, 0.34), skin);
        head.position.y = 1.62; body.add(head);
        const bandana = new THREE.Mesh(new THREE.BoxGeometry(0.37, 0.12, 0.37), blue);
        bandana.position.y = 1.8; body.add(bandana);
        const bandTail = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.3, 0.04), blue);
        bandTail.position.set(0.1, 1.62, -0.2); body.add(bandTail);

        const torso = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.62, 0.34), white);
        torso.position.y = 1.14; body.add(torso);
        const shorts = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.24, 0.35), blue);
        shorts.position.y = 0.7; body.add(shorts);

        const armL = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.55, 0.13), skin);
        armL.position.set(-0.35, 1.16, 0.05); body.add(armL);
        this.armL = armL;

        // 右臂+枪（瞄准时前指）
        const armRGroup = new THREE.Group();
        armRGroup.position.set(0.35, 1.38, 0);
        const armR = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.5, 0.13), skin);
        armR.position.y = -0.2; armRGroup.add(armR);
        const gun = new THREE.Group();
        const gunBody = new THREE.Mesh(new THREE.BoxGeometry(0.09, 0.13, 0.62), gunMat);
        gunBody.position.z = 0.28; gun.add(gunBody);
        const barrel = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, 0.3), gunMat);
        barrel.position.z = 0.66; gun.add(barrel);
        gun.position.set(0, -0.42, 0.1);
        gun.rotation.x = -0.25;
        armRGroup.add(gun);
        body.add(armRGroup);
        this.armRGroup = armRGroup;
        this.gun = gun;

        const legGeo = new THREE.BoxGeometry(0.16, 0.62, 0.16);
        const legL = new THREE.Mesh(legGeo, dark); legL.position.set(-0.14, 0.32, 0); body.add(legL);
        const legR = new THREE.Mesh(legGeo, dark); legR.position.set(0.14, 0.32, 0); body.add(legR);
        this.legL = legL; this.legR = legR;
        // 腿的摆动绕髋：用几何偏移近似（position 微调在动画里处理）

        // B 道具防护罩
        const shield = new THREE.Mesh(
            new THREE.SphereGeometry(1.25, 12, 10),
            new THREE.MeshBasicMaterial({ color: 0x66ccff, transparent: true, opacity: 0.22, depthWrite: false })
        );
        shield.position.y = 1.0;
        shield.visible = false;
        g.add(shield);
        this.shieldMesh = shield;

        // 枪口闪光
        const flash = new THREE.Mesh(
            new THREE.SphereGeometry(0.16, 6, 6),
            new THREE.MeshBasicMaterial({ color: 0xffcc55, transparent: true, opacity: 0 })
        );
        this.scene.add(flash);
        this.flashMesh = flash;

        this.mesh = g;
        this.mesh.position.set(this.position.x, 0, this.position.z);
        this.scene.add(g);
    }

    get chestY() { return this.position.y + (this.prone ? 0.4 : 1.15); }

    reset(point, keepWeapon) {
        this.position.x = point.x; this.position.y = point.y || 0; this.position.z = point.z;
        this.vy = 0; this.grounded = true; this.prone = false;
        this.hpCells = CONFIG.player.maxCells;
        this.alive = true;
        this.barrier = 0; this.invuln = 0; this._blink = false;
        if (!keepWeapon) { this.weapon = 'N'; this.rapid = false; }
        this.facing = Math.PI;
        this.mesh.visible = true;
        this._syncMesh(0);
    }

    respawn(point) {
        this.reset(point, false);
        this.invuln = CONFIG.player.respawnInvuln;
        this._blink = true;
    }

    takeDamage(cells) {
        if (!this.alive || this.invuln > 0 || this.barrier > 0) return false;
        this.hpCells -= cells;
        this.invuln = CONFIG.player.hitInvuln;
        AudioManager.hurt();
        if (this.onDamaged) this.onDamaged(this.hpCells);
        if (this.hpCells <= 0) {
            this.hpCells = 0;
            this.alive = false;
            if (this.onDeath) this.onDeath();
        }
        return true;
    }

    heal(n) {
        this.hpCells = Math.min(CONFIG.player.maxCells, this.hpCells + n);
    }

    applyPickup(letter) {
        AudioManager.pickup();
        if (letter === 'R') this.rapid = true;
        else if (letter === 'B') this.barrier = 8;
        else if (letter === '+') this.heal(1);
        else if (WEAPON_DATA[letter]) this.weapon = letter;
    }

    update(dt, input, level, aimYaw, aimingOrShooting) {
        if (!this.alive) return;
        if (this.invuln > 0) this.invuln -= dt;
        if (this.barrier > 0) { this.barrier -= dt; if (this.barrier < 0) this.barrier = 0; }
        this.shieldMesh.visible = this.barrier > 0;
        if (this.fireTimer > 0) this.fireTimer -= dt;
        if (this._flashT > 0) { this._flashT -= dt; this.flashMesh.material.opacity = Math.max(0, this._flashT / 0.05); }

        // 复活无敌闪烁
        if (this._blink) {
            if (this.invuln <= 0) { this._blink = false; this.mesh.visible = true; }
            else this.mesh.visible = Math.floor(performance.now() / 90) % 2 === 0;
        }

        this.prone = !!input.isProne() && this.grounded;

        // 移动（相对镜头朝向）
        const move = input.getMoveVector();
        const moving = move.magnitude > 0.1;
        let speed = CONFIG.player.walkSpeed;
        if (this.prone) speed = CONFIG.player.proneSpeed;
        else if (input.isRunning() && !aimingOrShooting) speed = CONFIG.player.runSpeed;

        const sin = Math.sin(aimYaw), cos = Math.cos(aimYaw);
        // forward=(sin,cos)，right=(-cos,sin)（与镜头约定一致）
        const wx = (move.x * -cos + -move.z * sin);
        const wz = (move.x * sin + -move.z * cos);
        let nx = this.position.x + wx * speed * dt;
        let nz = this.position.z + wz * speed * dt;

        // 走廊边界
        const halfW = level.width / 2 - 1.1;
        nx = Utils.clamp(nx, -halfW, halfW);
        nz = Utils.clamp(nz, -level.length - 14, 30);

        // 水平碰撞
        const resolved = this._resolveHorizontal(nx, nz, level);
        nx = resolved.x; nz = resolved.z;
        this.position.x = nx; this.position.z = nz;

        // 地面/跳跃
        const support = level.getSupportY(nx, nz, this.position.y);
        if (this.grounded) {
            if (input.consumeJump()) {
                this.vy = CONFIG.player.jumpVelocity;
                this.grounded = false;
                this._flip = 0.01;
                AudioManager.jump();
            } else if (support < this.position.y - 1.5) {
                this.grounded = false; // 走下高台边缘
                this.vy = 0;
            } else {
                this.position.y = support;
            }
        }
        if (!this.grounded) {
            this.vy -= CONFIG.player.gravity * dt;
            this.position.y += this.vy * dt;
            if (this._flip > 0) this._flip += dt * 5.2; // 翻跟头进度
            const s2 = level.getSupportY(nx, nz, this.position.y);
            if (this.position.y <= s2) {
                this.position.y = s2;
                this.vy = 0;
                this.grounded = true;
                this._flip = 0;
            }
        }

        // 朝向：瞄准/开火锁镜头方向，否则朝移动方向
        if (aimingOrShooting) {
            this.facing = aimYaw;
        } else if (moving) {
            const target = Math.atan2(wx, wz);
            let diff = target - this.facing;
            while (diff > Math.PI) diff -= Math.PI * 2;
            while (diff < -Math.PI) diff += Math.PI * 2;
            this.facing += diff * Math.min(1, dt * 14);
        }

        // 动画相位
        if (moving && this.grounded) this.walkPhase += dt * (speed * 1.35);
        this._syncMesh(dt, moving);
    }

    _resolveHorizontal(nx, nz, level) {
        const radius = this.radius;
        const feetY = this.position.y;
        const bodyTop = feetY + (this.prone ? CONFIG.player.proneHeight : CONFIG.player.height);
        for (const c of level.colliders) {
            if (c.disabled || c.noCollide) continue;
            const cBot = c.y0 || 0, cTop = cBot + (c.h || 6);
            if (cTop <= feetY + 0.55) continue;          // 可踩/可跨
            if (cBot >= bodyTop - 0.15) continue;        // 在头顶上方
            if (c.type === 'box') {
                const hw = c.w / 2 + radius, hd = c.d / 2 + radius;
                const dx = nx - c.x, dz = nz - c.z;
                if (Math.abs(dx) < hw && Math.abs(dz) < hd) {
                    const penX = hw - Math.abs(dx), penZ = hd - Math.abs(dz);
                    if (penX < penZ) nx = c.x + (dx >= 0 ? hw : -hw);
                    else nz = c.z + (dz >= 0 ? hd : -hd);
                }
            } else if (c.type === 'circle') {
                const dx = nx - c.x, dz = nz - c.z;
                const d2 = dx * dx + dz * dz, minD = c.r + radius;
                if (d2 < minD * minD && d2 > 1e-6) {
                    const d = Math.sqrt(d2);
                    nx = c.x + (dx / d) * minD;
                    nz = c.z + (dz / d) * minD;
                }
            }
        }
        return { x: nx, z: nz };
    }

    _syncMesh(dt, moving) {
        this.mesh.position.set(this.position.x, this.position.y, this.position.z);
        this.mesh.rotation.y = this.facing;
        const body = this.bodyGroup;
        if (!this.grounded && this._flip > 0) {
            body.rotation.x = -Math.min(this._flip, 1) * Math.PI * 2;
            body.position.y = 0;
        } else if (this.prone) {
            body.rotation.x = 1.25;
            body.position.y = -0.55;
        } else {
            body.rotation.x = 0;
            body.position.y = (moving && this.grounded) ? Math.abs(Math.sin(this.walkPhase)) * 0.07 : 0;
        }
        // 腿摆动（绕髋近似：前后摆用 rotation.x 作用在单腿网格上会绕其中心，可接受的低模动画）
        const swing = (moving && this.grounded && !this.prone) ? Math.sin(this.walkPhase) * 0.55 : 0;
        this.legL.rotation.x = swing;
        this.legR.rotation.x = -swing;
        // 右臂瞄准姿势
        this.armRGroup.rotation.x = this.prone ? -1.2 : -1.45;
    }

    getMuzzleWorld(out) {
        const y = this.position.y + (this.prone ? 0.35 : 1.3);
        const fx = Math.sin(this.facing), fz = Math.cos(this.facing);
        out.set(this.position.x + fx * 0.55, y, this.position.z + fz * 0.55);
        return out;
    }

    tryShoot(projectiles, aimPoint) {
        if (!this.alive || this.fireTimer > 0) return false;
        const w = WEAPON_DATA[this.weapon];
        this.fireTimer = w.fireRate * (this.rapid ? RAPID_FACTOR : 1);
        const muzzle = this.getMuzzleWorld(new THREE.Vector3());
        const baseDir = aimPoint.clone().sub(muzzle);
        if (baseDir.lengthSq() < 0.01) baseDir.set(Math.sin(this.facing), 0, Math.cos(this.facing));
        baseDir.normalize();
        const right = new THREE.Vector3(-baseDir.z, 0, baseDir.x).normalize();
        const up = new THREE.Vector3().crossVectors(baseDir, right).normalize();
        for (let i = 0; i < w.pellets; i++) {
            const dir = baseDir.clone();
            if (w.pellets > 1) {
                // S 散射：扇形均布 + 少量随机
                const t = (i / (w.pellets - 1) - 0.5);
                dir.addScaledVector(right, t * w.spread * 2.2);
                dir.addScaledVector(up, (Math.random() - 0.5) * w.spread * 0.4);
            } else if (w.spread > 0) {
                dir.addScaledVector(right, (Math.random() - 0.5) * w.spread * 2);
                dir.addScaledVector(up, (Math.random() - 0.5) * w.spread * 2);
            }
            dir.normalize();
            projectiles.spawnPlayerBullet(muzzle, dir, w);
        }
        this.flashMesh.position.copy(muzzle).addScaledVector(baseDir, 0.25);
        this.flashMesh.material.opacity = 0.9;
        this._flashT = 0.05;
        AudioManager.shoot(this.weapon);
        return true;
    }

    destroy() {
        if (this.mesh) { this.scene.remove(this.mesh); Utils.disposeObject(this.mesh); }
        if (this.flashMesh) { this.scene.remove(this.flashMesh); Utils.disposeObject(this.flashMesh); }
    }
}
