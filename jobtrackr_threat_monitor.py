import socket
import time
from datetime import datetime


SERVICES = [
	{"owner": "Dhaya", "name": "Frontend", "ip": "10.67.151.133", "port": 7012},
	{"owner": "Bhavna", "name": "Rabbitmq AMQP", "ip": "10.67.151.114", "port": 5672},
	{"owner": "Bhavna", "name": "Rabbitq Dashboard", "ip": "10.67.151.114", "port": 15672},
	{"owner": "Ravi", "name": "MySQL Database", "ip": "10.67.151.166", "port": 3306},
	{"owner": "Rishu", "name": "Backend", "ip": "10.67.151.212", "port": 5000},
]

LOG_FILE = "/home/bhavnasahai3/Capstone-Group-01/jobtrackr_threat_monitor.log"

def log_event(level, message):
	timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
	line = f"[{timestamp}] [{level}] {message}"
	print(line)

	with open(LOG_FILE, "a") as file:
		file.write(line + "\n")

def check_service(service):
	try:
		connection = socket.create_connection((service["ip"], service["port"]), timeout=3)
		connection.close()
		log_event("OK", f"{service['owner']} - {service['name']} reachable at {service['ip']}:{service['port']}")
	except:
		log_event("ALERT", f"{service['owner']} - {service['name']} DOWN/BLOCKED at {service['ip']}:{service['port']}")



def monitor():
	log_event("INFO", "Jobtrackr automated threat monitor started")	
	

	while True:
		for service in SERVICES:
			check_service(service)

		log_event("INFO", "Full system scan complete")
		time.sleep(10)

if __name__ == "__main__":
	monitor()
