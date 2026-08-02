extends Node2D

var serial: GdSerial

func _ready() -> void:
	serial = GdSerial.new()
	
	# 利用可能なポート一覧を取得
	var ports = serial.list_ports()
	print("Available ports: ", ports)
	
	# ポートとボーレートを設定(環境に合わせて変更)
	serial.set_port("/dev/tty.usbserial-57710034421") # ポートは仮置き
	serial.set_baud_rate(115200)
	
	# ポートを開いて送受信テスト
	if serial.open():
		print("Port opened successfully")
		
		var response = serial.readline()
		print("Response: ", response)
		
		serial.close()
	else:
		print("Failed to open port")
