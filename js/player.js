/**
 * 玩家系统 — 第三人称控制器（GTA风格）
 * Bill Rizer — 魂斗罗主角
 */
class Player {
    constructor(scene, camera, colliders) {
        this.scene = scene;
        this.camera = camera;
        this.colliders = colliders;
        this.position = { x: 0, y: 0, z: 30 };
        this.yaw = 0;
        this.pitch = 0;
        this.health = CONFIG.player.health;
        this.maxHealth = CONFIG.player.health;
        this.alive = true;
        this.lastDamageTime = 0;
        this.regenTimer = 0;

        // 武器管理
        this.currentWeapon = 0;
        this.weaponAmmo = {};
        this.isReloading = false;
        this.reloadTimer = 0;
        this.lastShotTime = 0;

        for (let i = 0; i < 4; i++) {
            const w = CONFIG.weapons[i];
            this.weaponAmmo[i] = { mag: w.magSize, reserve: w.reserveAmmo };
        }

        this.score = 0;

        // 创建角色模型
        this._createCharacter();

        // 枪口闪光
        this.muzzleFlash = null;
        this._createMuzzleFlash();

        this._updateCamera();
    }

    _createCharacter() {
        const group = new THREE.Group();

        // Bill Rizer — 经典魂斗罗造型：蓝色头巾、肤色身体、蓝色短裤
        // 头
        const headMat = new THREE.MeshLambertMaterial({ color: 0xd4a574 });
        const head = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.35, 0.35), headMat);
        head.position.y = 1.7;
        group.add(head);

        // 蓝色头巾
        const bandanaMat = new THREE.MeshLambertMaterial({ color: 0x2244aa });
        const bandana = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.12, 0.38), bandanaMat);
        bandana.position.y = 1.88;
        group.add(bandana);

        // 身体（白色背心）
        const bodyMat = new THREE.MeshLambertMaterial({ color: 0xeeeeee });
        const body = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.65, 0.35), bodyMat);
        body.position.y = 1.2;
        group.add(body);

        // 蓝色短裤
        const shortsMat = new THREE.MeshLambertMaterial({ color: 0x2244aa });
        const shorts = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.25, 0.35), shortsMat);
        shorts.position.y = 0.72;
        group.add(shorts);

        // 手臂
        const armMat = new THREE.MeshLambertMaterial({ color: 0xd4a574 });
        const armR = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.55, 0.12), armMat);
        armR.position.set(0.34, 1.2, 0);
        group.add(armR);
        const armL = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.55, 0.12), armMat);
        armL.position.set(-0.34, 1.2, 0);
        group.add(armL);

        // 腿
        const legMat = new THREE.MeshLambertMaterial({ color: 0x664422 });
        const legR = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.65, 0.15), legMat);
        legR.position.set(0.13, 0.32, 0);
        group.add(legR);
        const legL = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.65, 0.15), legMat);
        legL.position.set(-0.13, 0.32, 0);
        group.add(legL);

        // 枪（背在身上或拿在手上）
        const gunGroup = new THREE.Group();
        const gunMat = new THREE.MeshLambertMaterial({ color: 0x333333 });
        const gunBody = new THREE.Mesh(new THREE.BoxGeometry(0.08, 0.12, 0.6), gunMat);
        gunBody.position.z = 0.3;
        gunGroup.add(gunBody);
        const gunBarrel = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, 0.3), gunMat);
        gunBarrel.position.z = 0.65;
        gunGroup.add(gunBarrel);
        gunGroup.position.set(0.25, 1.2, 0.15);
        group.add(gunGroup);
        this.gunMesh = gunGroup;

        this.walkPhase = 0;
        this.mesh = group;
        this.mesh.position.set(this.position.x, 0, this.position.z);
        this.scene.add(this.mesh);
    }

    _createMuzzleFlash() {
        const geo = new THREE.SphereGeometry(0.2, 6, 6);
        const mat = new THREE.MeshBasicMaterial({ color: 0xffaa00, transparent: true, opacity: 0 });
        this.muzzleFlash = new THREE.Mesh(geo, mat);
        this.scene.add(this.muzzleFlash);
    }

    _updateCamera() {
        // 第三人称：相机在角色身后上方
        const dist = CONFIG.player.cameraDistance;
        const height = CONFIG.player.cameraHeight;
        const lookAhead = CONFIG.player.cameraLookAhead;

        const camX = this.position.x - Math.sin(this.yaw) * dist;
        const camZ = this.position.z - Math.cos(this.yaw) * dist;
        const camY = height + this.position.y;

        this.camera.position.set(camX, camY, camZ);

        const lookX = this.position.x + Math.sin(this.yaw) * lookAhead;
        const lookY = 1.5 + this.position.y;
        const lookZ = this.position.z + Math.cos(this.yaw) * lookAhead;
        this.camera.lookAt(lookX, lookY, lookZ);
    }

    update(deltaTime, input, level) {
        if (!this.alive) return;

        this.yaw = input.yaw;
        this.pitch = input.pitch;

        // 移动
        const move = input.getMoveVector();
        const speed = input.isRunning() ? CONFIG.player.runSpeed : CONFIG.player.speed;

        // forward = (sin(yaw), 0, cos(yaw))
        // right = (cos(yaw), 0, -sin(yaw))
        const forwardX = Math.sin(this.yaw);
        const forwardZ = Math.cos(this.yaw);
        const rightX = Math.cos(this.yaw);
        const rightZ = -Math.sin(this.yaw);

        // move.x: 左右, move.z: 前后（z=-1前进）
        let nx = this.position.x + (move.x * rightX + -move.z * forwardX) * speed * deltaTime;
        let nz = this.position.z + (move.x * rightZ + -move.z * forwardZ) * speed * deltaTime;

        // 碰撞检测
        const radius = CONFIG.player.radius;
        for (const c of this.colliders) {
            if (c.type === 'box') {
                const halfW = c.w / 2 + radius;
                const halfD = c.d / 2 + radius;
                if (Math.abs(nx - c.x) < halfW && Math.abs(nz - c.z) < halfD) {
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

        const bound = level.size / 2 - 2;
        nx = Utils.clamp(nx, -bound, bound);
        nz = Utils.clamp(nz, -bound, bound);

        this.position.x = nx;
        this.position.z = nz;

        // 更新角色模型
        this.mesh.position.set(this.position.x, 0, this.position.z);
        this.mesh.rotation.y = this.yaw;

        // 走路动画
        if (move.magnitude > 0.1) {
            this.walkPhase += deltaTime * 10;
            this.mesh.children.forEach(child => {
                if (child === this.gunMesh) return;
            });
            // 简单上下晃动
            this.mesh.position.y = Math.abs(Math.sin(this.walkPhase)) * 0.08;
        } else {
            this.mesh.position.y = 0;
        }

        this._updateCamera();

        // 枪口闪光衰减
        if (this.muzzleFlash.material.opacity > 0) {
            this.muzzleFlash.material.opacity -= deltaTime * 10;
            if (this.muzzleFlash.material.opacity <= 0) this.muzzleFlash.material.opacity = 0;
        }

        // 换弹
        if (this.isReloading) {
            this.reloadTimer -= deltaTime;
            if (this.reloadTimer <= 0) this._finishReload();
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
        if (index < 0 || index > 3) return;
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

    getAmmo() { return this.weaponAmmo[this.currentWeapon]; }
    getCurrentWeapon() { return CONFIG.weapons[this.currentWeapon]; }
    addScore(points) { this.score += points; }

    // 射击：从相机中心射线检测
    shoot(enemies) {
        const now = performance.now();
        const w = this.getCurrentWeapon();
        const ammo = this.getAmmo();

        if (this.isReloading) return false;
        if (now - this.lastShotTime < w.fireRate * 1000) return false;
        if (ammo.mag <= 0) { this.reload(); return false; }

        this.lastShotTime = now;
        ammo.mag--;
        this._updateHUD();

        AudioManager.shoot(w.flame ? 100 : 200, w.flame ? 'sawtooth' : 'square');

        // 枪口闪光位置
        const muzzleOffset = new THREE.Vector3(0.25, 1.2, 0.6);
        muzzleOffset.applyAxisAngle(new THREE.Vector3(0, 1, 0), this.yaw);
        this.muzzleFlash.position.set(
            this.position.x + muzzleOffset.x,
            muzzleOffset.y,
            this.position.z + muzzleOffset.z
        );
        this.muzzleFlash.material.opacity = 1;

        // 射线：从相机中心向前
        const origin = this.camera.position.clone();
        const direction = new THREE.Vector3(0, 0, -1);
        direction.applyQuaternion(this.camera.quaternion);

        const pellets = w.pellets || 1;
        for (let p = 0; p < pellets; p++) {
            const spread = w.spread;
            const spreadX = (Math.random() - 0.5) * spread;
            const spreadY = (Math.random() - 0.5) * spread;
            const dir = direction.clone();
            const right = new THREE.Vector3(1, 0, 0);
            right.applyQuaternion(this.camera.quaternion);
            const up = new THREE.Vector3(0, 1, 0);
            up.applyQuaternion(this.camera.quaternion);
            dir.add(right.multiplyScalar(spreadX));
            dir.add(up.multiplyScalar(spreadY));
            dir.normalize();

            // 火焰喷射：短距离锥形
            if (w.flame) {
                this._applyFlame(origin, dir, enemies, w);
                continue;
            }

            // 射线检测敌人
            let closestEnemy = null;
            let closestEnemyDist = w.range;

            for (const enemy of enemies) {
                if (!enemy.alive) continue;
                const hit = this._raycastEnemy(origin, dir, enemy);
                if (hit && hit.dist < closestEnemyDist) {
                    closestEnemy = enemy;
                    closestEnemyDist = hit.dist;
                }
            }

            // 射线检测场景碰撞体
            let sceneDist = w.range;
            for (const c of this.colliders) {
                const hit = this._raycastCollider(origin, dir, c);
                if (hit && hit < sceneDist) sceneDist = hit;
            }

            // 地面
            const groundDist = origin.y > 0 ? origin.y / Math.abs(dir.y + 0.001) : w.range;
            if (Math.abs(dir.y) > 0.001 && groundDist < sceneDist) {
                sceneDist = Math.min(sceneDist, groundDist);
            }

            let endPoint;
            if (closestEnemy && closestEnemyDist <= sceneDist) {
                closestEnemy.takeDamage(w.damage);
                endPoint = origin.clone().add(dir.clone().multiplyScalar(closestEnemyDist));
                closestEnemy._showHitEffect(endPoint);
            } else {
                endPoint = origin.clone().add(dir.clone().multiplyScalar(sceneDist));
            }

            this._createTracer(origin, endPoint, w.color);
        }

        return true;
    }

    _applyFlame(origin, dir, enemies, w) {
        // 火焰：短距离，锥形范围伤害
        const flameLength = w.range;
        const flameRadius = 1.5;
        const endPoint = origin.clone().add(dir.clone().multiplyScalar(flameLength));

        for (const enemy of enemies) {
            if (!enemy.alive) continue;
            const enemyPos = new THREE.Vector3(enemy.position.x, enemy.position.y + 1, enemy.position.z);
            const toEnemy = enemyPos.clone().sub(origin);
            const projLen = toEnemy.dot(dir);
            if (projLen < 0 || projLen > flameLength) continue;
            const perpDist = toEnemy.length() - projLen;
            if (perpDist > flameRadius + enemy.radius) continue;
            // 随机伤害（火焰是多段）
            enemy.takeDamage(w.damage * Utils.randomRange(0.5, 1.5));
        }

        this._createTracer(origin, endPoint, 0xff4400);
    }

    _raycastEnemy(origin, dir, enemy) {
        const enemyPos = new THREE.Vector3(enemy.position.x, enemy.position.y + 1, enemy.position.z);
        const radius = enemy.radius;
        const oc = origin.clone().sub(enemyPos);
        const a = dir.dot(dir);
        const b = 2 * oc.dot(dir);
        const c = oc.dot(oc) - radius * radius;
        const disc = b * b - 4 * a * c;
        if (disc < 0) return null;
        const t = (-b - Math.sqrt(disc)) / (2 * a);
        if (t < 0) return null;
        return { dist: t };
    }

    _raycastCollider(origin, dir, c) {
        if (c.type === 'box') {
            const minX = c.x - c.w / 2, maxX = c.x + c.w / 2;
            const minZ = c.z - c.d / 2, maxZ = c.z + c.d / 2;
            const height = c.h || CONFIG.level.wallHeight;
            const minY = 0, maxY = height;

            let tmin = -Infinity, tmax = Infinity;
            for (let i = 0; i < 3; i++) {
                const o = i === 0 ? origin.x : (i === 1 ? origin.y : origin.z);
                const d = i === 0 ? dir.x : (i === 1 ? dir.y : dir.z);
                const lo = i === 0 ? minX : (i === 1 ? minY : minZ);
                const hi = i === 0 ? maxX : (i === 1 ? maxY : maxZ);
                if (Math.abs(d) < 0.0001) {
                    if (o < lo || o > hi) return Infinity;
                } else {
                    let t1 = (lo - o) / d;
                    let t2 = (hi - o) / d;
                    if (t1 > t2) [t1, t2] = [t2, t1];
                    tmin = Math.max(tmin, t1);
                    tmax = Math.min(tmax, t2);
                    if (tmin > tmax) return Infinity;
                }
            }
            return tmin > 0 ? tmin : Infinity;
        } else if (c.type === 'circle') {
            const ox = origin.x, oz = origin.z;
            const dx = dir.x, dz = dir.z;
            const fx = ox - c.x, fz = oz - c.z;
            const a = dx * dx + dz * dz;
            const b = 2 * (fx * dx + fz * dz);
            const cc = fx * fx + fz * fz - c.r * c.r;
            const disc = b * b - 4 * a * cc;
            if (disc < 0) return Infinity;
            const t = (-b - Math.sqrt(disc)) / (2 * a);
            if (t < 0) return Infinity;
            const hitY = origin.y + dir.y * t;
            if (hitY < 0 || hitY > (c.h || CONFIG.level.wallHeight)) return Infinity;
            return t;
        }
        return Infinity;
    }

    _createTracer(from, to, color) {
        const geo = new THREE.BufferGeometry().setFromPoints([from, to]);
        const mat = new THREE.LineBasicMaterial({ color: color || 0xffff00, transparent: true, opacity: 0.6 });
        const line = new THREE.Line(geo, mat);
        this.scene.add(line);
        // 自动清理
        setTimeout(() => { if (this.scene) this.scene.remove(line); }, 200);
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

    destroy() {
        if (this.mesh) this.scene.remove(this.mesh);
        if (this.muzzleFlash) this.scene.remove(this.muzzleFlash);
    }
}
