/**
 * 工具函数 + 程序化音效（Web Audio，无外部音频文件）
 */
const Utils = {
    degToRad: (deg) => deg * Math.PI / 180,
    radToDeg: (rad) => rad * 180 / Math.PI,
    dist: (a, b) => Math.sqrt((a.x - b.x) ** 2 + (a.z - b.z) ** 2),
    dist2: (a, b) => (a.x - b.x) ** 2 + (a.z - b.z) ** 2,
    lerp: (a, b, t) => a + (b - a) * t,
    clamp: (v, min, max) => Math.max(min, Math.min(max, v)),
    randomRange: (min, max) => min + Math.random() * (max - min),
    randomInt: (min, max) => Math.floor(min + Math.random() * (max - min + 1)),
    randomPick: (arr) => arr[Math.floor(Math.random() * arr.length)],
    // 带种子的伪随机（关卡布局稳定，同关每次进图一致）
    seededRandom(seed) {
        let s = seed >>> 0;
        return () => {
            s = (s * 1664525 + 1013904223) >>> 0;
            return s / 4294967296;
        };
    },
    // 递归释放 three 对象（修旧版只 remove 不 dispose 的泄漏）
    disposeObject(root) {
        if (!root) return;
        root.traverse((o) => {
            if (o.geometry) o.geometry.dispose();
            if (o.material) {
                const mats = Array.isArray(o.material) ? o.material : [o.material];
                mats.forEach((m) => { if (m.map) m.map.dispose(); m.dispose(); });
            }
        });
    },
};

const AudioManager = {
    ctx: null,
    enabled: true,
    init() {
        if (this.ctx) { if (this.ctx.state === 'suspended') this.ctx.resume(); return; }
        try {
            this.ctx = new (window.AudioContext || window.webkitAudioContext)();
        } catch (e) { this.enabled = false; }
    },
    _tone(freq, dur, type, vol, slideTo, delay) {
        if (!this.enabled || !this.ctx) return;
        const t0 = this.ctx.currentTime + (delay || 0);
        const osc = this.ctx.createOscillator();
        const gain = this.ctx.createGain();
        osc.type = type || 'square';
        osc.frequency.setValueAtTime(freq, t0);
        if (slideTo) osc.frequency.exponentialRampToValueAtTime(Math.max(20, slideTo), t0 + dur);
        gain.gain.setValueAtTime(vol || 0.12, t0);
        gain.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
        osc.connect(gain).connect(this.ctx.destination);
        osc.start(t0);
        osc.stop(t0 + dur + 0.02);
    },
    shoot(kind) {
        if (kind === 'L') this._tone(880, 0.09, 'sawtooth', 0.10, 220);
        else if (kind === 'F') this._tone(160, 0.14, 'sawtooth', 0.13, 60);
        else if (kind === 'S') this._tone(300, 0.08, 'square', 0.12, 90);
        else this._tone(240, 0.07, 'square', 0.11, 80);
    },
    enemyShoot() { this._tone(180, 0.09, 'sawtooth', 0.07, 70); },
    hurt() { this._tone(150, 0.2, 'sawtooth', 0.18, 50); },
    jump() { this._tone(300, 0.12, 'sine', 0.08, 520); },
    enemyDie() { this._tone(320, 0.25, 'square', 0.10, 70); },
    explosion() {
        this._tone(90, 0.4, 'sawtooth', 0.22, 30);
        this._tone(55, 0.5, 'square', 0.16, 24, 0.03);
    },
    pickup() { [660, 880, 1320].forEach((f, i) => this._tone(f, 0.12, 'sine', 0.12, null, i * 0.07)); },
    gateOpen() { this._tone(120, 0.5, 'sawtooth', 0.14, 480); },
    bossWarn() { [98, 98, 98].forEach((f, i) => this._tone(f, 0.28, 'square', 0.16, 65, i * 0.32)); },
    levelComplete() { [523, 659, 784, 1046].forEach((f, i) => this._tone(f, 0.3, 'sine', 0.13, null, i * 0.13)); },
    gameOver() { [392, 330, 262, 196].forEach((f, i) => this._tone(f, 0.4, 'sawtooth', 0.11, null, i * 0.2)); },
};
