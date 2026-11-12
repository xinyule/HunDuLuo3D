/**
 * 主引擎 — 状态机是唯一有权改 state 的地方（旧版阵亡软死的根源即在于此）
 * 状态：menu / dialog / playing / levelclear / gameover / victory
 */
const Game = {
    state: 'menu',
    levelIndex: 0,
    score: 0,
    lives: CONFIG.player.startLives,
    _nextExtend: CONFIG.player.extendScore,

    scene: null, camera: null, renderer: null, clock: null,
    input: null, cameraRig: null, projectiles: null,
    player: null, currentLevel: null,
    checkpoint: { x: 0, y: 0, z: 26 },
    _dialogCallback: null,

    _init() {
        const canvas = document.getElementById('gameCanvas');
        this.scene = new THREE.Scene();
        this.scene.background = new THREE.Color(0x0a0a15);
        this.camera = new THREE.PerspectiveCamera(CONFIG.renderer.fov, window.innerWidth / window.innerHeight, CONFIG.renderer.near, CONFIG.renderer.far);
        this.camera.position.set(0, 3, 38);
        this.renderer = new THREE.WebGLRenderer({ canvas, antialias: CONFIG.renderer.antialias });
        this.renderer.setSize(window.innerWidth, window.innerHeight);
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
        this.clock = new THREE.Clock();
        this.input = new InputManager(canvas);
        this.cameraRig = new ThirdPersonCamera(this.camera);
        this.projectiles = new ProjectileSystem(this.scene);
        window.addEventListener('resize', () => this._onResize());
        this._bindUI();
        this._addMenuBackground();
        this._render();
    },

    _bindUI() {
        const on = (id, fn) => { const el = document.getElementById(id); if (el) el.addEventListener('click', fn); };
        on('btnStart', () => this.startGame());
        on('btnControls', () => document.getElementById('controlsPanel').classList.remove('hidden'));
        on('btnControlsClose', () => document.getElementById('controlsPanel').classList.add('hidden'));
        on('btnRetry', () => this.startGame());
        on('btnMenu', () => this.showMenu());
        on('btnVictoryRetry', () => this.startGame());
        on('btnVictoryMenu', () => this.showMenu());
        on('dialog', () => { if (this._dialogCallback) this._dialogCallback(); });
    },

    _onResize() {
        this.camera.aspect = window.innerWidth / window.innerHeight;
        this.camera.updateProjectionMatrix();
        this.renderer.setSize(window.innerWidth, window.innerHeight);
    },

    _render() {
        requestAnimationFrame(() => this._render());
        const dt = Math.min(this.clock.getDelta(), 0.05);
        if (this.state === 'playing') this._updateGame(dt);
        if (this.renderer && this.scene && this.camera) this.renderer.render(this.scene, this.camera);
    },

    _updateGame(dt) {
        const player = this.player, level = this.currentLevel;
        if (!player || !level) return;
        const aiming = this.input.isAiming() || this.input.isShooting();
        const shooting = this.input.isShooting();

        player.update(dt, this.input, level, this.input.yaw, aiming);

        const targets = level.getTargets();
        this.cameraRig.update(dt, {
            anchor: { x: player.position.x, y: player.position.y, z: player.position.z, prone: player.prone },
            yaw: this.input.yaw, pitch: this.input.pitch,
            aiming, colliders: level.colliders, targets,
        });

        if (shooting && player.alive) player.tryShoot(this.projectiles, this.cameraRig.aimPoint);

        level.update(dt, player, this.camera.position);
        this.projectiles.update(dt, {
            targets: level.getTargets(), colliders: level.colliders, player,
            onPlayerHit: (d) => player.takeDamage(d),
        });

        this._updateHUD();
    },

    // ---------------- 流程 ----------------
    startGame() {
        this.score = 0;
        this.lives = CONFIG.player.startLives;
        this._nextExtend = CONFIG.player.extendScore;
        this.levelIndex = 0;
        AudioManager.init();
        document.getElementById('mainMenu').classList.add('hidden');
        document.getElementById('gameOverScreen').classList.add('hidden');
        document.getElementById('victoryScreen').classList.add('hidden');
        this._loadLevel(0, true);
    },

    _loadLevel(index, freshRun) {
        if (this.currentLevel) { this.currentLevel.destroy(); this.currentLevel = null; }
        this.projectiles.clear();
        // 清理菜单粒子等残留
        const toRemove = this.scene.children.filter((c) => c.userData && c.userData.isMenuParticle);
        for (const o of toRemove) { this.scene.remove(o); Utils.disposeObject(o); }

        if (!this.player) {
            this.player = new Player(this.scene);
            this.player.onDeath = () => this._onPlayerDeath();
            this.player.onDamaged = () => this._updateHUD();
        }
        const data = LEVELS_DATA[index];
        const spawn = { x: 0, y: 0, z: 26 };
        this.checkpoint = spawn;
        this.player.reset(spawn, !freshRun && index > 0);

        this.currentLevel = new Level(this.scene, data, index, {
            projectiles: this.projectiles,
            onScore: (n) => this._addScore(n),
            onPickup: (letter) => { this.player.applyPickup(letter); this._showCenterMsg(this._pickupText(letter), 1100); this._updateHUD(); },
            onCheckpoint: (p) => { this.checkpoint = p; },
            onBossActivated: (boss) => {
                document.getElementById('bossBar').classList.remove('hidden');
                document.getElementById('bossName').textContent = 'BOSS · ' + BOSS_DATA[boss.id].name;
                this._showCenterMsg('⚠ ' + BOSS_DATA[boss.id].name + ' ⚠', 1800);
            },
            onBossDefeated: () => this._onBossDefeated(),
        });

        this.input.yaw = Math.PI;
        this.input.pitch = 0;
        this.cameraRig.snapTo({ x: 0, y: 0, z: 26, prone: false }, Math.PI, 0);

        document.getElementById('hud').classList.remove('hidden');
        document.getElementById('bossBar').classList.add('hidden');
        document.getElementById('touchControls').classList.toggle('hidden', !this.input.isTouch);
        this._updateHUD();
        this._showDialog(data.story, () => {
            if (!this.input.isTouch) this.input.dom.requestPointerLock();
        });
    },

    _pickupText(letter) {
        if (letter === 'R') return 'R · 子弹加速！';
        if (letter === 'B') return 'B · 防护罩！';
        if (letter === '+') return '+1 格血';
        const w = WEAPON_DATA[letter];
        return w ? (w.letter + ' · ' + w.name + '！') : '';
    },

    _showDialog(text, callback) {
        this.state = 'dialog';
        document.getElementById('dialogText').textContent = text;
        document.getElementById('dialog').classList.remove('hidden');
        this._dialogCallback = () => {
            document.getElementById('dialog').classList.add('hidden');
            this._dialogCallback = null;
            this.state = 'playing';
            if (callback) callback();
        };
    },

    _showCenterMsg(text, duration, callback) {
        const msg = document.getElementById('centerMsg');
        msg.textContent = text;
        msg.classList.remove('hidden');
        msg.classList.add('show');
        setTimeout(() => {
            msg.classList.remove('show');
            setTimeout(() => { msg.classList.add('hidden'); if (callback) callback(); }, 400);
        }, duration || 1500);
    },

    _addScore(n) {
        this.score += n;
        while (this.score >= this._nextExtend) {
            this._nextExtend += CONFIG.player.extendScore;
            this.lives++;
            this._showCenterMsg('延长！命 +1（×' + this.lives + '）', 1400);
        }
        this._updateHUD();
    },

    _onPlayerDeath() {
        // 只有 Game 能决定生死流转；Player.takeDamage 只发回调
        this.lives--;
        AudioManager.gameOver();
        if (this.lives > 0) {
            this.projectiles.clear();
            this.player.respawn(this.checkpoint);
            this._showCenterMsg('阵亡！剩余命 ×' + this.lives, 1600);
            this._updateHUD();
        } else {
            this.state = 'gameover';
            document.getElementById('gameOverText').textContent = '倒在了' + LEVELS_DATA[this.levelIndex].name + ' · 分数 ' + this.score;
            document.getElementById('hud').classList.add('hidden');
            document.getElementById('touchControls').classList.add('hidden');
            document.getElementById('gameOverScreen').classList.remove('hidden');
            if (document.pointerLockElement) document.exitPointerLock();
        }
    },

    _onBossDefeated() {
        if (this.state !== 'playing') return;
        this.state = 'levelclear';
        AudioManager.levelComplete();
        document.getElementById('bossBar').classList.add('hidden');
        this.projectiles.clear();
        if (this.levelIndex >= LEVELS_DATA.length - 1) {
            setTimeout(() => {
                this.state = 'victory';
                document.getElementById('finalScore').textContent = this.score;
                document.getElementById('hud').classList.add('hidden');
                document.getElementById('touchControls').classList.add('hidden');
                document.getElementById('victoryScreen').classList.remove('hidden');
                if (document.pointerLockElement) document.exitPointerLock();
            }, 1400);
        } else {
            const nextName = LEVELS_DATA[this.levelIndex + 1].name;
            this._showCenterMsg('关卡完成！下一关：' + nextName, 2000, () => {
                this.levelIndex++;
                this._loadLevel(this.levelIndex, false);
            });
        }
    },

    showMenu() {
        this.state = 'menu';
        if (this.currentLevel) { this.currentLevel.destroy(); this.currentLevel = null; }
        if (this.player) { this.player.destroy(); this.player = null; }
        this.projectiles.clear();
        document.getElementById('hud').classList.add('hidden');
        document.getElementById('touchControls').classList.add('hidden');
        document.getElementById('gameOverScreen').classList.add('hidden');
        document.getElementById('victoryScreen').classList.add('hidden');
        document.getElementById('mainMenu').classList.remove('hidden');
        this.scene.background = new THREE.Color(0x0a0a15);
        this.scene.fog = null;
        this.camera.position.set(0, 3, 38);
        this.camera.lookAt(0, 2, 0);
        this._addMenuBackground();
    },

    _addMenuBackground() {
        const old = this.scene.children.filter((c) => c.userData && c.userData.isMenuParticle);
        for (const p of old) { this.scene.remove(p); Utils.disposeObject(p); }
        const starGeo = new THREE.BufferGeometry();
        const count = 200;
        const positions = new Float32Array(count * 3);
        for (let i = 0; i < count * 3; i += 3) {
            positions[i] = (Math.random() - 0.5) * 200;
            positions[i + 1] = Math.random() * 100;
            positions[i + 2] = (Math.random() - 0.5) * 200;
        }
        starGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        const stars = new THREE.Points(starGeo, new THREE.PointsMaterial({ color: 0xff6b35, size: 0.5, transparent: true, opacity: 0.6 }));
        stars.userData.isMenuParticle = true;
        this.scene.add(stars);
    },

    // ---------------- HUD ----------------
    _updateHUD() {
        if (!this.player || !this.currentLevel) return;
        const p = this.player;
        const hearts = document.getElementById('hearts');
        if (hearts) hearts.textContent = '❤'.repeat(p.hpCells) + '🖤'.repeat(Math.max(0, CONFIG.player.maxCells - p.hpCells));
        const livesEl = document.getElementById('livesValue');
        if (livesEl) livesEl.textContent = '×' + Math.max(0, this.lives);
        const w = WEAPON_DATA[p.weapon];
        const weaponEl = document.getElementById('weaponName');
        if (weaponEl) weaponEl.textContent = w.letter + ' · ' + w.name + (p.rapid ? ' +R' : '') + (p.barrier > 0 ? ' · 罩' + Math.ceil(p.barrier) + 's' : '');
        const scoreEl = document.getElementById('scoreValue');
        if (scoreEl) scoreEl.textContent = this.score;
        const levelEl = document.getElementById('levelName');
        if (levelEl) levelEl.textContent = this.currentLevel.data.name;
        const dist = Utils.clamp(this.currentLevel.playerDist(p), 0, this.currentLevel.length);
        const fill = document.getElementById('objectiveFill');
        if (fill) fill.style.width = (dist / this.currentLevel.length * 100) + '%';
        const prog = document.getElementById('progressText');
        if (prog) prog.textContent = Math.floor(dist) + 'm / ' + this.currentLevel.length + 'm';
        if (this.currentLevel.bossActive) {
            const bf = document.getElementById('bossFill');
            if (bf) bf.style.width = (this.currentLevel.bossFraction * 100) + '%';
        }
    },
};

window.addEventListener('DOMContentLoaded', () => { Game._init(); });
