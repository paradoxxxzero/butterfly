FROM ubuntu:14.04.4

RUN apt-get update -y
RUN apt-get install -y python-setuptools python-dev build-essential libffi-dev libssl-dev

WORKDIR /opt
ADD . /opt/app
WORKDIR /opt/app

RUN python setup.py build
RUN python setup.py install

ADD docker/run.sh /opt/run.sh

EXPOSE 57575

ENTRYPOINT ["/opt/run.sh"]
