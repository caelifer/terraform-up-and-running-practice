CLUSTER_NAME := test1
SOURCE := main.tf

${CLUSTER_NAME}.plan:${SOURCE}
	terraform plan -var http_server_port=HTTP_SERVER_PORT -o $@
	
