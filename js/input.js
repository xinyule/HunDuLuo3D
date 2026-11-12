/**
 * 输入管理模块 — 键盘/鼠标 + 触屏
 */
class InputManager {
    constructor(domElement) {
        this.dom = domElement;
        this.keys = {};
        this.mouseDown = false;
        this.mouseX = 0;
        this.mouseY = 0;
        this.pointerLocked = false;

        // 触屏状态
        this.isTouch = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
        this.joystickActive = false;
        this.joystickVec = { x: 0, y: 0 };
        this.joystickCenter = { x: 0, y: 0 };
        this.joystickId = null;
        this.shootHeld = false;

        // 视角控制（累积值）
        this.yaw = 0;   // 水平旋转
        this.pitch = 0; // 垂直旋转
        this.sensitivity = 0.0024;

        // 拖屏转向（触屏）
        this.dragLookActive = false;
        this.dragLookLastX = 0;
        this.dragLookLastY = 0;

        this._init();
    }

    _init() {
        // 键盘
        window.addEventListener('keydown', (e) => {
            this.keys[e.code] = true;
            if (e.code === 'KeyR') this.reloadRequested = true;
            if (e.code === 'Space') this.shootRequested = true;
            if (e.code === 'Digit1') this.weaponSwitchRequested = 0;
            if (e.code === 'Digit2') this.weaponSwitchRequested = 1;
            if (e.code === 'Digit3') this.weaponSwitchRequested = 2;
            if (e.code === 'Digit4') this.weaponSwitchRequested = 3;
        });
        window.addEventListener('keyup', (e) => {
            this.keys[e.code] = false;
        });

        // 鼠标
        this.dom.addEventListener('mousedown', (e) => {
            if (e.button === 0) { this.mouseDown = true; this.shootRequested = true; }
        });
        this.dom.addEventListener('mouseup', (e) => {
            if (e.button === 0) this.mouseDown = false;
        });

        // 鼠标移动（指针锁定模式）
        document.addEventListener('mousemove', (e) => {
            if (this.pointerLocked) {
                this.yaw -= e.movementX * this.sensitivity;
                this.pitch -= e.movementY * this.sensitivity;
                this.pitch = Utils.clamp(this.pitch, -Math.PI / 2 + 0.1, Math.PI / 2 - 0.1);
            }
        });

        // 指针锁定
        this.dom.addEventListener('click', () => {
            if (!this.pointerLocked && Game.state === 'playing') {
                this.dom.requestPointerLock();
            }
        });
        document.addEventListener('pointerlockchange', () => {
            this.pointerLocked = document.pointerLockElement === this.dom;
        });

        // 触屏
        if (this.isTouch) {
            this._initTouch();
        }
    }

