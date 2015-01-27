FROM ubuntu:14.04.1

RUN apt-get update -y
RUN apt-get install -y python-setuptools python-dev build-essential libffi-dev libssl-dev

WORKDIR /opt
ADD . /opt/app
WORKDIR /opt/app

RUN python setup.py build
RUN python setup.py install

ADD docker/run.sh /opt/run.sh
RUN chmod 777 /opt/run.sh

EXPOSE 57575

CMD ["/opt/run.sh"]