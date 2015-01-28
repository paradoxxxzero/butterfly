# ƸӜƷ butterfly

![](http://paradoxxxzero.github.io/assets/butterfly_1.gif)


## Description

Butterfly is a tornado web server written in python which powers a full featured web terminal.

The js part is heavily based on [term.js](https://github.com/chjj/term.js/) which is heavily based on [jslinux](http://bellard.org/jslinux/).


## Try it

```bash
    $ pip install butterfly
    $ butterfly.server.py
```

Then open [localhost:57575](http://localhost:57575) in your favorite browser and done.

## Run it with systemd (linux)

Systemd provides a way to automatically activate daemons when needed (socket activation):

```bash
    $ cd /etc/systemd/system
    # curl -O https://raw.githubusercontent.com/paradoxxxzero/butterfly/master/butterfly.service
    # curl -O https://raw.githubusercontent.com/paradoxxxzero/butterfly/master/butterfly.socket
    # systemctl enable butterfly.socket
    # systemctl start butterfly.socket
```

## Contribute

and make the world better (or just butterfly).

Don't hesitate to fork the repository and start hacking on it, I am very open to pull requests.

If you don't know what to do go to the github issues and pick one you like.

If you want to motivate me to continue working on this project you can tip me, see: http://paradoxxxzero.github.io/about/

The dev requirements are coffee script and compass for the client side.
Run `python dev.py --debug --port=12345` and you are set (yes you can launch it from your regular butterfly instance)

## Author

[Florian Mounier](http://paradoxxxzero.github.io/)


## License

```
    butterfly Copyright (C) 2014  Florian Mounier

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
```

## Docker Usage
There is a docker repository created for this project that is set to automatically rebuild when there is a push
into this repository: https://registry.hub.docker.com/u/garland/butterfly/

### Starting

        docker run \
        --env PASSWORD=password \
        --env PORT=57575 \
        -p 57575:57575 \
        -d garland/butterfly

