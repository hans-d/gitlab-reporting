IMG_NAME=gitlab-reporting

GITLAB_CLI=docker run -it --rm \
	-e GITLAB_PRIVATE_TOKEN=${GITLAB_API_PRIVATE_TOKEN} \
	-v $$(pwd):/src \
	${EXTRA_ARGS} \
	${IMG_NAME}

ifeq ($(ENV),dev)
	EXTRA_ARGS = \
		-v $$(pwd)/src/collect.sh:/usr/local/bin/collect.sh \
		-v $$(pwd)/src/report-access.sh:/usr/local/bin/report-access.sh
endif

default:

build:
	docker build -t ${IMG_NAME} .

collect:
	@echo "make sure to provide your root ids via `GITLAB_ROOT_IDS`"
	${GITLAB_CLI} collect.sh ${GITLAB_ROOT_IDS}


report:
	${GITLAB_CLI} report-access.sh

gitlab:
	${GITLAB_CLI} gitlab ${CMD}