    _initTouch() {
        const joyArea = document.getElementById('joystickArea');
        const knob = document.getElementById('joystickKnob');
        const shootBtn = document.getElementById('shootBtn');
        const reloadBtn = document.getElementById('reloadBtn');
        const wsBtns = document.querySelectorAll('.ws-btn');
        const canvas = document.getElementById('gameCanvas');

        // 摇杆
        joyArea.addEventListener('touchstart', (e) => {
            e.preventDefault();
            const t = e.changedTouches[0];
            this.joystickActive = true;
            this.joystickId = t.identifier;
            const rect = joyArea.getBoundingClientRect();
            this.joystickCenter = { x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
            this._updateJoystick(t.clientX, t.clientY);
        }, { passive: false });

        joyArea.addEventListener('touchmove', (e) => {
            e.preventDefault();
            for (let i = 0; i < e.touches.length; i++) {
                if (e.touches[i].identifier === this.joystickId) {
                    this._updateJoystick(e.touches[i].clientX, e.touches[i].clientY);
                    break;
                }
            }
        }, { passive: false });

        joyArea.addEventListener('touchend', (e) => {
            e.preventDefault();
            for (let i = 0; i < e.changedTouches.length; i++) {
                if (e.changedTouches[i].identifier === this.joystickId) {
                    this.joystickActive = false;
                    this.joystickId = null;
                    this.joystickVec = { x: 0, y: 0 };
                    knob.style.transform = 'translate(-50%, -50%)';
                    break;
                }
            }
        }, { passive: false });

        // 射击按钮
        const onShootStart = (e) => {
            e.preventDefault();
            this.shootHeld = true;
            this.shootRequested = true;
        };
        const onShootEnd = (e) => {
            e.preventDefault();
            this.shootHeld = false;
        };
        shootBtn.addEventListener('touchstart', onShootStart, { passive: false });
        shootBtn.addEventListener('touchend', onShootEnd, { passive: false });
        shootBtn.addEventListener('mousedown', onShootStart);
        shootBtn.addEventListener('mouseup', onShootEnd);

        // 换弹按钮
        reloadBtn.addEventListener('touchstart', (e) => {
            e.preventDefault();
            this.reloadRequested = true;
        }, { passive: false });
        reloadBtn.addEventListener('mousedown', () => { this.reloadRequested = true; });

        // 武器切换
        wsBtns.forEach(btn => {
            btn.addEventListener('touchstart', (e) => {
                e.preventDefault();
                this.weaponSwitchRequested = parseInt(btn.dataset.weapon);
            }, { passive: false });
            btn.addEventListener('mousedown', () => {
                this.weaponSwitchRequested = parseInt(btn.dataset.weapon);
            });
        });

        // 拖屏转向（在画布上滑动）
        canvas.addEventListener('touchstart', (e) => {
            e.preventDefault();
            this.dragLookActive = true;
            this.dragLookLastX = e.changedTouches[0].clientX;
            this.dragLookLastY = e.changedTouches[0].clientY;
        }, { passive: false });

        canvas.addEventListener('touchmove', (e) => {
            e.preventDefault();
            if (this.dragLookActive) {
                for (let i = 0; i < e.touches.length; i++) {
                    const t = e.touches[i];
                    const dx = t.clientX - this.dragLookLastX;
                    const dy = t.clientY - this.dragLookLastY;
                    this.yaw -= dx * this.sensitivity * 2;
                    this.pitch -= dy * this.sensitivity * 2;
                    this.pitch = Utils.clamp(this.pitch, -Math.PI / 2 + 0.1, Math.PI / 2 - 0.1);
                    this.dragLookLastX = t.clientX;
                    this.dragLookLastY = t.clientY;
                }
            }
        }, { passive: false });

        canvas.addEventListener('touchend', () => {
            this.dragLookActive = false;
        }, { passive: false });
    }

    _updateJoystick(x, y) {
        const dx = x - this.joystickCenter.x;
        const dy = y - this.joystickCenter.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        const maxDist = 40;
        const factor = Math.min(dist / maxDist, 1);
        const angle = Math.atan2(dy, dx);
        this.joystickVec.x = Math.cos(angle) * factor;
        this.joystickVec.y = Math.sin(angle) * factor;
        const knob = document.getElementById('joystickKnob');
        if (knob) {
            knob.style.transform = `translate(calc(-50% + ${dx * 0.5}px), calc(-50% + ${dy * 0.5}px))`;
        }
    }

    // 获取移动方向（归一化的 WASD 向量）
    getMoveVector() {
        let x = 0, z = 0;
        if (this.keys['KeyW'] || this.keys['ArrowUp']) z -= 1;
        if (this.keys['KeyS'] || this.keys['ArrowDown']) z += 1;
        if (this.keys['KeyA'] || this.keys['ArrowLeft']) x -= 1;
        if (this.keys['KeyD'] || this.keys['ArrowRight']) x += 1;

        // 触屏摇杆
        if (this.joystickActive) {
            x += this.joystickVec.x;
            z += this.joystickVec.y;
        }

        const len = Math.sqrt(x * x + z * z);
        if (len > 0) {
            x /= len;
            z /= len;
        }
        return { x, z, magnitude: len };
    }

    isRunning() {
        return this.keys['ShiftLeft'] || this.keys['ShiftRight'] || false;
    }

    isShooting() {
        return this.mouseDown || this.shootHeld || this.keys['Space'] || false;
    }

    // 获取并消费一次性事件
    consumeShoot() {
        const r = this.shootRequested || false;
        this.shootRequested = false;
        return r;
    }

    consumeReload() {
        const r = this.reloadRequested || false;
        this.reloadRequested = false;
        return r;
    }

    consumeWeaponSwitch() {
        const r = this.weaponSwitchRequested;
        this.weaponSwitchRequested = null;
        return r;
    }
}
