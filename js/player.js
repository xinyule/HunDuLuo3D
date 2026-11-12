/**
 * 玩家系统 — 第一人称控制器
 */
class Player {
    constructor(camera, colliders) {
        this.camera = camera;
        this.colliders = colliders; // 碰撞体数组 [{x, z, r}] 或 [{x, z, w, d}]
        this.position = { x: 0, y: CONFIG.player.height, z: 30 };
        this.yaw = 0;
        this.pitch = 0;
        this.health = CONFIG.player.health;
        this.maxHealth = CONFIG.player.health;
        this.alive = true;
        this.lastDamageTime = 0;
        this.regenTimer = 0;

        // 武器管理
        this.currentWeapon = 0;
        this.weaponAmmo = {}; // {0: {mag: 30, reserve: 90}, ...}
        this.isReloading = false;
        this.reloadTimer = 0;

        // 初始化弹药
        for (let i = 0; i < 3; i++) {
            const w = CONFIG.weapons[i];
            this.weaponAmmo[i] = { mag: w.magSize, reserve: w.reserveAmmo };
        }

        // 分数
        this.score = 0;

        // 设置相机初始位置
        this._updateCamera();
    }

    setRotation(yaw, pitch) {
        this.yaw = yaw;
        this.pitch = pitch;
    }

    _updateCamera() {
        this.camera.position.set(this.position.x, this.position.y, this.position.z);
        // 从 yaw/pitch 计算朝向
        const lookX = this.position.x + Math.sin(this.yaw) * Math.cos(this.pitch);
        const lookY = this.position.y + Math.sin(this.pitch);
        const lookZ = this.position.z + Math.cos(this.yaw) * Math.cos(this.pitch);
        this.camera.lookAt(lookX, lookY, lookZ);
    }

    update(deltaTime, input, level) {
        if (!this.alive) return;

        // 处理视角
        this.yaw = input.yaw;
        this.pitch = input.pitch;

        // 移动
        const move = input.getMoveVector();
        const speed = input.isRunning() ? CONFIG.player.runSpeed : CONFIG.player.speed;
        const dx = (move.x * Math.cos(this.yaw) + move.z * Math.cos(this.yaw + Math.PI / 2)) * speed * deltaTime;
        const dz = (-move.x * Math.sin(this.yaw) + move.z * Math.cos(this.yaw + Math.PI / 2)) * speed * deltaTime;

        // 移动方向：前方是 yaw 方向
        // forward = (sin(yaw), 0, cos(yaw))  — 当 pitch=0 时
        // right = (cos(yaw), 0, -sin(yaw))
        const forwardX = Math.sin(this.yaw);
        const forwardZ = Math.cos(this.yaw);
        const rightX = Math.cos(this.yaw);
        const rightZ = -Math.sin(this.yaw);

        // move.x 是左右（right），move.z 是前后（forward，z=-1 是前进）
        let nx = this.position.x + (move.x * rightX + -move.z * forwardX) * speed * deltaTime;
        let nz = this.position.z + (move.x * rightZ + -move.z * forwardZ) * speed * deltaTime;

        // 碰撞检测
        const radius = CONFIG.player.radius;
        for (const c of this.colliders) {
            if (c.type === 'box') {
                const halfW = c.w / 2 + radius;
                const halfD = c.d / 2 + radius;
                if (Math.abs(nx - c.x) < halfW && Math.abs(nz - c.z) < halfD) {
                    // 推到边界
                    const overlapX = (Math.abs(nx - c.x) - halfW);
                    const overlapZ = (Math.abs(nz - c.z) - halfD);
                    if (Math.abs(nx - c.x) > Math.abs(nz - c.z)) {
                        nx += (nx > c.x ? overlapX : -overlapX);
                    } else {
                        nz += (nz > c.z ? overlapZ : -overlapZ);
                    }
                }
            } else if (c.type === 'circle') {
                const ddx = nx - c.x;
                const ddz = nz - c.z;
                const dist = Math.sqrt(ddx * ddx + ddz * ddz);
                const minDist = c.r + radius;
                if (dist < minDist && dist > 0.001) {
                    nx = c.x + (ddx / dist) * minDist;
                    nz = c.z + (ddz / dist) * minDist;
                }
            }
        }

        // 边界限制
        const bound = level.size / 2 - 2;
        nx = Utils.clamp(nx, -bound, bound);
        nz = Utils.clamp(nz, -bound, bound);

        this.position.x = nx;
        this.position.z = nz;
        this._updateCamera();

        // 换弹
        if (this.isReloading) {
            this.reloadTimer -= deltaTime;
            if (this.reloadTimer <= 0) {
                this._finishReload();
            }
        }

        // 回血
        if (this.health < this.maxHealth) {
            this.regenTimer += deltaTime;
            if (this.regenTimer > CONFIG.player.regenDelay) {
                this.health = Math.min(this.maxHealth, this.health + CONFIG.player.regenRate * deltaTime);
            }
        } else {
            this.regenTimer = 0;
        }

        // 更新 HUD
        this._updateHUD();
    }

    takeDamage(amount) {
        if (!this.alive) return;
        this.health -= amount;
        this.lastDamageTime = performance.now();
        this.regenTimer = 0;
        if (this.health <= 0) {
            this.health = 0;
            this.alive = false;
            AudioManager.gameOver();
            Game.state = 'gameover';
        } else {
            AudioManager.hurt();
        }
    }

    switchWeapon(index) {
        if (index < 0 || index > 2) return;
        if (index === this.currentWeapon) return;
        this.currentWeapon = index;
        this.isReloading = false;
        this._updateHUD();
    }

    reload() {
        const w = CONFIG.weapons[this.currentWeapon];
        const ammo = this.weaponAmmo[this.currentWeapon];
        if (this.isReloading) return;
        if (ammo.mag >= w.magSize) return;
        if (ammo.reserve <= 0) return;
        this.isReloading = true;
        this.reloadTimer = w.reloadTime;
        AudioManager.reload();
        document.getElementById('reloadIndicator').classList.remove('hidden');
    }

    _finishReload() {
        const w = CONFIG.weapons[this.currentWeapon];
        const ammo = this.weaponAmmo[this.currentWeapon];
        const needed = w.magSize - ammo.mag;
        const take = Math.min(needed, ammo.reserve);
        ammo.mag += take;
        ammo.reserve -= take;
        this.isReloading = false;
        document.getElementById('reloadIndicator').classList.add('hidden');
        this._updateHUD();
    }

    getAmmo() {
        return this.weaponAmmo[this.currentWeapon];
    }

    getCurrentWeapon() {
        return CONFIG.weapons[this.currentWeapon];
    }

    addScore(points) {
        this.score += points;
    }

    _updateHUD() {
        const healthPct = (this.health / this.maxHealth) * 100;
        document.getElementById('healthFill').style.width = healthPct + '%';
        document.getElementById('healthValue').textContent = Math.ceil(this.health);
        const w = this.getCurrentWeapon();
        const ammo = this.getAmmo();
        document.getElementById('ammoDisplay').innerHTML = `${ammo.mag} <span class="ammo-reserve">/ ${ammo.reserve}</span>`;
        document.getElementById('weaponName').textContent = w.name;
        document.getElementById('scoreValue').textContent = this.score;
    }
}
