/**
 * 主游戏引擎 — 渲染循环、UI管理、状态机
 */
const Game = {
    // 状态: menu, playing, gameover, victory, loading, dialog
    state: 'menu',
    levelIndex: 0,

    // Three.js 核心
    scene: null,
    camera: null,
    renderer: null,
    clock: null,

    // 游戏对象
    input: null,
    player: null,
    currentLevel: null,

    // UI 元素
    hud: null,

    _init() {
        const canvas = document.getElementById('gameCanvas');

        // 场景
        this.scene = new THREE.Scene();
        this.scene.background = new THREE.Color(0x0a0a15);

        // 相机
        this.camera = new THREE.PerspectiveCamera(
            CONFIG.renderer.fov,
            window.innerWidth / window.innerHeight,
            CONFIG.renderer.near,
            CONFIG.renderer.far
        );

        // 渲染器
        this.renderer = new THREE.WebGLRenderer({
            canvas,
            antialias: CONFIG.renderer.antialias,
        });
        this.renderer.setSize(window.innerWidth, window.innerHeight);
        this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

        // 时钟
        this.clock = new THREE.Clock();

        // 输入管理
        this.input = new InputManager(canvas);

        // 窗口大小调整
        window.addEventListener('resize', () => this._onResize());

        // 绑定按钮
        this._bindUI();

        // 菜单背景
        this._addMenuBackground();

        // 开始渲染循环（显示菜单背景）
        this._render();
    },

    _bindUI() {
        document.getElementById('btnStart').addEventListener('click', () => this.startGame());
        document.getElementById('btnControls').addEventListener('click', () => {
            document.getElementById('controlsPanel').classList.remove('hidden');
        });
        document.getElementById('btnControlsClose').addEventListener('click', () => {
            document.getElementById('controlsPanel').classList.add('hidden');
        });
        document.getElementById('btnRetry').addEventListener('click', () => this.startGame());
        document.getElementById('btnMenu').addEventListener('click', () => this.showMenu());
        document.getElementById('btnVictoryRetry').addEventListener('click', () => this.startGame());
        document.getElementById('btnVictoryMenu').addEventListener('click', () => this.showMenu());

        // 对话框点击继续
        document.getElementById('dialog').addEventListener('click', () => {
            if (this._dialogCallback) this._dialogCallback();
        });
    },

    _onResize() {
        this.camera.aspect = window.innerWidth / window.innerHeight;
        this.camera.updateProjectionMatrix();
        this.renderer.setSize(window.innerWidth, window.innerHeight);
    },

    _render() {
        requestAnimationFrame(() => this._render());
        const deltaTime = Math.min(this.clock.getDelta(), 0.1);

        if (this.state === 'playing') {
            this._updateGame(deltaTime);
        }

        if (this.renderer && this.scene && this.camera) {
            this.renderer.render(this.scene, this.camera);
        }
    },

    _updateGame(deltaTime) {
        // 检查玩家是否阵亡
        if (!this.player.alive) {
            this._onPlayerDeath();
            return;
        }

        // 处理输入
        // 换弹
        if (this.input.consumeReload()) {
            this.player.reload();
        }

        // 武器切换
        const ws = this.input.consumeWeaponSwitch();
        if (ws !== null && ws !== undefined) {
            this.player.switchWeapon(ws);
        }

        // 射击 — 直接调用 player.shoot
        const w = this.player.getCurrentWeapon();
        const wantShoot = w.auto ? this.input.isShooting() : this.input.consumeShoot();
        if (wantShoot) {
            this.player.shoot(this.currentLevel.enemies);
        }

        // 更新玩家
        this.player.update(deltaTime, this.input, this.currentLevel);

        // 更新关卡（敌人AI等）
        this.currentLevel.update(deltaTime);

        // 更新触屏武器切换高亮
        this._updateWeaponSwitchUI();
    },

    _updateWeaponSwitchUI() {
        const btns = document.querySelectorAll('.ws-btn');
        btns.forEach((btn, i) => {
            btn.classList.toggle('active', i === this.player.currentWeapon);
        });
    },

    startGame() {
        this.levelIndex = 0;
        this.state = 'loading';
        this._showLoading();

        // 清理旧关卡
        if (this.currentLevel) {
            this.currentLevel.destroy();
            this.currentLevel = null;
        }

        // 清理旧玩家
        if (this.player) {
            this.player.destroy();
            this.player = null;
        }

        // 清理场景中的旧物体
        const toRemove = this.scene.children.filter(c => !c.isCamera && !c.isLight && !c.userData.isMenuParticle);
        for (const obj of toRemove) this.scene.remove(obj);

        // 初始化音频
        AudioManager.init();

        // 加载第一关
        setTimeout(() => this._loadLevel(0), 1000);
    },

    _showLoading() {
        document.getElementById('mainMenu').classList.add('hidden');
        document.getElementById('gameOverScreen').classList.add('hidden');
        document.getElementById('victoryScreen').classList.add('hidden');
        document.getElementById('loadingScreen').classList.remove('hidden');
        document.getElementById('loadingFill').style.width = '30%';
        document.getElementById('loadingText').textContent = '加载中...';
    },

    _loadLevel(index) {
        // 清理旧关卡
        if (this.currentLevel) {
            this.currentLevel.destroy();
            this.currentLevel = null;
        }
        if (this.player) {
            this.player.destroy();
            this.player = null;
        }

        // 清理场景中上一关的物体
        const toRemove = this.scene.children.filter(c => !c.isCamera && !c.isLight && !c.userData.isMenuParticle);
        for (const obj of toRemove) this.scene.remove(obj);

        const levelData = LEVELS_DATA[index];
        this.currentLevel = new Level(this.scene, levelData, index);
        this.player = new Player(this.scene, this.camera, this.currentLevel.colliders);

        // 设置输入视角
        this.input.yaw = 0;
        this.input.pitch = 0;

        // 更新 UI
        document.getElementById('levelName').textContent = levelData.name;
        document.getElementById('enemyKilled').textContent = '0';
        document.getElementById('enemyTotal').textContent = this.currentLevel.totalEnemies;
        document.getElementById('objectiveFill').style.width = '0%';

        // 显示 HUD
        document.getElementById('hud').classList.remove('hidden');
        document.getElementById('loadingScreen').classList.add('hidden');

        // 触屏控件
        if (this.input.isTouch) {
            document.getElementById('touchControls').classList.remove('hidden');
        } else {
            document.getElementById('touchControls').classList.add('hidden');
        }

        // 显示剧情
        this.state = 'playing';
        if (levelData.story) {
            this._showDialog(levelData.story, () => {
                // 对话框关闭后开始游戏
                if (!this.input.isTouch) {
                    // 桌面端：锁定鼠标实现视角控制
                    this.input.dom.requestPointerLock();
                }
            });
        } else {
            if (!this.input.isTouch) {
                this.input.dom.requestPointerLock();
            }
        }

        this._updateWeaponSwitchUI();
        document.getElementById('loadingFill').style.width = '100%';
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

    onLevelComplete() {
        if (this.levelIndex >= LEVELS_DATA.length - 1) {
            // 通关
            this.state = 'victory';
            document.getElementById('hud').classList.add('hidden');
            document.getElementById('touchControls').classList.add('hidden');
            document.getElementById('finalScore').textContent = this.player.score;
            document.getElementById('victoryScreen').classList.remove('hidden');
            if (document.pointerLockElement) document.exitPointerLock();
        } else {
            // 下一关
            this.levelIndex++;
            const nextData = LEVELS_DATA[this.levelIndex];
            this._showCenterMsg(nextData.name, 2000, () => {
                this._showDialog(nextData.story || '', () => {
                    this._loadLevel(this.levelIndex);
                });
            });
        }
    },

    _showCenterMsg(text, duration, callback) {
        const msg = document.getElementById('centerMsg');
        msg.textContent = text;
        msg.classList.remove('hidden');
        msg.classList.add('show');
        setTimeout(() => {
            msg.classList.remove('show');
            setTimeout(() => {
                msg.classList.add('hidden');
                if (callback) callback();
            }, 500);
        }, duration);
    },

    _onPlayerDeath() {
        if (this.state !== 'playing') return; // 防止重复触发
        this.state = 'gameover';
        AudioManager.gameOver();
        document.getElementById('finalScore').textContent = this.player.score;
        document.getElementById('hud').classList.add('hidden');
        document.getElementById('touchControls').classList.add('hidden');
        document.getElementById('gameOverScreen').classList.remove('hidden');
        if (document.pointerLockElement) document.exitPointerLock();
    },

    showMenu() {
        this.state = 'menu';
        document.getElementById('hud').classList.add('hidden');
        document.getElementById('touchControls').classList.add('hidden');
        document.getElementById('gameOverScreen').classList.add('hidden');
        document.getElementById('victoryScreen').classList.add('hidden');
        document.getElementById('loadingScreen').classList.add('hidden');
        document.getElementById('mainMenu').classList.remove('hidden');

        // 清理场景
        if (this.currentLevel) {
            this.currentLevel.destroy();
            this.currentLevel = null;
        }
        if (this.player) {
            this.player.destroy();
            this.player = null;
        }

        // 清理场景中所有非灯光物体
        const toRemove = this.scene.children.filter(c => !c.isLight && !c.userData.isMenuParticle);
        for (const obj of toRemove) this.scene.remove(obj);

        this.scene.background = new THREE.Color(0x0a0a15);
        this.scene.fog = null;

        // 菜单背景：添加粒子效果
        this._addMenuBackground();
    },

    _addMenuBackground() {
        // 清除旧的
        const oldParticles = this.scene.children.filter(c => c.userData.isMenuParticle);
        for (const p of oldParticles) this.scene.remove(p);

        // 添加星星
        const starGeo = new THREE.BufferGeometry();
        const starCount = 200;
        const positions = new Float32Array(starCount * 3);
        for (let i = 0; i < starCount * 3; i += 3) {
            positions[i] = (Math.random() - 0.5) * 200;
            positions[i + 1] = Math.random() * 100;
            positions[i + 2] = (Math.random() - 0.5) * 200;
        }
        starGeo.setAttribute('position', new THREE.BufferAttribute(positions, 3));
        const starMat = new THREE.PointsMaterial({ color: 0xff6b35, size: 0.5, transparent: true, opacity: 0.6 });
        const stars = new THREE.Points(starGeo, starMat);
        stars.userData.isMenuParticle = true;
        this.scene.add(stars);
    },

};

// 启动游戏
window.addEventListener('DOMContentLoaded', () => {
    Game._init();
});
