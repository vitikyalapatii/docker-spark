# Makefile for Splunk Spark Docker image

# Security Scanner Variables
SCANNER_DATE := `date +%Y-%m-%d`
SCANNER_DATE_YEST := `TZ=GMT+24 +%Y:%m:%d`
SCANNER_VERSION := v8
SCANNER_LOCALIP := $(shell ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | awk '{print $1}' | head -n 1)
ifeq ($(shell uname), Linux)
	SCANNER_FILE = clair-scanner_linux_amd64
else ifeq ($(shell uname), Darwin)
	SCANNER_FILE = clair-scanner_darwin_amd64
else
	SCANNER_FILE = clair-scanner_windows_amd64.exe
endif

all:
	@echo Building splunk-spark image
	@docker build -t splunk/spark .

stop_clair_scanner:
	@docker stop clair_db || true
	@docker rm clair_db || true
	@docker stop clair || true
	@docker rm clair || true

setup_clair_scanner: stop_clair_scanner
	@mkdir -p clair-scanner-logs
	@docker pull arminc/clair-db:${SCANNER_DATE} || docker pull arminc/clair-db:${SCANNER_DATE_YEST} || echo "WARNING: Failed to pull daily image, defaulting to latest" >> clair-scanner-logs/clair_setup_errors.log ; docker pull arminc/clair-db:latest
	@docker run -d --name clair_db arminc/clair-db:${SCANNER_DATE} || docker run -d --name clair_db arminc/clair-db:${SCANNER_DATE_YEST} || docker run -d --name clair_db arminc/clair-db:latest
	@docker run -p 6060:6060 --link clair_db:postgres -d --name clair --restart on-failure arminc/clair-local-scan:v2.0.6
	@wget https://github.com/arminc/clair-scanner/releases/download/${SCANNER_VERSION}/${SCANNER_FILE}
	@mv ${SCANNER_FILE} clair-scanner
	@chmod +x clair-scanner
	@echo "Waiting for clair daemon to start"
	@retries=0 ; while( ! wget -T 10 -q -O /dev/null http://0.0.0.0:6060/v1/namespaces ) ; do sleep 1 ; echo -n "." ; if [ $$retries -eq 10 ] ; then echo " Timeout, aborting." ; exit 1 ; fi ; retries=$$(($$retries+1)) ; done
	@echo "Clair daemon started."

run_clair_scan:
	@./clair-scanner -c http://0.0.0.0:6060 --ip ${SCANNER_LOCALIP} -r clair-scanner-logs/results.json -l clair-scanner-logs/results.log splunk/spark
