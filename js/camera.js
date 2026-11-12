/**
 * 世界碰撞查询（相机与弹丸共用）
 * collider: {type:'box'|'circle', x, z, w, d, r, h, y0?, disabled?}
 */
const WorldHit = {
    // 射线 vs 碰撞体，返回最近距离（无命中 Infinity）
    rayVsColliders(origin, dir, maxDist, colliders) {
        let best = maxDist;
        for (const c of colliders) {
            if (c.disabled) continue;
            const y0 = c.y0 || 0, y1 = y0 + (c.h || 6);
            if (c.type === 'box') {
                const minX = c.x - c.w / 2, maxX = c.x + c.w / 2;
                const minZ = c.z - c.d / 2, maxZ = c.z + c.d / 2;
                let tmin = 0, tmax = best;
                let ok = true;
                const o = [origin.x, origin.y, origin.z], d = [dir.x, dir.y, dir.z];
                const lo = [minX, y0, minZ], hi = [maxX, y1, maxZ];
                for (let i = 0; i < 3; i++) {
                    if (Math.abs(d[i]) < 1e-6) { if (o[i] < lo[i] || o[i] > hi[i]) { ok = false; break; } }
                    else {
                        let t1 = (lo[i] - o[i]) / d[i], t2 = (hi[i] - o[i]) / d[i];
                        if (t1 > t2) { const t = t1; t1 = t2; t2 = t; }
                        tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2);
                        if (tmin > tmax) { ok = false; break; }
                    }
                }
                if (ok && tmin < best && tmin > 0.01) best = tmin;
            } else if (c.type === 'circle') {
                const fx = origin.x - c.x, fz = origin.z - c.z;
                const a = dir.x * dir.x + dir.z * dir.z;
                if (a < 1e-8) continue;
                const b = 2 * (fx * dir.x + fz * dir.z);
                const cc = fx * fx + fz * fz - c.r * c.r;
                const disc = b * b - 4 * a * cc;
                if (disc < 0) continue;
                const t = (-b - Math.sqrt(disc)) / (2 * a);
                if (t < 0.01 || t >= best) continue;
                const hitY = origin.y + dir.y * t;
                if (hitY >= y0 && hitY <= y1) best = t;
            }
        }
        return best;
    },
    // 点是否落在碰撞体内（弹丸步进判定用，pad 为弹丸半径）
    pointHitsCollider(x, y, z, c, pad) {
        if (c.disabled) return false;
        const y0 = (c.y0 || 0) - pad, y1 = y0 + (c.h || 6) + pad * 2;
        if (y < y0 || y > y1) return false;
        if (c.type === 'box') {
            return Math.abs(x - c.x) <= c.w / 2 + pad && Math.abs(z - c.z) <= c.d / 2 + pad;
        }
        if (c.type === 'circle') {
            const dx = x - c.x, dz = z - c.z, rr = c.r + pad;
            return dx * dx + dz * dz <= rr * rr;
        }
        return false;
    },
};

/**
 * GTA 式第三人称镜头：人后越肩、轨道俯仰、开镜收紧、撞墙回收、阻尼平滑。
 * 朝向约定：forward = (sinYaw*cosPitch, sinPitch, cosYaw*cosPitch)，yaw=π 时朝 -Z。
 */
class ThirdPersonCamera {
    constructor(camera) {
        this.camera = camera;
        this.pos = new THREE.Vector3(0, 3, 38);
        this.aimPoint = new THREE.Vector3(0, 1.5, -40);
        this.aimDir = new THREE.Vector3(0, 0, -1);
        this._snap = true;
        this._fov = CONFIG.renderer.fov;
    }

    snapTo(anchor, yaw, pitch) {
        this._snap = true;
        this._compute(anchor, yaw, pitch, false, null, 0, true);
    }

