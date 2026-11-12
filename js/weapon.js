/**
 * 武器系统 — 射击、射线检测、弹药、换弹
 */
class WeaponSystem {
    constructor(scene, player) {
        this.scene = scene;
        this.player = player;
        this.raycaster = new THREE.Raycaster();

        // 枪口闪光
        this.muzzleFlash = null;
        this._createMuzzleFlash();

        // 子弹轨迹线
        this.tracers = [];
        this.maxTracers = 10;

        // 射击间隔
        this.lastShotTime = 0;
    }

    _createMuzzleFlash() {
        const geo = new THREE.SphereGeometry(0.15, 6, 6);
        const mat = new THREE.MeshBasicMaterial({ color: 0xffaa00, transparent: true, opacity: 0 });
        this.muzzleFlash = new THREE.Mesh(geo, mat);
        this.muzzleFlash.position.set(0, 0, -0.5);
        this.scene.add(this.muzzleFlash);
    }

    update(deltaTime) {
        // 枪口闪光衰减
        if (this.muzzleFlash.material.opacity > 0) {
            this.muzzleFlash.material.opacity -= deltaTime * 10;
            if (this.muzzleFlash.material.opacity <= 0) {
                this.muzzleFlash.material.opacity = 0;
            }
        }

        // 更新子弹轨迹
        for (let i = this.tracers.length - 1; i >= 0; i--) {
            const t = this.tracers[i];
            t.line.material.opacity -= deltaTime * 4;
            if (t.line.material.opacity <= 0) {
                this.scene.remove(t.line);
                this.tracers.splice(i, 1);
            }
        }
    }

    _showMuzzleFlash() {
        // 将枪口闪光放在相机右下方
        const offset = new THREE.Vector3(0.3, -0.2, -0.5);
        offset.applyQuaternion(this.player.camera.quaternion);
        this.muzzleFlash.position.copy(this.player.camera.position).add(offset);
        this.muzzleFlash.material.opacity = 1;
    }

    _createTracer(from, to) {
        const geo = new THREE.BufferGeometry().setFromPoints([from, to]);
        const mat = new THREE.LineBasicMaterial({ color: 0xffff00, transparent: true, opacity: 0.6 });
        const line = new THREE.Line(geo, mat);
        this.scene.add(line);
        this.tracers.push({ line });
        if (this.tracers.length > this.maxTracers) {
            const old = this.tracers.shift();
            this.scene.remove(old.line);
        }
    }

    shoot(enemies) {
        const now = performance.now();
        const w = this.player.getCurrentWeapon();
        const ammo = this.player.getAmmo();

        if (this.player.isReloading) return false;
        if (now - this.lastShotTime < w.fireRate * 1000) return false;
        if (ammo.mag <= 0) {
            this.player.reload();
            return false;
        }

        this.lastShotTime = now;
        ammo.mag--;
        this.player._updateHUD();

        AudioManager.shoot(w === CONFIG.weapons[1] ? 120 : 250, 'square');
        this._showMuzzleFlash();

        // 射线检测
        const origin = this.player.camera.position.clone();
        const direction = new THREE.Vector3(0, 0, -1);
        direction.applyQuaternion(this.player.camera.quaternion);

        const pellets = w.pellets || 1;
        for (let p = 0; p < pellets; p++) {
            // 散布
            const spread = w.spread;
            const spreadX = (Math.random() - 0.5) * spread;
            const spreadY = (Math.random() - 0.5) * spread;
            const dir = direction.clone();
            // 在相机空间中散布
            const right = new THREE.Vector3(1, 0, 0);
            right.applyQuaternion(this.player.camera.quaternion);
            const up = new THREE.Vector3(0, 1, 0);
            up.applyQuaternion(this.player.camera.quaternion);
            dir.add(right.multiplyScalar(spreadX));
            dir.add(up.multiplyScalar(spreadY));
            dir.normalize();

            this.raycaster.set(origin, dir);
            this.raycaster.far = w.range;

            // 检测敌人
            let closestHit = null;
            let closestDist = w.range;

            for (const enemy of enemies) {
                if (!enemy.alive) continue;
                const hit = this._raycastEnemy(origin, dir, enemy);
                if (hit && hit.dist < closestDist) {
                    closestHit = enemy;
                    closestDist = hit.dist;
                }
            }

            // 检测场景碰撞体（墙壁、箱子等）
            let sceneDist = w.range;
            for (const c of this.player.colliders) {
                const hit = this._raycastCollider(origin, dir, c);
                if (hit && hit < sceneDist) {
                    sceneDist = hit;
                }
            }

            // 地形（地面）
            const groundDist = origin.y > 0 ? origin.y / Math.abs(dir.y) : w.range;
            if (Math.abs(dir.y) > 0.001 && groundDist < sceneDist) {
                sceneDist = Math.min(sceneDist, groundDist);
            }

            let endPoint;
            if (closestHit && closestDist <= sceneDist) {
                // 击中敌人
                closestHit.takeDamage(w.damage);
                endPoint = origin.clone().add(dir.clone().multiplyScalar(closestDist));
                // 血溅效果
                closestHit._showHitEffect(endPoint);
            } else {
                endPoint = origin.clone().add(dir.clone().multiplyScalar(sceneDist));
            }

            this._createTracer(origin, endPoint);
        }

        return true;
    }

    _raycastEnemy(origin, dir, enemy) {
        // 简化的敌人碰撞体：圆柱体近似为球体
        const enemyPos = new THREE.Vector3(enemy.position.x, enemy.position.y, enemy.position.z);
        const radius = CONFIG.enemy.radius;
        // 球体射线相交
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
        // 盒子碰撞体的射线相交（AABB）
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
            // 圆柱体：先做水平面射线相交
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

    syncMuzzleToCamera() {
        if (this.muzzleFlash.material.opacity > 0) {
            const offset = new THREE.Vector3(0.25, -0.15, -0.6);
            offset.applyQuaternion(this.player.camera.quaternion);
            this.muzzleFlash.position.copy(this.player.camera.position).add(offset);
        }
    }
}
