IMG_NAME=gitlab-reporting

GITLAB_CLI=docker run -it --rm \
	-e GITLAB_PRIVATE_TOKEN=${GITLAB_API_PRIVATE_TOKEN} \
	-v $$(pwd):/src \
	 ${IMG_NAME}

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