/**
 * 实体弹丸系统 — 双方子弹都看得见、躲得开（修旧版敌人掷骰子命中的核心问题）
 * 玩家弹：高速曳光；敌弹：慢速红弹丸（可跳/趴躲）；另有榴弹（抛物线+爆炸）与 Boss 圆盘。
 * 可击目标统一接口：{ alive, hitX, hitY, hitZ, hitR, onHit(damage, point) }
 */
class ProjectileSystem {
    constructor(scene) {
        this.scene = scene;
        this.list = [];
        this.effects = [];
        this._geoSphere = new THREE.SphereGeometry(1, 8, 6);
        this._geoDisc = new THREE.CylinderGeometry(0.5, 0.5, 0.12, 10);
        this._mats = {};
    }

    _mat(color) {
        if (!this._mats[color]) {
            this._mats[color] = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.95 });
        }
        return this._mats[color];
    }

    _spawn(o) {
        const geo = o.kind === 'disc' ? this._geoDisc : this._geoSphere;
        const mesh = new THREE.Mesh(geo, this._mat(o.color));
        const r = o.radius;
        mesh.scale.set(r, o.kind === 'disc' ? 1 : r, r);
        if (o.kind === 'laser') mesh.scale.set(r * 0.7, r * 0.7, r * 6);
        mesh.position.copy(o.from);
        this.scene.add(mesh);
        const p = Object.assign({
            mesh, alive: true, travelled: 0, hitSet: new Set(), wavePhase: Math.random() * 6.28, t: 0,
        }, o);
        if (p.kind === 'laser') {
            mesh.lookAt(o.from.clone().add(o.dir));
        }
        this.list.push(p);
        return p;
    }

    // 玩家开火（Game/Player 调用，pellets 在 Player 内逐发调用）
    spawnPlayerBullet(from, dir, w) {
        const kind = w.wave ? 'fire' : (w.pierce && w.bulletSpeed > 150 ? 'laser' : 'bullet');
        return this._spawn({
            friendly: true, kind,
            from: from.clone(), dir: dir.clone(),
            speed: w.bulletSpeed, damage: w.damage, color: w.color,
            radius: kind === 'fire' ? 0.22 : 0.1, pierce: !!w.pierce, wave: !!w.wave, maxRange: 190,
        });
    }

    // 敌方慢速红弹丸
    spawnOrb(from, dir, speed, damage) {
        return this._spawn({
            friendly: false, kind: 'orb',
            from: from.clone(), dir: dir.clone(),
            speed: speed || 17, damage: damage || 1, color: 0xff2222,
            radius: 0.19, pierce: false, maxRange: 130,
        });
    }

    // 榴弹（抛物线，落地爆炸）
    spawnGrenade(from, velocity, friendly) {
        return this._spawn({
            friendly: !!friendly, kind: 'grenade',
            from: from.clone(), dir: velocity.clone().normalize(), velocity: velocity.clone(),
            speed: 0, damage: 1, color: friendly ? 0xaaffaa : 0xff8830,
            radius: 0.15, pierce: false, maxRange: 200,
        });
    }

    // Boss 圆盘弹
    spawnDisc(from, dir, speed) {
        return this._spawn({
            friendly: false, kind: 'disc',
            from: from.clone(), dir: dir.clone(),
            speed: speed || 15, damage: 1, color: 0xffcc33,
            radius: 0.5, pierce: false, maxRange: 130,
        });
    }

    spawnExplosionFX(pos, scale, color) {
        const mesh = new THREE.Mesh(this._geoSphere, new THREE.MeshBasicMaterial({
            color: color || 0xff6622, transparent: true, opacity: 0.9,
        }));
        mesh.position.copy(pos);
        mesh.scale.setScalar(0.3);
        this.scene.add(mesh);
        this.effects.push({ mesh, t: 0, scale: scale || 2.2 });
        AudioManager.explosion();
    }

    update(dt, ctx) {
        // ctx: { targets, colliders, player, onPlayerHit(damage) }
        const player = ctx.player;
        for (let i = this.list.length - 1; i >= 0; i--) {
            const p = this.list[i];
            if (!p.alive) { this._removeAt(i); continue; }
            p.t += dt;

            if (p.kind === 'grenade') {
                p.velocity.y -= 16 * dt;
                const step = p.velocity.clone().multiplyScalar(dt);
                p.mesh.position.add(step);
                p.travelled += step.length();
                const pos = p.mesh.position;
                if (pos.y <= 0.16 || this._hitsWorld(pos, ctx.colliders, p.radius)) {
                    this._explode(p, ctx);
                    p.alive = false;
                }
                continue;
            }

            const moveLen = p.speed * dt;
            const steps = Math.max(1, Math.ceil(moveLen / 0.35));
            const sub = moveLen / steps;
            for (let s = 0; s < steps && p.alive; s++) {
                p.mesh.position.addScaledVector(p.dir, sub);
                p.travelled += sub;
                const pos = p.mesh.position;
                if (p.wave) {
                    // 火球波浪轨迹：在垂直于 dir 的平面内正弦摆动（仅视觉+判定同步偏移）
                    const side = Math.sin(p.t * 14 + p.wavePhase) * 0.35;
                    pos.y += Math.cos(p.t * 14 + p.wavePhase) * 0.006;
                    p._waveSide = side;
                }
                if (pos.y <= 0.04) { this._impact(p, ctx); break; }
                if (this._hitsWorld(pos, ctx.colliders, p.radius * 0.6)) { this._impact(p, ctx); break; }
                if (p.friendly) {
                    if (this._hitTargets(p, ctx.targets)) break;
                } else {
                    if (this._hitPlayer(p, player)) { ctx.onPlayerHit(p.damage); p.alive = false; break; }
                }
            }
            if (p.travelled > p.maxRange) p.alive = false;
            if (p.kind === 'disc') p.mesh.rotation.y += dt * 12;
            if (!p.alive) this._removeAt(i);
        }

        // 爆炸特效
        for (let i = this.effects.length - 1; i >= 0; i--) {
            const e = this.effects[i];
            e.t += dt;
            const k = e.t / 0.45;
            if (k >= 1) {
                this.scene.remove(e.mesh);
                e.mesh.material.dispose();
                this.effects.splice(i, 1);
            } else {
                e.mesh.scale.setScalar(0.3 + e.scale * k);
                e.mesh.material.opacity = 0.9 * (1 - k);
            }
        }
    }

    _hitsWorld(pos, colliders, pad) {
        for (const c of colliders) {
            // 贴地步行面（低矮台阶/桥面）不挡子弹：只挡高于 1.2 的实体
            if ((c.h || 6) <= 1.2 && (c.y0 || 0) === 0) continue;
            if (WorldHit.pointHitsCollider(pos.x, pos.y, pos.z, c, pad)) return true;
        }
        return false;
    }

    _hitTargets(p, targets) {
        const pos = p.mesh.position;
        for (const t of targets) {
            if (!t.alive || p.hitSet.has(t)) continue;
            const dx = pos.x - t.hitX, dy = pos.y - t.hitY, dz = pos.z - t.hitZ;
            const rr = t.hitR + p.radius;
            if (dx * dx + dy * dy + dz * dz <= rr * rr) {
                t.onHit(p.damage, pos);
                if (!p.pierce) { p.alive = false; return true; }
                p.hitSet.add(t);
                return false;
            }
        }
        return false;
    }

    _hitPlayer(p, player) {
        if (!player || !player.alive) return false;
        const pos = p.mesh.position;
        const dx = pos.x - player.position.x, dz = pos.z - player.position.z;
        const rr = player.radius + p.radius;
        if (dx * dx + dz * dz > rr * rr) return false;
        const h = player.prone ? CONFIG.player.proneHeight : CONFIG.player.height;
        return pos.y >= player.position.y - 0.1 && pos.y <= player.position.y + h + p.radius;
    }

    _explode(p, ctx) {
        const pos = p.mesh.position.clone();
        pos.y = Math.max(0.3, pos.y);
        this.spawnExplosionFX(pos, 2.4);
        if (!p.friendly && ctx.player && ctx.player.alive) {
            const d = pos.distanceTo(new THREE.Vector3(ctx.player.position.x, ctx.player.position.y + 0.6, ctx.player.position.z));
            if (d < 2.4) ctx.onPlayerHit(1);
        }
        if (p.friendly) {
            for (const t of ctx.targets) {
                if (!t.alive) continue;
                const d = pos.distanceTo(new THREE.Vector3(t.hitX, t.hitY, t.hitZ));
                if (d < 2.6) t.onHit(p.damage || 40, pos);
            }
        }
    }

    _impact(p, ctx) {
        if (p.kind === 'grenade') this._explode(p, ctx);
        p.alive = false;
    }

    _removeAt(i) {
        const p = this.list[i];
        this.scene.remove(p.mesh);
        this.list.splice(i, 1);
    }

    clear() {
        for (const p of this.list) this.scene.remove(p.mesh);
        this.list = [];
        for (const e of this.effects) { this.scene.remove(e.mesh); e.mesh.material.dispose(); }
        this.effects = [];
    }

    destroy() {
        this.clear();
        this._geoSphere.dispose();
        this._geoDisc.dispose();
        Object.values(this._mats).forEach((m) => m.dispose());
    }
}
