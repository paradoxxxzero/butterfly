# ƸӜƷ butterfly 2.0

![](http://paradoxxxzero.github.io/assets/butterfly_2.0_1.gif)


## Description

Butterfly is a xterm compatible terminal that runs in your browser.


## Features

* xterm compatible (support a lot of unused features!)
* Native browser scroll and search
* Theming in css / sass [(18 preset themes)](https://github.com/paradoxxxzero/butterfly-themes) endless possibilities!
* HTML in your terminal! cat images and use &lt;table&gt;
* Multiple sessions support (à la screen -x) to simultaneously access a terminal from several places on the planet!
* Secure authentication with X509 certificates!
* 16,777,216 colors support!
* Keyboard text selection!
* Desktop notifications on terminal output!
* Geolocation from browser!
* May work on firefox too!

## Try it

``` bash
$ pip install butterfly
$ pip install libsass  # If you want to use themes
$ butterfly
```

A new tab should appear in your browser. Then type

``` bash
$ butterfly help
```

To get an overview of butterfly features.


## Run it as a server

``` bash
$ butterfly.server.py --host=myhost --port=57575
```

The first time it will ask you to generate the certificates (see: [here](http://paradoxxxzero.github.io/2014/03/21/butterfly-with-ssl-auth.html))


## Run it with systemd (linux)

Systemd provides a way to automatically activate daemons when needed (socket activation):

``` bash
$ cd /etc/systemd/system
$ curl -O https://raw.githubusercontent.com/paradoxxxzero/butterfly/master/butterfly.service
$ curl -O https://raw.githubusercontent.com/paradoxxxzero/butterfly/master/butterfly.socket
$ systemctl enable butterfly.socket
$ systemctl start butterfly.socket
```

Don't forget to update the /etc/butterfly/butterfly.conf file with your server options (host, port, shell, ...)

## Contribute

and make the world better (or just butterfly).

Don't hesitate to fork the repository and start hacking on it, I am very open to pull requests.

If you don't know what to do go to the github issues and pick one you like.

If you want to motivate me to continue working on this project you can tip me, see: http://paradoxxxzero.github.io/about/

Client side development use [grunt](http://gruntjs.com/) and [bower](http://bower.io/).

## Credits

The js part is based on [term.js](https://github.com/chjj/term.js/) which is based on [jslinux](http://bellard.org/jslinux/).
## Author

[Florian Mounier](http://paradoxxxzero.github.io/)

## License

```
butterfly Copyright (C) 2015  Florian Mounier

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

## Docker
There is a docker repository created for this project that is set to automatically rebuild when there is a push
into this repository: https://registry.hub.docker.com/u/garland/butterfly/

### Example usage

Starting with login and password

``` bash
docker run --env PASSWORD=password -d garland/butterfly --login
```

Starting with no password

``` bash
docker run -d -p 57575:57575 garland/butterfly
```

Starting with a different port

``` bash
docker run -d -p 12345:12345 garland/butterfly --port=12345
```
