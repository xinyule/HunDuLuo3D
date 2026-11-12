/**
 * 道具系统 — 飞鹰徽章（Falcon）与掉落拾取
 * 飞鹰从走廊上方横飞，打下来掉字母道具：N/M/F/L/S 换枪、R 加速、B 防护罩、+ 回 1 格血。
 * （本文件为旧版 WeaponSystem 的替代实现，射击逻辑已在 Player + ProjectileSystem 中。）
 */
class PickupSystem {
    constructor(scene, ctx) {
        this.scene = scene;
        this.ctx = ctx; // { onPickup(letter), onScore(n) }
        this.items = [];
        this.falcon = null;
        this._texCache = {};
    }

    _letterTexture(letter) {
        if (this._texCache[letter]) return this._texCache[letter];
        const cv = document.createElement('canvas');
        cv.width = 128; cv.height = 128;
        const g = cv.getContext('2d');
        g.fillStyle = letter === '+' ? '#14532d' : '#5b1a1a';
        g.fillRect(0, 0, 128, 128);
        g.strokeStyle = '#ffd34d'; g.lineWidth = 8;
        g.strokeRect(6, 6, 116, 116);
        g.fillStyle = letter === '+' ? '#7dffa8' : '#ffe08a';
        g.font = 'bold 84px Arial';
        g.textAlign = 'center'; g.textBaseline = 'middle';
        g.fillText(letter, 64, 70);
        const tex = new THREE.CanvasTexture(cv);
        this._texCache[letter] = tex;
        return tex;
    }

    _makeItemMesh(letter) {
        const tex = this._letterTexture(letter);
        const mat = new THREE.MeshBasicMaterial({ map: tex });
        const mesh = new THREE.Mesh(new THREE.BoxGeometry(0.72, 0.72, 0.72),
            [mat, mat, mat, mat, mat, mat]);
        return mesh;
    }

    spawnLetter(x, y, z, letter) {
        const mesh = this._makeItemMesh(letter);
        mesh.position.set(x, y, z);
        this.scene.add(mesh);
        this.items.push({ mesh, letter, x, z, y, vy: 0, landed: false, t: Math.random() * 6 });
    }

    spawnHeal(x, z) {
        this.spawnLetter(x, 3.2, z, '+');
    }

    spawnFalcon(z, letter, corridorHalfWidth) {
        if (this.falcon) return;
        const group = new THREE.Group();
        const red = new THREE.MeshLambertMaterial({ color: 0xb02020 });
        const gold = new THREE.MeshLambertMaterial({ color: 0xd8a020 });
        const body = new THREE.Mesh(new THREE.CylinderGeometry(0.32, 0.32, 1.05, 10), red);
        body.rotation.z = Math.PI / 2;
        group.add(body);
        [-0.55, 0.55].forEach((wx) => {
            const wing = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.06, 0.34), gold);
            wing.position.set(wx, 0.12, -0.1);
            wing.rotation.z = wx > 0 ? -0.35 : 0.35;
            group.add(wing);
        });
        const eye = new THREE.Mesh(new THREE.SphereGeometry(0.1, 6, 6), new THREE.MeshBasicMaterial({ color: 0xffe08a }));
        eye.position.set(0, 0.1, 0.3);
        group.add(eye);
        const dir = Math.random() > 0.5 ? 1 : -1;
        const startX = -dir * (corridorHalfWidth + 3);
        group.position.set(startX, 6.4, z);
        this.scene.add(group);
        const self = this;
        const falcon = {
            mesh: group, dir, speed: 11, z, letter, alive: true, halfW: corridorHalfWidth,
            hitX: startX, hitY: 6.4, hitZ: z, hitR: 0.75,
            onHit() {
                if (!this.alive) return;
                this.alive = false;
                self.ctx.onScore(100);
                // 道具必须落在走廊内可拾取范围（曾有掉在墙外拿不到的 bug）
                const dropX = Utils.clamp(this.hitX, -this.halfW + 2, this.halfW - 2);
                self.spawnLetter(dropX, 5.6, this.z, this.letter);
                AudioManager.enemyDie();
            },
        };
        this.falcon = falcon;
    }

    update(dt, player, level) {
        // 飞鹰横飞
        if (this.falcon) {
            const f = this.falcon;
            if (!f.alive) {
                this.scene.remove(f.mesh); Utils.disposeObject(f.mesh);
                this.falcon = null;
            } else {
                f.mesh.position.x += f.dir * f.speed * dt;
                f.mesh.position.y = 6.4 + Math.sin(performance.now() / 280) * 0.25;
                f.mesh.rotation.y = f.dir > 0 ? Math.PI / 2 : -Math.PI / 2;
                f.hitX = f.mesh.position.x; f.hitY = f.mesh.position.y; f.hitZ = f.z;
                if (Math.abs(f.mesh.position.x) > level.width / 2 + 8) {
                    this.scene.remove(f.mesh); Utils.disposeObject(f.mesh);
                    this.falcon = null;
                }
            }
        }
        // 道具下落/拾取
        for (let i = this.items.length - 1; i >= 0; i--) {
            const it = this.items[i];
            it.t += dt;
            if (!it.landed) {
                const groundY = level.getSupportY(it.x, it.z, it.y) + 0.55;
                it.y -= 3.4 * dt;
                if (it.y <= groundY) { it.y = groundY; it.landed = true; }
                it.mesh.position.set(it.x, it.y, it.z);
            } else {
                it.mesh.position.y = it.y + Math.sin(it.t * 3.2) * 0.09;
            }
            it.mesh.rotation.y += dt * 2.4;
            const dx = player.position.x - it.x, dz = player.position.z - it.z;
            const dy = (player.position.y + 0.9) - it.mesh.position.y;
            if (dx * dx + dz * dz < 1.7 && Math.abs(dy) < 1.9 && player.alive) {
                this.ctx.onPickup(it.letter);
                this.scene.remove(it.mesh);
                this.items.splice(i, 1);
            }
        }
    }

    getFalconTarget() { return this.falcon && this.falcon.alive ? this.falcon : null; }

    destroy() {
        if (this.falcon) { this.scene.remove(this.falcon.mesh); Utils.disposeObject(this.falcon.mesh); this.falcon = null; }
        for (const it of this.items) this.scene.remove(it.mesh);
        this.items = [];
        Object.values(this._texCache).forEach((t) => t.dispose());
        this._texCache = {};
    }
}
