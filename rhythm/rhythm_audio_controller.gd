class_name RhythmAudioController
extends Node

signal cue_played(beat: float, path: String, start_offset: float)
signal song_finished

@onready var base_music_player: AudioStreamPlayer = $BaseMusicPlayer
@onready var cue_players: Array[AudioStreamPlayer] = [
	$CuePlayerA,
	$CuePlayerB,
]

# headless testではAudioStreamPlayerを動かさず、simulated_song_timeを使う。
@export var playback_enabled: bool = true

var chart: RhythmChart
var timing: RhythmTiming
var cue_streams: Dictionary = {}
var next_cue_index: int = 0
var next_cue_player_index: int = 0
var simulated_song_time: float = 0.0
var running: bool = false
var finish_emitted: bool = false
var configured: bool = false


func _ready() -> void:
	set_process(false)
	base_music_player.finished.connect(finish_song)


func configure(new_chart: RhythmChart) -> bool:
	stop()
	configured = false
	chart = new_chart
	if chart == null:
		return false

	timing = RhythmTiming.new(chart.tempo_changes, chart.offset)
	cue_streams.clear()

	if playback_enabled:
		var base_stream := load(chart.audio_path) as AudioStream
		if base_stream == null:
			push_error("OffVocalを読み込めません: %s" % chart.audio_path)
			return false
		base_music_player.stream = base_stream

		for cue: Dictionary in chart.cues:
			var path: String = cue["path"]
			if cue_streams.has(path):
				continue
			var stream := load(path) as AudioStream
			if stream == null:
				push_error("掛け声音源を読み込めません: %s" % path)
				return false
			cue_streams[path] = stream

	reset_cue_index(0.0)
	configured = true
	return true


func start(from_seconds: float = 0.0) -> void:
	if chart == null:
		return

	stop_players()
	simulated_song_time = maxf(0.0, from_seconds)
	reset_cue_index(simulated_song_time)
	running = true
	finish_emitted = false
	set_process(true)

	if playback_enabled and base_music_player.stream != null:
		base_music_player.play(simulated_song_time)


func seek(song_time: float) -> void:
	start(song_time)


func stop() -> void:
	running = false
	set_process(false)
	stop_players()


func _process(_delta: float) -> void:
	if not running:
		return

	var song_time := get_song_time()
	advance(song_time)

	if (
		not playback_enabled
		and song_time >= timing.beat_to_seconds(chart.end_beat)
	):
		finish_song()


# OffVocalを全画面共通の唯一の曲時計として使う。
func get_song_time() -> float:
	if not playback_enabled or not base_music_player.playing:
		return simulated_song_time

	return maxf(
		0.0,
		base_music_player.get_playback_position()
		+ AudioServer.get_time_since_last_mix()
		- AudioServer.get_output_latency()
	)


# テストやシーク復元では明示時刻を渡し、同じCue処理を利用する。
func set_simulated_song_time(song_time: float) -> void:
	simulated_song_time = maxf(0.0, song_time)
	if running:
		advance(simulated_song_time)


func advance(song_time: float) -> void:
	if chart == null:
		return
	simulated_song_time = song_time

	while next_cue_index < chart.cues.size():
		var cue: Dictionary = chart.cues[next_cue_index]
		var cue_time := timing.beat_to_seconds(float(cue["beat"]))
		if song_time < cue_time:
			break

		play_cue(cue, maxf(0.0, song_time - cue_time))
		next_cue_index += 1


func play_cue(cue: Dictionary, start_offset: float) -> void:
	var path: String = cue["path"]
	if playback_enabled and cue_streams.has(path):
		var stream: AudioStream = cue_streams[path]
		# フレーム遅延が音源尺を超えたCueは過去イベントとして読み飛ばす。
		if start_offset < stream.get_length():
			var player := cue_players[next_cue_player_index]
			next_cue_player_index = (
				(next_cue_player_index + 1) % cue_players.size()
			)
			player.stop()
			player.stream = stream
			player.play(start_offset)

	cue_played.emit(float(cue["beat"]), path, start_offset)


func reset_cue_index(song_time: float) -> void:
	next_cue_index = 0
	if chart == null or timing == null:
		return

	while next_cue_index < chart.cues.size():
		var cue_beat: float = chart.cues[next_cue_index]["beat"]
		var cue_time := timing.beat_to_seconds(cue_beat)
		if cue_time >= song_time:
			break
		next_cue_index += 1


func finish_song() -> void:
	if finish_emitted:
		return
	finish_emitted = true
	running = false
	set_process(false)
	stop_players()
	song_finished.emit()


func stop_players() -> void:
	if is_instance_valid(base_music_player):
		base_music_player.stop()
	for player: AudioStreamPlayer in cue_players:
		if is_instance_valid(player):
			player.stop()


func _exit_tree() -> void:
	stop_players()