    _compute(anchor, yaw, pitch, aiming, colliders, dt, forceSnap) {
        const C = CONFIG.camera;
        const targetH = aiming !== null && anchor.prone ? C.targetHeightProne : C.targetHeight;
        const pivot = new THREE.Vector3(anchor.x, anchor.y + targetH, anchor.z);
        const cp = Math.cos(pitch), sp = Math.sin(pitch);
        const fwd = new THREE.Vector3(Math.sin(yaw) * cp, sp, Math.cos(yaw) * cp);
        const right = new THREE.Vector3(-fwd.z, 0, fwd.x).normalize();
        const dist = aiming ? C.aimDistance : C.distance;

        const desired = pivot.clone()
            .addScaledVector(fwd, -dist)
            .addScaledVector(right, C.shoulder);
        desired.y += C.height * (aiming ? 0.5 : 1);

        // 镜头碰撞：从注视点向期望位置打射线，撞墙拉近
        if (colliders && !forceSnap) {
            const toCam = desired.clone().sub(pivot);
            const len = toCam.length();
            if (len > 0.01) {
                const dir = toCam.clone().divideScalar(len);
                const hit = WorldHit.rayVsColliders(pivot, dir, len, colliders);
                if (hit < len) {
                    const d = Math.max(0.7, hit - C.collisionPad);
                    desired.copy(pivot).addScaledVector(dir, d);
                }
            }
        }
        if (desired.y < anchor.y + 0.3) desired.y = anchor.y + 0.3;

        if (forceSnap || this._snap) {
            this.pos.copy(desired);
            this._snap = false;
        } else {
            const k = 1 - Math.exp(-C.smooth * dt);
            this.pos.lerp(desired, k);
        }
        this.camera.position.copy(this.pos);
        // 准星射线须收敛到角色胸口前方（越肩镜头的标准做法），
        // 否则射线停在镜头高度，站立敌人会整体从弹道下方漏过
        const lookTarget = pivot.clone().addScaledVector(fwd, 12);
        this.camera.lookAt(lookTarget);

        // 准星落点：相机中心射线 vs 碰撞体/地面
        this.camera.getWorldDirection(this.aimDir);
        let best = 160;
        if (colliders) best = WorldHit.rayVsColliders(this.camera.position, this.aimDir, best, colliders);
        if (this.aimDir.y < -0.001) {
            const tg = this.camera.position.y / -this.aimDir.y;
            if (tg > 0 && tg < best) best = tg;
        }
        this.aimPoint.copy(this.camera.position).addScaledVector(this.aimDir, best);
    }

    update(dt, opts) {
        this._compute(opts.anchor, opts.yaw, opts.pitch, opts.aiming, opts.colliders, dt, false);
        // FOV 开镜收紧
        const targetFov = opts.aiming ? CONFIG.renderer.aimFov : CONFIG.renderer.fov;
        if (Math.abs(targetFov - this._fov) > 0.05) {
            this._fov = Utils.lerp(this._fov, targetFov, 1 - Math.exp(-10 * dt));
            this.camera.fov = this._fov;
            this.camera.updateProjectionMatrix();
        }
        // 准星落点再与可击目标求近（敌人/Boss/感应器/飞鹰）
        if (opts.targets) {
            let best = this.camera.position.distanceTo(this.aimPoint);
            for (const t of opts.targets) {
                if (!t.alive) continue;
                const dx = t.hitX - this.camera.position.x;
                const dy = t.hitY - this.camera.position.y;
                const dz = t.hitZ - this.camera.position.z;
                const along = dx * this.aimDir.x + dy * this.aimDir.y + dz * this.aimDir.z;
                if (along < 0 || along > best) continue;
                const px = this.camera.position.x + this.aimDir.x * along;
                const py = this.camera.position.y + this.aimDir.y * along;
                const pz = this.camera.position.z + this.aimDir.z * along;
                const off = Math.sqrt((t.hitX - px) ** 2 + (t.hitY - py) ** 2 + (t.hitZ - pz) ** 2);
                if (off <= t.hitR + 0.25) best = along;
            }
            this.aimPoint.copy(this.camera.position).addScaledVector(this.aimDir, best);
        }
    }
}
