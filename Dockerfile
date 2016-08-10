from python:3.5-onbuild

run python setup.py build
run python setup.py install

expose 57575

cmd ["/usr/src/app/docker/run.sh"]
