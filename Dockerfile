FROM python:alpine

RUN apk update ;\
    apk add --no-cache \
        bash \
        jq \
        ;\
    pip install --upgrade python-gitlab

COPY entrypoint-python-gitlab.sh /usr/local/bin/.

COPY src/ /usr/local/bin/

WORKDIR /src

ENTRYPOINT ["entrypoint-python-gitlab.sh"]
CMD ["gitlab --version"]
