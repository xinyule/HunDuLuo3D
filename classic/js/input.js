/**
 * 输入 — 键鼠（指针锁定）+ 触屏
 * 左键射击 / 右键瞄准 / 空格跳跃 / C或Ctrl趴下 / Shift疾跑 / WASD移动
 */
class InputManager {
    constructor(domElement) {
        this.dom = domElement;
        this.keys = {};
        this.mouseDown = false;
        this.rightDown = false;
        this.pointerLocked = false;
        this.yaw = Math.PI;   // 初始朝 -Z
        this.pitch = 0;
        this.sensitivity = 0.0023;

        this.isTouch = ('ontouchstart' in window) || navigator.maxTouchPoints > 0;
        this.joystickActive = false;
        this.joystickVec = { x: 0, y: 0 };
        this.joystickCenter = { x: 0, y: 0 };
        this.joystickId = null;
        this.shootHeld = false;
        this.proneToggle = false;
        this.jumpRequested = false;
        this.dragLookActive = false;
        this.dragLookLastX = 0;
        this.dragLookLastY = 0;

        this._init();
    }

    _init() {
        window.addEventListener('keydown', (e) => {
            this.keys[e.code] = true;
            if (e.code === 'Space') { this.jumpRequested = true; e.preventDefault(); }
            if (e.code === 'ArrowUp' || e.code === 'ArrowDown' || e.code === 'ArrowLeft' || e.code === 'ArrowRight') e.preventDefault();
        });
        window.addEventListener('keyup', (e) => { this.keys[e.code] = false; });

        this.dom.addEventListener('mousedown', (e) => {
            if (e.button === 0) this.mouseDown = true;
            if (e.button === 2) this.rightDown = true;
        });
        window.addEventListener('mouseup', (e) => {
            if (e.button === 0) this.mouseDown = false;
            if (e.button === 2) this.rightDown = false;
        });
        this.dom.addEventListener('contextmenu', (e) => e.preventDefault());

        document.addEventListener('mousemove', (e) => {
            if (this.pointerLocked) {
                this.yaw -= e.movementX * this.sensitivity;
                this.pitch -= e.movementY * this.sensitivity;
                this.pitch = Utils.clamp(this.pitch, CONFIG.camera.pitchMin, CONFIG.camera.pitchMax);
            }
        });

        this.dom.addEventListener('click', () => {
            if (!this.pointerLocked && typeof Game !== 'undefined' && Game.state === 'playing') {
                this.dom.requestPointerLock();
            }
        });
        document.addEventListener('pointerlockchange', () => {
            this.pointerLocked = document.pointerLockElement === this.dom;
        });

        if (this.isTouch) this._initTouch();
    }

    _initTouch() {
        const joyArea = document.getElementById('joystickArea');
        const knob = document.getElementById('joystickKnob');
        const shootBtn = document.getElementById('shootBtn');
        const jumpBtn = document.getElementById('jumpBtn');
        const proneBtn = document.getElementById('proneBtn');
        const canvas = document.getElementById('gameCanvas');
        if (!joyArea) return;

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
            for (const t of e.touches) if (t.identifier === this.joystickId) this._updateJoystick(t.clientX, t.clientY);
        }, { passive: false });
        const joyEnd = (e) => {
            for (const t of e.changedTouches) {
                if (t.identifier === this.joystickId) {
                    this.joystickActive = false; this.joystickId = null;
                    this.joystickVec = { x: 0, y: 0 };
                    if (knob) knob.style.transform = 'translate(-50%, -50%)';
                }
            }
        };
        joyArea.addEventListener('touchend', joyEnd, { passive: false });
        joyArea.addEventListener('touchcancel', joyEnd, { passive: false });

        const bindBtn = (el, down, up) => {
            if (!el) return;
            el.addEventListener('touchstart', (e) => { e.preventDefault(); down(); }, { passive: false });
            if (up) {
                el.addEventListener('touchend', (e) => { e.preventDefault(); up(); }, { passive: false });
                el.addEventListener('touchcancel', () => up(), { passive: false });
            }
            el.addEventListener('mousedown', down);
            if (up) el.addEventListener('mouseup', up);
        };
        bindBtn(shootBtn, () => { this.shootHeld = true; }, () => { this.shootHeld = false; });
        bindBtn(jumpBtn, () => { this.jumpRequested = true; });
        bindBtn(proneBtn, () => {
            this.proneToggle = !this.proneToggle;
            proneBtn.classList.toggle('active', this.proneToggle);
        });

        canvas.addEventListener('touchstart', (e) => {
            this.dragLookActive = true;
            this.dragLookLastX = e.changedTouches[0].clientX;
            this.dragLookLastY = e.changedTouches[0].clientY;
        }, { passive: true });
        canvas.addEventListener('touchmove', (e) => {
            if (!this.dragLookActive) return;
            const t = e.touches[0];
            const dx = t.clientX - this.dragLookLastX;
            const dy = t.clientY - this.dragLookLastY;
            this.yaw -= dx * this.sensitivity * 2.2;
            this.pitch -= dy * this.sensitivity * 2.2;
            this.pitch = Utils.clamp(this.pitch, CONFIG.camera.pitchMin, CONFIG.camera.pitchMax);
            this.dragLookLastX = t.clientX;
            this.dragLookLastY = t.clientY;
        }, { passive: true });
        canvas.addEventListener('touchend', () => { this.dragLookActive = false; }, { passive: true });
    }

    _updateJoystick(x, y) {
        const dx = x - this.joystickCenter.x;
        const dy = y - this.joystickCenter.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        const maxDist = 42;
        const factor = Math.min(dist / maxDist, 1);
        const angle = Math.atan2(dy, dx);
        this.joystickVec.x = Math.cos(angle) * factor;
        this.joystickVec.y = Math.sin(angle) * factor;
        const knob = document.getElementById('joystickKnob');
        if (knob) knob.style.transform = `translate(calc(-50% + ${dx * 0.5}px), calc(-50% + ${dy * 0.5}px))`;
    }

    getMoveVector() {
        let x = 0, z = 0;
        if (this.keys['KeyW'] || this.keys['ArrowUp']) z -= 1;
        if (this.keys['KeyS'] || this.keys['ArrowDown']) z += 1;
        if (this.keys['KeyA'] || this.keys['ArrowLeft']) x -= 1;
        if (this.keys['KeyD'] || this.keys['ArrowRight']) x += 1;
        if (this.joystickActive) { x += this.joystickVec.x; z += this.joystickVec.y; }
        const len = Math.sqrt(x * x + z * z);
        if (len > 1) { x /= len; z /= len; }
        return { x, z, magnitude: Math.min(len, 1) };
    }

    isRunning() { return !!(this.keys['ShiftLeft'] || this.keys['ShiftRight']); }
    isShooting() { return this.mouseDown || this.shootHeld; }
    isAiming() { return this.rightDown; }
    isProne() { return !!(this.keys['KeyC'] || this.keys['ControlLeft'] || this.keys['ControlRight'] || this.proneToggle); }
    consumeJump() { const r = this.jumpRequested; this.jumpRequested = false; return r; }
}
