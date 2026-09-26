extends Node
## Small, bounded UI voice pool. Loading goes through PaxMod (no import required).

const HOVER_INTERVAL_MS: int = 100
const CLICK_INTERVAL_MS: int = 32
const CROSSFADE_SECONDS: float = 0.010
const SILENCE_DB: float = -80.0
const HOVER_GAIN: float = 0.52

var sound_enabled: bool = true
var volume: float = 0.35

var _hover_stream: AudioStream
var _click_stream: AudioStream
var _players: Array[AudioStreamPlayer] = []
var _fades: Array[Tween] = []
var _voice_gains: Array[float] = [1.0, 1.0]
var _active_slot: int = -1
var _last_hover_ms: int = -1000
var _last_click_ms: int = -1000
var _click_until_ms: int = 0


func setup(mod: PaxMod) -> void:
	stop_all()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hover_stream = mod.sound("sounds/hover.wav")
	_click_stream = mod.sound("sounds/click.wav")
	if _players.is_empty():
		for index: int in range(2):
			var player: AudioStreamPlayer = AudioStreamPlayer.new()
			player.name = "InterfaceVoice%d" % index
			player.max_polyphony = 1
			player.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(player)
			_players.append(player)
			_fades.append(null)


func configure(settings: Dictionary) -> void:
	sound_enabled = bool(settings.get("sound_enabled", true))
	var requested_volume: float = float(settings.get("volume", settings.get("sound_volume", 0.35)))
	volume = clampf(requested_volume, 0.0, 1.0) if is_finite(requested_volume) else 0.35
	if not sound_enabled or volume <= 0.0:
		stop_all()
		return
	for index: int in range(_players.size()):
		# A fading tail must keep fading; changing the slider must not revive it.
		if _players[index].playing and (_fades[index] == null or not _fades[index].is_running()):
			_players[index].volume_db = linear_to_db(volume * _voice_gains[index])


func hover(button: BaseButton = null) -> void:
	if not _can_play(button) or _hover_stream == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_hover_ms < HOVER_INTERVAL_MS or now_ms < _click_until_ms:
		return
	_last_hover_ms = now_ms
	_play(_hover_stream, HOVER_GAIN)


func click(button: BaseButton = null) -> void:
	if not _can_play(button) or _click_stream == null:
		return
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_click_ms < CLICK_INTERVAL_MS:
		return
	_last_click_ms = now_ms
	_click_until_ms = now_ms + int(ceil(_click_stream.get_length() * 1000.0))
	_play(_click_stream, 1.0)


func preview() -> void:
	click()


func stop_all() -> void:
	for index: int in range(_players.size()):
		_kill_fade(index)
		if is_instance_valid(_players[index]):
			_players[index].stop()
	_active_slot = -1
	_last_hover_ms = -1000
	_last_click_ms = -1000
	_click_until_ms = 0


func _can_play(button: BaseButton) -> bool:
	if not sound_enabled or volume <= 0.0 or _players.size() != 2 or not is_inside_tree():
		return false
	if button == null:
		return true
	if not is_instance_valid(button):
		return false
	return not button.disabled and button.is_visible_in_tree() and button.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _play(stream: AudioStream, gain: float) -> void:
	# Swap between two voices. Only a 10 ms release may overlap the new attack;
	# a rapid click interrupts the hover without queueing input or audio commands.
	var next_slot: int = 0 if _active_slot != 0 else 1
	_kill_fade(next_slot)
	var next_player: AudioStreamPlayer = _players[next_slot]
	next_player.stop()
	if _active_slot >= 0:
		_fade_out(_active_slot)
	_voice_gains[next_slot] = gain
	next_player.stream = stream
	next_player.volume_db = linear_to_db(volume * gain)
	next_player.play()
	_active_slot = next_slot


func _fade_out(index: int) -> void:
	_kill_fade(index)
	var player: AudioStreamPlayer = _players[index]
	if not player.playing:
		return
	var fade: Tween = create_tween()
	_fades[index] = fade
	fade.tween_property(player, "volume_db", SILENCE_DB, CROSSFADE_SECONDS)
	fade.tween_callback(player.stop)


func _kill_fade(index: int) -> void:
	if _fades[index] != null and _fades[index].is_valid():
		_fades[index].kill()
	_fades[index] = null


func _exit_tree() -> void:
	stop_all()
