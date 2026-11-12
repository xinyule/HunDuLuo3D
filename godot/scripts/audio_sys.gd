extends Node

## 合成音效/BGM 播放（素材为程序合成的 WAV，无外部版权素材）
## 用法：AudioSys.play("shoot") / AudioSys.start_bgm()

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _muted := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in ["shoot", "shoot_m", "enemy_shoot", "explosion", "jump", "hurt", "pickup", "gate", "die", "clear", "bgm"]:
		var p := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(p):
			_streams[n] = load(p)
	for i in 14:
		var pl := AudioStreamPlayer.new()
		pl.bus = "Master"
		add_child(pl)
		_pool.append(pl)
	_bgm = AudioStreamPlayer.new()
	add_child(_bgm)
	if _streams.has("bgm"):
		var s: AudioStreamWAV = _streams["bgm"]
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.get_data().size() / 2  # 16-bit 单声道帧数近似
		_bgm.stream = s
		_bgm.volume_db = -9.0

func play(stream_name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if _muted or not _streams.has(stream_name):
		return
	for pl in _pool:
		if not pl.playing:
			pl.stream = _streams[stream_name]
			pl.volume_db = vol_db
			pl.pitch_scale = pitch * randf_range(0.96, 1.04)
			pl.play()
			return

func start_bgm() -> void:
	if _muted:
		return
	if _bgm.stream and not _bgm.playing:
		_bgm.play()

func stop_bgm() -> void:
	if _bgm.playing:
		_bgm.stop()

func toggle_mute() -> bool:
	_muted = not _muted
	AudioServer.set_bus_mute(0, _muted)
	return _muted
