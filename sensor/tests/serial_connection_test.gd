extends Node

@export var port_name: String = ""
@export var baud_rate: int = 115200

var serial: GdSerial

func _ready() -> void:
	run_connection_test()

func run_connection_test() -> void:
	serial = GdSerial.new()
	
	# 利用可能なポート一覧を取得
	var ports = serial.list_ports()
	print("Available ports: ", ports)
	
	# ポートとボーレートを設定(環境に合わせて変更)
	serial.set_port(port_name)
	serial.set_baud_rate(baud_rate)
	
	if not serial.open():
		push_error("Failed to open port")
		return
	
	# ポートを開いて送受信テスト
	print("Port opened successfully")
		
	var response = serial.readline()
	print("Response: ", response)
		
	serial.close()
