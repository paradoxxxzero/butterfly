(function() {
  var $, State, Terminal, cancel, cols, open_ts, quit, rows, s,
    __slice = [].slice,
    __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  cols = rows = null;

  quit = false;

  open_ts = (new Date()).getTime();

  $ = document.querySelectorAll.bind(document);

  document.addEventListener('DOMContentLoaded', function() {
    var bench, cbench, ctl, send, term, ws, ws_url;
    send = function(data) {
      return ws.send('S' + data);
    };
    ctl = function() {
      var args, params, type;
      type = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      params = args.join(',');
      if (type === 'Resize') {
        return ws.send('R' + params);
      }
    };
    if (location.protocol === 'https:') {
      ws_url = 'wss://';
    } else {
      ws_url = 'ws://';
    }
    ws_url += document.location.host + '/ws' + location.pathname;
    ws = new WebSocket(ws_url);
    ws.addEventListener('open', function() {
      console.log("WebSocket open", arguments);
      ws.send('R' + term.cols + ',' + term.rows);
      return open_ts = (new Date()).getTime();
    });
    ws.addEventListener('error', function() {
      return console.log("WebSocket error", arguments);
    });
    ws.addEventListener('message', function(e) {
      return setTimeout(function() {
        return term.write(e.data);
      }, 1);
    });
    ws.addEventListener('close', function() {
      console.log("WebSocket closed", arguments);
      setTimeout(function() {
        term.write('Closed');
        term.skipNextKey = true;
        return term.element.classList.add('dead');
      }, 1);
      quit = true;
      if ((new Date()).getTime() - open_ts > 60 * 1000) {
        return open('', '_self').close();
      }
    });
    term = new Terminal($('#wrapper')[0], send, ctl);
    addEventListener('beforeunload', function() {
      if (!quit) {
        return 'This will exit the terminal session';
      }
    });
    bench = function(n) {
      var rnd, t0;
      if (n == null) {
        n = 100000000;
      }
      rnd = '';
      while (rnd.length < n) {
        rnd += Math.random().toString(36).substring(2);
      }
      t0 = (new Date()).getTime();
      term.write(rnd);
      return console.log("" + n + " chars in " + ((new Date()).getTime() - t0) + " ms");
    };
    cbench = function(n) {
      var rnd, t0;
      if (n == null) {
        n = 100000000;
      }
      rnd = '';
      while (rnd.length < n) {
        rnd += "\x1b[" + (30 + parseInt(Math.random() * 20)) + "m";
        rnd += Math.random().toString(36).substring(2);
      }
      t0 = (new Date()).getTime();
      term.write(rnd);
      return console.log("" + n + " chars + colors in " + ((new Date()).getTime() - t0) + " ms");
    };
    term.ws = ws;
    return window.butterfly = term;
  });

  cancel = function(ev) {
    if (ev.preventDefault) {
      ev.preventDefault();
    }
    if (ev.stopPropagation) {
      ev.stopPropagation();
    }
    ev.cancelBubble = true;
    return false;
  };

  s = 0;

  State = {
    normal: s++,
    escaped: s++,
    csi: s++,
    osc: s++,
    charset: s++,
    dcs: s++,
    ignore: s++
  };

  Terminal = (function() {
    function Terminal(parent, out, ctl) {
      var div, i, term_size;
      this.parent = parent;
      this.out = out;
      this.ctl = ctl != null ? ctl : function() {};
      this.context = this.parent.ownerDocument.defaultView;
      this.document = this.parent.ownerDocument;
      this.body = this.document.getElementsByTagName('body')[0];
      this.element = this.document.createElement('div');
      this.element.className = 'terminal focus';
      this.element.style.outline = 'none';
      this.element.setAttribute('tabindex', 0);
      this.element.setAttribute('spellcheck', 'false');
      this.parent.appendChild(this.element);
      div = this.document.createElement('div');
      div.className = 'line';
      this.element.appendChild(div);
      this.children = [div];
      this.compute_char_size();
      div.style.height = this.char_size.height + 'px';
      term_size = this.parent.getBoundingClientRect();
      this.cols = Math.floor(term_size.width / this.char_size.width);
      this.rows = Math.floor(term_size.height / this.char_size.height);
      i = this.rows - 1;
      while (i--) {
        div = this.document.createElement('div');
        div.style.height = this.char_size.height + 'px';
        div.className = 'line';
        this.element.appendChild(div);
        this.children.push(div);
      }
      this.scrollback = 100000;
      this.visualBell = 100;
      this.convertEol = false;
      this.termName = 'xterm';
      this.cursorBlink = true;
      this.cursorState = 0;
      this.last_cc = 0;
      this.reset_vars();
      this.refresh(0, this.rows - 1);
      this.focus();
      this.startBlink();
      addEventListener('keydown', this.keyDown.bind(this));
      addEventListener('keypress', this.keyPress.bind(this));
      addEventListener('focus', this.focus.bind(this));
      addEventListener('blur', this.blur.bind(this));
      addEventListener('resize', this.resize.bind(this));
      if (typeof InstallTrigger !== "undefined") {
        this.element.contentEditable = 'true';
        this.element.addEventListener("mouseup", function() {
          var sel;
          sel = getSelection().getRangeAt(0);
          if (sel.startOffset === sel.endOffset) {
            return getSelection().removeAllRanges();
          }
        });
      }
      this.initmouse();
      setTimeout(this.resize.bind(this), 100);
    }

    Terminal.prototype.reset_vars = function() {
      var i;
      this.ybase = 0;
      this.ydisp = 0;
      this.x = 0;
      this.y = 0;
      this.cursorHidden = false;
      this.state = State.normal;
      this.queue = '';
      this.scrollTop = 0;
      this.scrollBottom = this.rows - 1;
      this.applicationKeypad = false;
      this.applicationCursor = false;
      this.originMode = false;
      this.wraparoundMode = false;
      this.normal = null;
      this.charset = null;
      this.gcharset = null;
      this.glevel = 0;
      this.charsets = [null];
      this.defAttr = (0 << 18) | (257 << 9) | (256 << 0);
      this.curAttr = this.defAttr;
      this.params = [];
      this.currentParam = 0;
      this.prefix = "";
      this.lines = [];
      i = this.rows;
      while (i--) {
        this.lines.push(this.blankLine());
      }
      this.setupStops();
      return this.skipNextKey = null;
    };

    Terminal.prototype.compute_char_size = function() {
      var test_span;
      test_span = document.createElement('span');
      test_span.textContent = '0123456789';
      this.children[0].appendChild(test_span);
      this.char_size = {
        width: test_span.getBoundingClientRect().width / 10,
        height: this.children[0].getBoundingClientRect().height
      };
      return this.children[0].removeChild(test_span);
    };

    Terminal.prototype.eraseAttr = function() {
      return (this.defAttr & ~0x1ff) | (this.curAttr & 0x1ff);
    };

    Terminal.prototype.focus = function() {
      if (this.sendFocus) {
        this.send('\x1b[I');
      }
      this.showCursor();
      this.element.classList.add('focus');
      return this.element.classList.remove('blur');
    };

    Terminal.prototype.blur = function() {
      this.cursorState = 1;
      this.refresh(this.y, this.y);
      if (this.sendFocus) {
        this.send('\x1b[O');
      }
      this.element.classList.add('blur');
      return this.element.classList.remove('focus');
    };

    Terminal.prototype.initmouse = function() {
      var encode, getButton, getCoords, pressed, sendButton, sendEvent, sendMove;
      pressed = 32;
      sendButton = function(ev) {
        var button, pos;
        button = getButton(ev);
        pos = getCoords(ev);
        if (!pos) {
          return;
        }
        sendEvent(button, pos);
        switch (ev.type) {
          case "mousedown":
            return pressed = button;
          case "mouseup":
            return pressed = 32;
        }
      };
      sendMove = function(ev) {
        var button, pos;
        button = pressed;
        pos = getCoords(ev);
        if (!pos) {
          return;
        }
        button += 32;
        return sendEvent(button, pos);
      };
      encode = (function(_this) {
        return function(data, ch) {
          if (!_this.utfMouse) {
            if (ch === 255) {
              return data.push(0);
            }
            if (ch > 127) {
              ch = 127;
            }
            return data.push(ch);
          } else {
            if (ch === 2047) {
              return data.push(0);
            }
            if (ch < 127) {
              return data.push(ch);
            } else {
              if (ch > 2047) {
                ch = 2047;
              }
              data.push(0xC0 | (ch >> 6));
              return data.push(0x80 | (ch & 0x3F));
            }
          }
        };
      })(this);
      sendEvent = (function(_this) {
        return function(button, pos) {
          var data;
          if (_this.urxvtMouse) {
            pos.x -= 32;
            pos.y -= 32;
            pos.x++;
            pos.y++;
            _this.send("\x1b[" + button + ";" + pos.x + ";" + pos.y + "M");
            return;
          }
          if (_this.sgrMouse) {
            pos.x -= 32;
            pos.y -= 32;
            _this.send("\x1b[<" + ((button & 3) === 3 ? button & ~3 : button) + ";" + pos.x + ";" + pos.y + ((button & 3) === 3 ? "m" : "M"));
            return;
          }
          data = [];
          encode(data, button);
          encode(data, pos.x);
          encode(data, pos.y);
          return _this.send("\x1b[M" + String.fromCharCode.apply(String, data));
        };
      })(this);
      getButton = (function(_this) {
        return function(ev) {
          var button, ctrl, meta, mod, shift;
          switch (ev.type) {
            case "mousedown":
              button = ev.button != null ? +ev.button : (ev.which != null ? ev.which - 1 : null);
              break;
            case "mouseup":
              button = 3;
              break;
            case "wheel":
              button = ev.deltaY < 0 ? 64 : 65;
          }
          shift = ev.shiftKey ? 4 : 0;
          meta = ev.metaKey ? 8 : 0;
          ctrl = ev.ctrlKey ? 16 : 0;
          mod = shift | meta | ctrl;
          if (_this.vt200Mouse) {
            mod &= ctrl;
          } else {
            if (!_this.normalMouse) {
              mod = 0;
            }
          }
          return (32 + (mod << 2)) + button;
        };
      })(this);
      getCoords = (function(_this) {
        return function(ev) {
          var el, h, w, x, y;
          x = ev.pageX;
          y = ev.pageY;
          el = _this.element;
          while (el && el !== _this.document.documentElement) {
            x -= el.offsetLeft;
            y -= el.offsetTop;
            el = "offsetParent" in el ? el.offsetParent : el.parentNode;
          }
          w = _this.element.clientWidth;
          h = _this.element.clientHeight;
          x = Math.ceil((x / w) * _this.cols);
          y = Math.ceil((y / h) * _this.rows);
          if (x < 0) {
            x = 0;
          }
          if (x > _this.cols) {
            x = _this.cols;
          }
          if (y < 0) {
            y = 0;
          }
          if (y > _this.rows) {
            y = _this.rows;
          }
          x += 32;
          y += 32;
          return {
            x: x,
            y: y,
            type: ev.type
          };
        };
      })(this);
      addEventListener("mousedown", (function(_this) {
        return function(ev) {
          var sm, up;
          if (!_this.mouseEvents) {
            return;
          }
          sendButton(ev);
          if (_this.vt200Mouse) {
            sendButton({
              __proto__: ev,
              type: "mouseup"
            });
            return cancel(ev);
          }
          sm = sendMove.bind(_this);
          if (_this.normalMouse) {
            addEventListener("mousemove", sm);
          }
          if (!_this.x10Mouse) {
            addEventListener("mouseup", up = function(ev) {
              sendButton(ev);
              if (_this.normalMouse) {
                removeEventListener("mousemove", sm);
              }
              removeEventListener("mouseup", up);
              return cancel(ev);
            });
          }
          return cancel(ev);
        };
      })(this));
      return addEventListener("wheel", (function(_this) {
        return function(ev) {
          if (_this.mouseEvents) {
            if (_this.x10Mouse) {
              return;
            }
            sendButton(ev);
          } else {
            if (_this.applicationKeypad) {
              return;
            }
            _this.scrollDisp(ev.deltaY > 0 ? 5 : -5);
          }
          return cancel(ev);
        };
      })(this));
    };

    Terminal.prototype.refresh = function(start, end) {
      var attr, bg, ch, classes, data, fg, flags, i, line, out, parent, row, width, x, y;
      if (end - start >= this.rows / 3) {
        parent = this.element.parentNode;
        if (parent != null) {
          parent.removeChild(this.element);
        }
      }
      width = this.cols + 1;
      y = start;
      if (end >= this.lines.length) {
        end = this.lines.length - 1;
      }
      while (y <= end) {
        row = y + this.ydisp;
        line = this.lines[row];
        out = "";
        if (y === this.y && (this.ydisp === this.ybase || this.selectMode) && !this.cursorHidden) {
          x = this.x;
        } else {
          x = -Infinity;
        }
        attr = this.defAttr;
        i = 0;
        while (i < line.length) {
          data = line[i][0];
          ch = line[i][1];
          if (data !== attr) {
            if (attr !== this.defAttr) {
              out += "</span>";
            }
            if (data !== this.defAttr) {
              classes = [];
              out += "<span ";
              bg = data & 0x1ff;
              fg = (data >> 9) & 0x1ff;
              flags = data >> 18;
              if (flags & 1) {
                classes.push("bold");
              }
              if (flags & 2) {
                classes.push("underline");
              }
              if (flags & 4) {
                classes.push("blink");
              }
              if (flags & 8) {
                classes.push("reverse-video");
              }
              if (flags & 16) {
                classes.push("invisible");
              }
              if (flags & 1 && fg < 8) {
                fg += 8;
              }
              classes.push("bg-color-" + bg);
              classes.push("fg-color-" + fg);
              out += "class=\"";
              out += classes.join(" ");
              out += "\">";
            }
          }
          if (i === x) {
            out += "<span class=\"" + (this.cursorState ? "reverse-video " : "") + "cursor\">";
          }
          if (ch.length > 1) {
            out += ch;
          } else {
            switch (ch) {
              case "&":
                out += "&amp;";
                break;
              case "<":
                out += "&lt;";
                break;
              case ">":
                out += "&gt;";
                break;
              default:
                if (ch === " ") {
                  out += '<span class="nbsp">\u2007</span>';
                } else if (ch <= " ") {
                  out += "&nbsp;";
                } else {
                  if (("\uff00" < ch && ch < "\uffef")) {
                    i++;
                  }
                  out += ch;
                }
            }
          }
          if (i === x) {
            out += "</span>";
          }
          attr = data;
          i++;
        }
        if (attr !== this.defAttr) {
          out += "</span>";
        }
        this.children[y].innerHTML = out;
        y++;
      }
      return parent != null ? parent.appendChild(this.element) : void 0;
    };

    Terminal.prototype._cursorBlink = function() {
      var cursor;
      this.cursorState ^= 1;
      cursor = this.element.querySelector(".cursor");
      if (!cursor) {
        return;
      }
      if (cursor.classList.contains("reverse-video")) {
        return cursor.classList.remove("reverse-video");
      } else {
        return cursor.classList.add("reverse-video");
      }
    };

    Terminal.prototype.showCursor = function() {
      if (!this.cursorState) {
        this.cursorState = 1;
        return this.refresh(this.y, this.y);
      }
    };

    Terminal.prototype.startBlink = function() {
      if (!this.cursorBlink) {
        return;
      }
      this._blinker = (function(_this) {
        return function() {
          return _this._cursorBlink();
        };
      })(this);
      return this.t_blink = setInterval(this._blinker, 500);
    };

    Terminal.prototype.refreshBlink = function() {
      if (!this.cursorBlink) {
        return;
      }
      clearInterval(this.t_blink);
      return this.t_blink = setInterval(this._blinker, 500);
    };

    Terminal.prototype.scroll = function() {
      var row;
      if (++this.ybase === this.scrollback) {
        this.ybase = this.ybase / 2 | 0;
        this.lines = this.lines.slice(-(this.ybase + this.rows) + 1);
      }
      this.ydisp = this.ybase;
      row = this.ybase + this.rows - 1;
      row -= this.rows - 1 - this.scrollBottom;
      if (row === this.lines.length) {
        this.lines.push(this.blankLine());
      } else {
        this.lines.splice(row, 0, this.blankLine());
      }
      if (this.scrollTop !== 0) {
        if (this.ybase !== 0) {
          this.ybase--;
          this.ydisp = this.ybase;
        }
        this.lines.splice(this.ybase + this.scrollTop, 1);
      }
      this.updateRange(this.scrollTop);
      return this.updateRange(this.scrollBottom);
    };

    Terminal.prototype.scrollDisp = function(disp) {
      this.ydisp += disp;
      if (this.ydisp > this.ybase) {
        this.ydisp = this.ybase;
      } else {
        if (this.ydisp < 0) {
          this.ydisp = 0;
        }
      }
      return this.refresh(0, this.rows - 1);
    };

    Terminal.prototype.write = function(data) {
      var ch, cs, i, j, l, pt, valid, _ref;
      this.refreshStart = this.y;
      this.refreshEnd = this.y;
      if (this.ybase !== this.ydisp) {
        this.ydisp = this.ybase;
        this.maxRange();
      }
      i = 0;
      l = data.length;
      while (i < l) {
        ch = data[i];
        switch (this.state) {
          case State.normal:
            switch (ch) {
              case "\x07":
                this.bell();
                break;
              case "\n":
              case "\x0b":
              case "\x0c":
                if (this.convertEol) {
                  this.x = 0;
                }
                this.y++;
                if (this.y > this.scrollBottom) {
                  this.y--;
                  this.scroll();
                }
                break;
              case "\r":
                this.x = 0;
                break;
              case "\b":
                if (this.x > 0) {
                  this.x--;
                }
                break;
              case "\t":
                this.x = this.nextStop();
                break;
              case "\x0e":
                this.setgLevel(1);
                break;
              case "\x0f":
                this.setgLevel(0);
                break;
              case "\x1b":
                this.state = State.escaped;
                break;
              default:
                if (ch >= " ") {
                  if ((_ref = this.charset) != null ? _ref[ch] : void 0) {
                    ch = this.charset[ch];
                  }
                  if (this.x >= this.cols) {
                    this.lines[this.y + this.ybase][this.x] = [this.curAttr, '\u23CE'];
                    this.x = 0;
                    this.y++;
                    if (this.y > this.scrollBottom) {
                      this.y--;
                      this.scroll();
                    }
                  }
                  this.lines[this.y + this.ybase][this.x] = [this.curAttr, ch];
                  this.x++;
                  this.updateRange(this.y);
                  if (("\uff00" < ch && ch < "\uffef")) {
                    j = this.y + this.ybase;
                    if (this.cols < 2 || this.x >= this.cols) {
                      this.lines[j][this.x - 1] = [this.curAttr, " "];
                      break;
                    }
                    this.lines[j][this.x] = [this.curAttr, " "];
                    this.x++;
                  }
                }
            }
            break;
          case State.escaped:
            switch (ch) {
              case "[":
                this.params = [];
                this.currentParam = 0;
                this.state = State.csi;
                break;
              case "]":
                this.params = [];
                this.currentParam = 0;
                this.state = State.osc;
                break;
              case "P":
                this.params = [];
                this.currentParam = 0;
                this.state = State.dcs;
                break;
              case "_":
                this.state = State.ignore;
                break;
              case "^":
                this.state = State.ignore;
                break;
              case "c":
                this.reset();
                break;
              case "E":
                this.x = 0;
                this.index();
                break;
              case "D":
                this.index();
                break;
              case "M":
                this.reverseIndex();
                break;
              case "%":
                this.setgLevel(0);
                this.setgCharset(0, Terminal.prototype.charsets.US);
                this.state = State.normal;
                i++;
                break;
              case "(":
              case ")":
              case "*":
              case "+":
              case "-":
              case ".":
                switch (ch) {
                  case "(":
                    this.gcharset = 0;
                    break;
                  case ")":
                  case "-":
                    this.gcharset = 1;
                    break;
                  case "*":
                  case ".":
                    this.gcharset = 2;
                    break;
                  case "+":
                    this.gcharset = 3;
                }
                this.state = State.charset;
                break;
              case "/":
                this.gcharset = 3;
                this.state = State.charset;
                i--;
                break;
              case "n":
                this.setgLevel(2);
                break;
              case "o":
                this.setgLevel(3);
                break;
              case "|":
                this.setgLevel(3);
                break;
              case "}":
                this.setgLevel(2);
                break;
              case "~":
                this.setgLevel(1);
                break;
              case "7":
                this.saveCursor();
                this.state = State.normal;
                break;
              case "8":
                this.restoreCursor();
                this.state = State.normal;
                break;
              case "#":
                this.state = State.normal;
                i++;
                break;
              case "H":
                this.tabSet();
                break;
              case "=":
                this.applicationKeypad = true;
                this.state = State.normal;
                break;
              case ">":
                this.applicationKeypad = false;
                this.state = State.normal;
                break;
              default:
                this.state = State.normal;
                console.log("Unknown ESC control:", ch);
            }
            break;
          case State.charset:
            switch (ch) {
              case "0":
                cs = Terminal.prototype.charsets.SCLD;
                break;
              case "A":
                cs = Terminal.prototype.charsets.UK;
                break;
              case "B":
                cs = Terminal.prototype.charsets.US;
                break;
              case "4":
                cs = Terminal.prototype.charsets.Dutch;
                break;
              case "C":
              case "5":
                cs = Terminal.prototype.charsets.Finnish;
                break;
              case "R":
                cs = Terminal.prototype.charsets.French;
                break;
              case "Q":
                cs = Terminal.prototype.charsets.FrenchCanadian;
                break;
              case "K":
                cs = Terminal.prototype.charsets.German;
                break;
              case "Y":
                cs = Terminal.prototype.charsets.Italian;
                break;
              case "E":
              case "6":
                cs = Terminal.prototype.charsets.NorwegianDanish;
                break;
              case "Z":
                cs = Terminal.prototype.charsets.Spanish;
                break;
              case "H":
              case "7":
                cs = Terminal.prototype.charsets.Swedish;
                break;
              case "=":
                cs = Terminal.prototype.charsets.Swiss;
                break;
              case "/":
                cs = Terminal.prototype.charsets.ISOLatin;
                i++;
                break;
              default:
                cs = Terminal.prototype.charsets.US;
            }
            this.setgCharset(this.gcharset, cs);
            this.gcharset = null;
            this.state = State.normal;
            break;
          case State.osc:
            if (ch === "\x1b" || ch === "\x07") {
              if (ch === "\x1b") {
                i++;
              }
              this.params.push(this.currentParam);
              switch (this.params[0]) {
                case 0:
                case 1:
                case 2:
                  if (this.params[1]) {
                    this.title = this.params[1] + " - ƸӜƷ butterfly";
                    this.handleTitle(this.title);
                  }
              }
              this.params = [];
              this.currentParam = 0;
              this.state = State.normal;
            } else {
              if (!this.params.length) {
                if (ch >= "0" && ch <= "9") {
                  this.currentParam = this.currentParam * 10 + ch.charCodeAt(0) - 48;
                } else if (ch === ";") {
                  this.params.push(this.currentParam);
                  this.currentParam = "";
                }
              } else {
                this.currentParam += ch;
              }
            }
            break;
          case State.csi:
            if (ch === "?" || ch === ">" || ch === "!") {
              this.prefix = ch;
              break;
            }
            if (ch >= "0" && ch <= "9") {
              this.currentParam = this.currentParam * 10 + ch.charCodeAt(0) - 48;
              break;
            }
            if (ch === "$" || ch === "\"" || ch === " " || ch === "'") {
              break;
            }
            this.params.push(this.currentParam);
            this.currentParam = 0;
            if (ch === ";") {
              break;
            }
            this.state = State.normal;
            switch (ch) {
              case "A":
                this.cursorUp(this.params);
                break;
              case "B":
                this.cursorDown(this.params);
                break;
              case "C":
                this.cursorForward(this.params);
                break;
              case "D":
                this.cursorBackward(this.params);
                break;
              case "H":
                this.cursorPos(this.params);
                break;
              case "J":
                this.eraseInDisplay(this.params);
                break;
              case "K":
                this.eraseInLine(this.params);
                break;
              case "m":
                if (!this.prefix) {
                  this.charAttributes(this.params);
                }
                break;
              case "n":
                if (!this.prefix) {
                  this.deviceStatus(this.params);
                }
                break;
              case "@":
                this.insertChars(this.params);
                break;
              case "E":
                this.cursorNextLine(this.params);
                break;
              case "F":
                this.cursorPrecedingLine(this.params);
                break;
              case "G":
                this.cursorCharAbsolute(this.params);
                break;
              case "L":
                this.insertLines(this.params);
                break;
              case "M":
                this.deleteLines(this.params);
                break;
              case "P":
                this.deleteChars(this.params);
                break;
              case "X":
                this.eraseChars(this.params);
                break;
              case "`":
                this.charPosAbsolute(this.params);
                break;
              case "a":
                this.HPositionRelative(this.params);
                break;
              case "c":
                this.sendDeviceAttributes(this.params);
                break;
              case "d":
                this.linePosAbsolute(this.params);
                break;
              case "e":
                this.VPositionRelative(this.params);
                break;
              case "f":
                this.HVPosition(this.params);
                break;
              case "h":
                this.setMode(this.params);
                break;
              case "l":
                this.resetMode(this.params);
                break;
              case "r":
                this.setScrollRegion(this.params);
                break;
              case "s":
                this.saveCursor(this.params);
                break;
              case "u":
                this.restoreCursor(this.params);
                break;
              case "I":
                this.cursorForwardTab(this.params);
                break;
              case "S":
                this.scrollUp(this.params);
                break;
              case "T":
                if (this.params.length < 2 && !this.prefix) {
                  this.scrollDown(this.params);
                }
                break;
              case "Z":
                this.cursorBackwardTab(this.params);
                break;
              case "b":
                this.repeatPrecedingCharacter(this.params);
                break;
              case "g":
                this.tabClear(this.params);
                break;
              case "p":
                if (this.prefix === '!') {
                  this.softReset(this.params);
                }
                break;
              default:
                console.error("Unknown CSI code: %s.", ch);
            }
            this.prefix = "";
            break;
          case State.dcs:
            if (ch === "\x1b" || ch === "\x07") {
              if (ch === "\x1b") {
                i++;
              }
              switch (this.prefix) {
                case "":
                  break;
                case "$q":
                  pt = this.currentParam;
                  valid = false;
                  switch (pt) {
                    case "\"q":
                      pt = "0\"q";
                      break;
                    case "\"p":
                      pt = "61\"p";
                      break;
                    case "r":
                      pt = "" + (this.scrollTop + 1) + ";" + (this.scrollBottom + 1) + "r";
                      break;
                    case "m":
                      pt = "0m";
                      break;
                    default:
                      console.error("Unknown DCS Pt: %s.", pt);
                      pt = "";
                  }
                  this.send("\x1bP" + +valid + "$r" + pt + "\x1b\\");
                  break;
                case "+q":
                  pt = this.currentParam;
                  valid = false;
                  this.send("\x1bP" + +valid + "+r" + pt + "\x1b\\");
                  break;
                default:
                  console.error("Unknown DCS prefix: %s.", this.prefix);
              }
              this.currentParam = 0;
              this.prefix = "";
              this.state = State.normal;
            } else if (!this.currentParam) {
              if (!this.prefix && ch !== "$" && ch !== "+") {
                this.currentParam = ch;
              } else if (this.prefix.length === 2) {
                this.currentParam = ch;
              } else {
                this.prefix += ch;
              }
            } else {
              this.currentParam += ch;
            }
            break;
          case State.ignore:
            if (ch === "\x1b" || ch === "\x07") {
              if (ch === "\x1b") {
                i++;
              }
              this.state = State.normal;
            }
        }
        i++;
      }
      this.updateRange(this.y);
      return this.refresh(this.refreshStart, this.refreshEnd);
    };

    Terminal.prototype.writeln = function(data) {
      return this.write("" + data + "\r\n");
    };

    Terminal.prototype.keyDown = function(ev) {
      var id, key, t, _ref;
      if (ev.keyCode > 15 && ev.keyCode < 19) {
        return true;
      }
      if ((ev.shiftKey || ev.ctrlKey) && ev.keyCode === 45) {
        return true;
      }
      if ((ev.shiftKey && ev.ctrlKey) && ((_ref = ev.keyCode) === 67 || _ref === 86)) {
        console.log('pasting')
        return true;
      }
      if (ev.altKey && ev.keyCode === 90 && !this.skipNextKey) {
        this.skipNextKey = true;
        this.element.classList.add('skip');
        return cancel(ev);
      }
      if (this.skipNextKey) {
        this.skipNextKey = false;
        this.element.classList.remove('skip');
        return true;
      }
      switch (ev.keyCode) {
        case 8:
          key = ev.altKey ? "\x1b" : "";
          if (ev.shiftKey) {
            key += "\x08";
            break;
          }
          key += "\x7f";
          break;
        case 9:
          if (ev.shiftKey) {
            key = "\x1b[Z";
            break;
          }
          key = "\t";
          break;
        case 13:
          key = "\r";
          break;
        case 27:
          key = "\x1b";
          break;
        case 37:
          if (this.applicationCursor) {
            key = "\x1bOD";
            break;
          }
          key = "\x1b[D";
          break;
        case 39:
          if (this.applicationCursor) {
            key = "\x1bOC";
            break;
          }
          key = "\x1b[C";
          break;
        case 38:
          if (this.applicationCursor) {
            key = "\x1bOA";
            break;
          }
          if (ev.ctrlKey) {
            this.scrollDisp(-1);
            return cancel(ev);
          } else {
            key = "\x1b[A";
          }
          break;
        case 40:
          if (this.applicationCursor) {
            key = "\x1bOB";
            break;
          }
          if (ev.ctrlKey) {
            this.scrollDisp(1);
            return cancel(ev);
          } else {
            key = "\x1b[B";
          }
          break;
        case 46:
          key = "\x1b[3~";
          break;
        case 45:
          key = "\x1b[2~";
          break;
        case 36:
          if (this.applicationKeypad) {
            key = "\x1bOH";
            break;
          }
          key = "\x1bOH";
          break;
        case 35:
          if (this.applicationKeypad) {
            key = "\x1bOF";
            break;
          }
          key = "\x1bOF";
          break;
        case 33:
          if (ev.shiftKey) {
            this.scrollDisp(-(this.rows - 1));
            return cancel(ev);
          } else {
            key = "\x1b[5~";
          }
          break;
        case 34:
          if (ev.shiftKey) {
            this.scrollDisp(this.rows - 1);
            return cancel(ev);
          } else {
            key = "\x1b[6~";
          }
          break;
        case 112:
          key = "\x1bOP";
          break;
        case 113:
          key = "\x1bOQ";
          break;
        case 114:
          key = "\x1bOR";
          break;
        case 115:
          key = "\x1bOS";
          break;
        case 116:
          key = "\x1b[15~";
          break;
        case 117:
          key = "\x1b[17~";
          break;
        case 118:
          key = "\x1b[18~";
          break;
        case 119:
          key = "\x1b[19~";
          break;
        case 120:
          key = "\x1b[20~";
          break;
        case 121:
          key = "\x1b[21~";
          break;
        case 122:
          key = "\x1b[23~";
          break;
        case 123:
          key = "\x1b[24~";
          break;
        default:
          if (ev.ctrlKey) {
            if (ev.keyCode >= 65 && ev.keyCode <= 90) {
              if (ev.keyCode === 67) {
                t = (new Date()).getTime();
                if ((t - this.last_cc) < 75) {
                  id = (setTimeout(function() {})) - 6;
                  this.write('\r\n --8<------8<-- Sectioned --8<------8<-- \r\n\r\n');
                  while (id--) {
                    if (id !== this.t_bell && id !== this.t_queue && id !== this.t_blink) {
                      clearTimeout(id);
                    }
                  }
                }
                this.last_cc = t;
              }
              key = String.fromCharCode(ev.keyCode - 64);
            } else if (ev.keyCode === 32) {
              key = String.fromCharCode(0);
            } else if (ev.keyCode >= 51 && ev.keyCode <= 55) {
              key = String.fromCharCode(ev.keyCode - 51 + 27);
            } else if (ev.keyCode === 56) {
              key = String.fromCharCode(127);
            } else if (ev.keyCode === 219) {
              key = String.fromCharCode(27);
            } else {
              if (ev.keyCode === 221) {
                key = String.fromCharCode(29);
              }
            }
          } else if ((ev.altKey && __indexOf.call(navigator.platform, 'Mac') < 0) || (ev.metaKey && __indexOf.call(navigator.platform, 'Mac') >= 0)) {
            if (ev.keyCode >= 65 && ev.keyCode <= 90) {
              key = "\x1b" + String.fromCharCode(ev.keyCode + 32);
            } else if (ev.keyCode === 192) {
              key = "\x1b`";
            } else {
              if (ev.keyCode >= 48 && ev.keyCode <= 57) {
                key = "\x1b" + (ev.keyCode - 48);
              }
            }
          }
      }
      if (ev.keyCode >= 37 && ev.keyCode <= 40) {
        if (ev.ctrlKey) {
          key = key.slice(0, -1) + "1;5" + key.slice(-1);
        } else if (ev.altKey) {
          key = key.slice(0, -1) + "1;3" + key.slice(-1);
        } else if (ev.shiftKey) {
          key = key.slice(0, -1) + "1;4" + key.slice(-1);
        }
      }
      if (!key) {
        return true;
      }
      if (this.prefixMode) {
        this.leavePrefix();
        return cancel(ev);
      }
      if (this.selectMode) {
        this.keySelect(ev, key);
        return cancel(ev);
      }
      this.showCursor();
      this.handler(key);
      return cancel(ev);
    };

    Terminal.prototype.setgLevel = function(g) {
      this.glevel = g;
      return this.charset = this.charsets[g];
    };

    Terminal.prototype.setgCharset = function(g, charset) {
      this.charsets[g] = charset;
      if (this.glevel === g) {
        return this.charset = charset;
      }
    };

    Terminal.prototype.keyPress = function(ev) {
      var key;
      if (this.skipNextKey === false) {
        this.skipNextKey = null;
        return true;
      }
      if (ev.charCode) {
        console.log(ev.charCode)
        key = ev.charCode;
      } else if (ev.which == null) {
        key = ev.keyCode;
      } else if (ev.which !== 0 && ev.charCode !== 0) {
        key = ev.which;
      } else {
        return false;
      }
      if (!key || ev.ctrlKey || ev.altKey || ev.metaKey) {
        return false;
      }
      key = String.fromCharCode(key);
      this.showCursor();
      this.handler(key);
      return false;
    };

    Terminal.prototype.send = function(data) {
      if (!this.queue) {
        this.t_queue = setTimeout(((function(_this) {
          return function() {
            _this.handler(_this.queue);
            return _this.queue = "";
          };
        })(this)), 1);
      }
      return this.queue += data;
    };

    Terminal.prototype.bell = function(cls) {
      if (cls == null) {
        cls = "bell";
      }
      if (!this.visualBell) {
        return;
      }
      this.element.classList.add(cls);
      return this.t_bell = setTimeout(((function(_this) {
        return function() {
          return _this.element.classList.remove(cls);
        };
      })(this)), this.visualBell);
    };

    Terminal.prototype.resize = function() {
      var ch, el, i, j, line, old_cols, old_rows, term_size;
      old_cols = this.cols;
      old_rows = this.rows;
      this.compute_char_size();
      term_size = this.parent.getBoundingClientRect();
      this.cols = Math.floor(term_size.width / this.char_size.width);
      this.rows = Math.floor(term_size.height / this.char_size.height);
      if (old_cols === this.cols && old_rows === this.rows) {
        return;
      }
      this.ctl('Resize', this.cols, this.rows);
      if (old_cols < this.cols) {
        ch = [this.defAttr, " "];
        i = this.lines.length;
        while (i--) {
          while (this.lines[i].length < this.cols) {
            this.lines[i].push(ch);
          }
        }
      } else if (old_cols > this.cols) {
        i = this.lines.length;
        while (i--) {
          while (this.lines[i].length > this.cols) {
            this.lines[i].pop();
          }
        }
      }
      this.setupStops(old_cols);
      j = old_rows;
      if (j < this.rows) {
        el = this.element;
        while (j++ < this.rows) {
          if (this.lines.length < this.rows + this.ybase) {
            this.lines.push(this.blankLine());
          }
          if (this.children.length < this.rows) {
            line = this.document.createElement("div");
            line.className = 'line';
            line.style.height = this.char_size.height + 'px';
            el.appendChild(line);
            this.children.push(line);
          }
        }
      } else if (j > this.rows) {
        while (j-- > this.rows) {
          if (this.lines.length > this.rows + this.ybase) {
            this.lines.pop();
          }
          if (this.children.length > this.rows) {
            el = this.children.pop();
            if (!el) {
              continue;
            }
            el.parentNode.removeChild(el);
          }
        }
      }
      if (this.y >= this.rows) {
        this.y = this.rows - 1;
      }
      if (this.x >= this.cols) {
        this.x = this.cols - 1;
      }
      this.scrollTop = 0;
      this.scrollBottom = this.rows - 1;
      this.refresh(0, this.rows - 1);
      return this.normal = null;
    };

    Terminal.prototype.updateRange = function(y) {
      if (y < this.refreshStart) {
        this.refreshStart = y;
      }
      if (y > this.refreshEnd) {
        return this.refreshEnd = y;
      }
    };

    Terminal.prototype.maxRange = function() {
      this.refreshStart = 0;
      return this.refreshEnd = this.rows - 1;
    };

    Terminal.prototype.setupStops = function(i) {
      var _results;
      if (i != null) {
        if (!this.tabs[i]) {
          i = this.prevStop(i);
        }
      } else {
        this.tabs = {};
        i = 0;
      }
      _results = [];
      while (i < this.cols) {
        this.tabs[i] = true;
        _results.push(i += 8);
      }
      return _results;
    };

    Terminal.prototype.prevStop = function(x) {
      if (x == null) {
        x = this.x;
      }
      while (!this.tabs[--x] && x > 0) {
        1;
      }
      if (x >= this.cols) {
        return this.cols - 1;
      } else {
        if (x < 0) {
          return 0;
        } else {
          return x;
        }
      }
    };

    Terminal.prototype.nextStop = function(x) {
      if (x == null) {
        x = this.x;
      }
      while (!this.tabs[++x] && x < this.cols) {
        1;
      }
      if (x >= this.cols) {
        return this.cols - 1;
      } else {
        if (x < 0) {
          return 0;
        } else {
          return x;
        }
      }
    };

    Terminal.prototype.eraseRight = function(x, y) {
      var ch, line;
      line = this.lines[this.ybase + y];
      ch = [this.eraseAttr(), " "];
      while (x < this.cols) {
        line[x] = ch;
        x++;
      }
      return this.updateRange(y);
    };

    Terminal.prototype.eraseLeft = function(x, y) {
      var ch, line;
      line = this.lines[this.ybase + y];
      ch = [this.eraseAttr(), " "];
      x++;
      while (x--) {
        line[x] = ch;
      }
      return this.updateRange(y);
    };

    Terminal.prototype.eraseLine = function(y) {
      return this.eraseRight(0, y);
    };

    Terminal.prototype.blankLine = function(cur) {
      var attr, ch, i, line;
      attr = (cur ? this.eraseAttr() : this.defAttr);
      ch = [attr, " "];
      line = [];
      i = 0;
      while (i < this.cols + 1) {
        line[i] = ch;
        i++;
      }
      return line;
    };

    Terminal.prototype.ch = function(cur) {
      if (cur) {
        return [this.eraseAttr(), " "];
      } else {
        return [this.defAttr, " "];
      }
    };

    Terminal.prototype.isterm = function(term) {
      return ("" + this.termName).indexOf(term) === 0;
    };

    Terminal.prototype.handler = function(data) {
      return this.out(data);
    };

    Terminal.prototype.handleTitle = function(title) {
      return document.title = title;
    };

    Terminal.prototype.index = function() {
      this.y++;
      if (this.y > this.scrollBottom) {
        this.y--;
        this.scroll();
      }
      return this.state = State.normal;
    };

    Terminal.prototype.reverseIndex = function() {
      var j;
      this.y--;
      if (this.y < this.scrollTop) {
        this.y++;
        this.lines.splice(this.y + this.ybase, 0, this.blankLine(true));
        j = this.rows - 1 - this.scrollBottom;
        this.lines.splice(this.rows - 1 + this.ybase - j + 1, 1);
        this.updateRange(this.scrollTop);
        this.updateRange(this.scrollBottom);
      }
      return this.state = State.normal;
    };

    Terminal.prototype.reset = function() {
      this.reset_vars();
      return this.refresh(0, this.rows - 1);
    };

    Terminal.prototype.tabSet = function() {
      this.tabs[this.x] = true;
      return this.state = State.normal;
    };

    Terminal.prototype.cursorUp = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.y -= param;
      if (this.y < 0) {
        return this.y = 0;
      }
    };

    Terminal.prototype.cursorDown = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.y += param;
      if (this.y >= this.rows) {
        return this.y = this.rows - 1;
      }
    };

    Terminal.prototype.cursorForward = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.x += param;
      if (this.x >= this.cols) {
        return this.x = this.cols - 1;
      }
    };

    Terminal.prototype.cursorBackward = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.x -= param;
      if (this.x < 0) {
        return this.x = 0;
      }
    };

    Terminal.prototype.cursorPos = function(params) {
      var col, row;
      row = params[0] - 1;
      if (params.length >= 2) {
        col = params[1] - 1;
      } else {
        col = 0;
      }
      if (row < 0) {
        row = 0;
      } else {
        if (row >= this.rows) {
          row = this.rows - 1;
        }
      }
      if (col < 0) {
        col = 0;
      } else {
        if (col >= this.cols) {
          col = this.cols - 1;
        }
      }
      this.x = col;
      return this.y = row;
    };

    Terminal.prototype.eraseInDisplay = function(params) {
      var j, _results, _results1, _results2;
      switch (params[0]) {
        case 0:
          this.eraseRight(this.x, this.y);
          j = this.y + 1;
          _results = [];
          while (j < this.rows) {
            this.eraseLine(j);
            _results.push(j++);
          }
          return _results;
          break;
        case 1:
          this.eraseLeft(this.x, this.y);
          j = this.y;
          _results1 = [];
          while (j--) {
            _results1.push(this.eraseLine(j));
          }
          return _results1;
          break;
        case 2:
          j = this.rows;
          _results2 = [];
          while (j--) {
            _results2.push(this.eraseLine(j));
          }
          return _results2;
      }
    };

    Terminal.prototype.eraseInLine = function(params) {
      switch (params[0]) {
        case 0:
          return this.eraseRight(this.x, this.y);
        case 1:
          return this.eraseLeft(this.x, this.y);
        case 2:
          return this.eraseLine(this.y);
      }
    };

    Terminal.prototype.charAttributes = function(params) {
      var bg, fg, flags, i, l, p;
      if (params.length === 1 && params[0] === 0) {
        this.curAttr = this.defAttr;
        return;
      }
      flags = this.curAttr >> 18;
      fg = (this.curAttr >> 9) & 0x1ff;
      bg = this.curAttr & 0x1ff;
      l = params.length;
      i = 0;
      while (i < l) {
        p = params[i];
        if (p >= 30 && p <= 37) {
          fg = p - 30;
        } else if (p >= 40 && p <= 47) {
          bg = p - 40;
        } else if (p >= 90 && p <= 97) {
          p += 8;
          fg = p - 90;
        } else if (p >= 100 && p <= 107) {
          p += 8;
          bg = p - 100;
        } else if (p === 0) {
          flags = this.defAttr >> 18;
          fg = (this.defAttr >> 9) & 0x1ff;
          bg = this.defAttr & 0x1ff;
        } else if (p === 1) {
          flags |= 1;
        } else if (p === 4) {
          flags |= 2;
        } else if (p === 5) {
          flags |= 4;
        } else if (p === 7) {
          flags |= 8;
        } else if (p === 8) {
          flags |= 16;
        } else if (p === 22) {
          flags &= ~1;
        } else if (p === 24) {
          flags &= ~2;
        } else if (p === 25) {
          flags &= ~4;
        } else if (p === 27) {
          flags &= ~8;
        } else if (p === 28) {
          flags &= ~16;
        } else if (p === 39) {
          fg = (this.defAttr >> 9) & 0x1ff;
        } else if (p === 49) {
          bg = this.defAttr & 0x1ff;
        } else if (p === 38) {
          if (params[i + 1] === 2) {
            i += 2;
            fg = "#" + params[i] & 0xff + params[i + 1] & 0xff + params[i + 2] & 0xff;
            i += 2;
          } else if (params[i + 1] === 5) {
            i += 2;
            fg = params[i] & 0xff;
          }
        } else if (p === 48) {
          if (params[i + 1] === 2) {
            i += 2;
            bg = "#" + params[i] & 0xff + params[i + 1] & 0xff + params[i + 2] & 0xff;
            i += 2;
          } else if (params[i + 1] === 5) {
            i += 2;
            bg = params[i] & 0xff;
          }
        } else if (p === 100) {
          fg = (this.defAttr >> 9) & 0x1ff;
          bg = this.defAttr & 0x1ff;
        } else {
          console.error("Unknown SGR attribute: %d.", p);
        }
        i++;
      }
      return this.curAttr = (flags << 18) | (fg << 9) | bg;
    };

    Terminal.prototype.deviceStatus = function(params) {
      if (!this.prefix) {
        switch (params[0]) {
          case 5:
            return this.send("\x1b[0n");
          case 6:
            return this.send("\x1b[" + (this.y + 1) + ";" + (this.x + 1) + "R");
        }
      } else if (this.prefix === "?") {
        if (params[0] === 6) {
          return this.send("\x1b[?" + (this.y + 1) + ";" + (this.x + 1) + "R");
        }
      }
    };

    Terminal.prototype.insertChars = function(params) {
      var ch, j, param, row, _results;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      row = this.y + this.ybase;
      j = this.x;
      ch = [this.eraseAttr(), " "];
      _results = [];
      while (param-- && j < this.cols) {
        this.lines[row].splice(j++, 0, ch);
        _results.push(this.lines[row].pop());
      }
      return _results;
    };

    Terminal.prototype.cursorNextLine = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.y += param;
      if (this.y >= this.rows) {
        this.y = this.rows - 1;
      }
      return this.x = 0;
    };

    Terminal.prototype.cursorPrecedingLine = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.y -= param;
      if (this.y < 0) {
        this.y = 0;
      }
      return this.x = 0;
    };

    Terminal.prototype.cursorCharAbsolute = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      return this.x = param - 1;
    };

    Terminal.prototype.insertLines = function(params) {
      var j, param, row;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      row = this.y + this.ybase;
      j = this.rows - 1 - this.scrollBottom;
      j = this.rows - 1 + this.ybase - j + 1;
      while (param--) {
        this.lines.splice(row, 0, this.blankLine(true));
        this.lines.splice(j, 1);
      }
      this.updateRange(this.y);
      return this.updateRange(this.scrollBottom);
    };

    Terminal.prototype.deleteLines = function(params) {
      var j, param, row;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      row = this.y + this.ybase;
      j = this.rows - 1 - this.scrollBottom;
      j = this.rows - 1 + this.ybase - j;
      while (param--) {
        this.lines.splice(j + 1, 0, this.blankLine(true));
        this.lines.splice(row, 1);
      }
      this.updateRange(this.y);
      return this.updateRange(this.scrollBottom);
    };

    Terminal.prototype.deleteChars = function(params) {
      var ch, param, row, _results;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      row = this.y + this.ybase;
      ch = [this.eraseAttr(), " "];
      _results = [];
      while (param--) {
        this.lines[row].splice(this.x, 1);
        _results.push(this.lines[row].push(ch));
      }
      return _results;
    };

    Terminal.prototype.eraseChars = function(params) {
      var ch, j, param, row, _results;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      row = this.y + this.ybase;
      j = this.x;
      ch = [this.eraseAttr(), " "];
      _results = [];
      while (param-- && j < this.cols) {
        _results.push(this.lines[row][j++] = ch);
      }
      return _results;
    };

    Terminal.prototype.charPosAbsolute = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.x = param - 1;
      if (this.x >= this.cols) {
        return this.x = this.cols - 1;
      }
    };

    Terminal.prototype.HPositionRelative = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.x += param;
      if (this.x >= this.cols) {
        return this.x = this.cols - 1;
      }
    };

    Terminal.prototype.sendDeviceAttributes = function(params) {
      if (params[0] > 0) {
        return;
      }
      if (!this.prefix) {
        if (this.isterm("xterm") || this.isterm("rxvt-unicode") || this.isterm("screen")) {
          return this.send("\x1b[?1;2c");
        } else {
          if (this.isterm("linux")) {
            return this.send("\x1b[?6c");
          }
        }
      } else if (this.prefix === ">") {
        if (this.isterm("xterm")) {
          return this.send("\x1b[>0;276;0c");
        } else if (this.isterm("rxvt-unicode")) {
          return this.send("\x1b[>85;95;0c");
        } else if (this.isterm("linux")) {
          return this.send(params[0] + "c");
        } else {
          if (this.isterm("screen")) {
            return this.send("\x1b[>83;40003;0c");
          }
        }
      }
    };

    Terminal.prototype.linePosAbsolute = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.y = param - 1;
      if (this.y >= this.rows) {
        return this.y = this.rows - 1;
      }
    };

    Terminal.prototype.VPositionRelative = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      this.y += param;
      if (this.y >= this.rows) {
        return this.y = this.rows - 1;
      }
    };

    Terminal.prototype.HVPosition = function(params) {
      if (params[0] < 1) {
        params[0] = 1;
      }
      if (params[1] < 1) {
        params[1] = 1;
      }
      this.y = params[0] - 1;
      if (this.y >= this.rows) {
        this.y = this.rows - 1;
      }
      this.x = params[1] - 1;
      if (this.x >= this.cols) {
        return this.x = this.cols - 1;
      }
    };

    Terminal.prototype.setMode = function(params) {
      var i, l, normal;
      if (typeof params === "object") {
        l = params.length;
        i = 0;
        while (i < l) {
          this.setMode(params[i]);
          i++;
        }
        return;
      }
      if (this.prefix === "?") {
        switch (params) {
          case 1:
            return this.applicationCursor = true;
          case 2:
            this.setgCharset(0, Terminal.prototype.charsets.US);
            this.setgCharset(1, Terminal.prototype.charsets.US);
            this.setgCharset(2, Terminal.prototype.charsets.US);
            return this.setgCharset(3, Terminal.prototype.charsets.US);
          case 3:
            this.savedCols = this.cols;
            return this.resize(132, this.rows);
          case 6:
            return this.originMode = true;
          case 7:
            return this.wraparoundMode = true;
          case 66:
            return this.applicationKeypad = true;
          case 9:
          case 1000:
          case 1002:
          case 1003:
            this.x10Mouse = params === 9;
            this.vt200Mouse = params === 1000;
            this.normalMouse = params > 1000;
            this.mouseEvents = true;
            return this.element.style.cursor = 'pointer';
          case 1004:
            return this.sendFocus = true;
          case 1005:
            return this.utfMouse = true;
          case 1006:
            return this.sgrMouse = true;
          case 1015:
            return this.urxvtMouse = true;
          case 25:
            return this.cursorHidden = false;
          case 1049:
          case 47:
          case 1047:
            if (!this.normal) {
              normal = {
                lines: this.lines,
                ybase: this.ybase,
                ydisp: this.ydisp,
                x: this.x,
                y: this.y,
                scrollTop: this.scrollTop,
                scrollBottom: this.scrollBottom,
                tabs: this.tabs
              };
              this.reset();
              this.normal = normal;
              return this.showCursor();
            }
        }
      }
    };

    Terminal.prototype.resetMode = function(params) {
      var i, l;
      if (typeof params === "object") {
        l = params.length;
        i = 0;
        while (i < l) {
          this.resetMode(params[i]);
          i++;
        }
        return;
      }
      if (this.prefix === "?") {
        switch (params) {
          case 1:
            return this.applicationCursor = false;
          case 3:
            if (this.cols === 132 && this.savedCols) {
              this.resize(this.savedCols, this.rows);
            }
            return delete this.savedCols;
          case 6:
            return this.originMode = false;
          case 7:
            return this.wraparoundMode = false;
          case 66:
            return this.applicationKeypad = false;
          case 9:
          case 1000:
          case 1002:
          case 1003:
            this.x10Mouse = false;
            this.vt200Mouse = false;
            this.normalMouse = false;
            this.mouseEvents = false;
            return this.element.style.cursor = "";
          case 1004:
            return this.sendFocus = false;
          case 1005:
            return this.utfMouse = false;
          case 1006:
            return this.sgrMouse = false;
          case 1015:
            return this.urxvtMouse = false;
          case 25:
            return this.cursorHidden = true;
          case 1049:
          case 47:
          case 1047:
            if (this.normal) {
              this.lines = this.normal.lines;
              this.ybase = this.normal.ybase;
              this.ydisp = this.normal.ydisp;
              this.x = this.normal.x;
              this.y = this.normal.y;
              this.scrollTop = this.normal.scrollTop;
              this.scrollBottom = this.normal.scrollBottom;
              this.tabs = this.normal.tabs;
              this.normal = null;
              this.refresh(0, this.rows - 1);
              return this.showCursor();
            }
        }
      }
    };

    Terminal.prototype.setScrollRegion = function(params) {
      if (this.prefix) {
        return;
      }
      this.scrollTop = (params[0] || 1) - 1;
      this.scrollBottom = (params[1] || this.rows) - 1;
      this.x = 0;
      return this.y = 0;
    };

    Terminal.prototype.saveCursor = function(params) {
      this.savedX = this.x;
      return this.savedY = this.y;
    };

    Terminal.prototype.restoreCursor = function(params) {
      this.x = this.savedX || 0;
      return this.y = this.savedY || 0;
    };

    Terminal.prototype.cursorForwardTab = function(params) {
      var param, _results;
      param = params[0] || 1;
      _results = [];
      while (param--) {
        _results.push(this.x = this.nextStop());
      }
      return _results;
    };

    Terminal.prototype.scrollUp = function(params) {
      var param;
      param = params[0] || 1;
      while (param--) {
        this.lines.splice(this.ybase + this.scrollTop, 1);
        this.lines.splice(this.ybase + this.scrollBottom, 0, this.blankLine());
      }
      this.updateRange(this.scrollTop);
      return this.updateRange(this.scrollBottom);
    };

    Terminal.prototype.scrollDown = function(params) {
      var param;
      param = params[0] || 1;
      while (param--) {
        this.lines.splice(this.ybase + this.scrollBottom, 1);
        this.lines.splice(this.ybase + this.scrollTop, 0, this.blankLine());
      }
      this.updateRange(this.scrollTop);
      return this.updateRange(this.scrollBottom);
    };

    Terminal.prototype.initMouseTracking = function(params) {};

    Terminal.prototype.resetTitleModes = function(params) {};

    Terminal.prototype.cursorBackwardTab = function(params) {
      var param, _results;
      param = params[0] || 1;
      _results = [];
      while (param--) {
        _results.push(this.x = this.prevStop());
      }
      return _results;
    };

    Terminal.prototype.repeatPrecedingCharacter = function(params) {
      var ch, line, param, _results;
      param = params[0] || 1;
      line = this.lines[this.ybase + this.y];
      ch = line[this.x - 1] || [this.defAttr, " "];
      _results = [];
      while (param--) {
        _results.push(line[this.x++] = ch);
      }
      return _results;
    };

    Terminal.prototype.tabClear = function(params) {
      var param;
      param = params[0];
      if (param <= 0) {
        return delete this.tabs[this.x];
      } else {
        if (param === 3) {
          return this.tabs = {};
        }
      }
    };

    Terminal.prototype.mediaCopy = function(params) {};

    Terminal.prototype.setResources = function(params) {};

    Terminal.prototype.disableModifiers = function(params) {};

    Terminal.prototype.setPointerMode = function(params) {};

    Terminal.prototype.softReset = function(params) {
      this.cursorHidden = false;
      this.insertMode = false;
      this.originMode = false;
      this.wraparoundMode = false;
      this.applicationKeypad = false;
      this.applicationCursor = false;
      this.scrollTop = 0;
      this.scrollBottom = this.rows - 1;
      this.curAttr = this.defAttr;
      this.x = this.y = 0;
      this.charset = null;
      this.glevel = 0;
      return this.charsets = [null];
    };

    Terminal.prototype.requestAnsiMode = function(params) {};

    Terminal.prototype.requestPrivateMode = function(params) {};

    Terminal.prototype.setConformanceLevel = function(params) {};

    Terminal.prototype.loadLEDs = function(params) {};

    Terminal.prototype.setCursorStyle = function(params) {};

    Terminal.prototype.setCharProtectionAttr = function(params) {};

    Terminal.prototype.restorePrivateValues = function(params) {};

    Terminal.prototype.setAttrInRectangle = function(params) {
      var attr, b, i, l, line, r, t;
      t = params[0];
      l = params[1];
      b = params[2];
      r = params[3];
      attr = params[4];
      while (t < b + 1) {
        line = this.lines[this.ybase + t];
        i = l;
        while (i < r) {
          line[i] = [attr, line[i][1]];
          i++;
        }
        t++;
      }
      this.updateRange(params[0]);
      return this.updateRange(params[2]);
    };

    Terminal.prototype.savePrivateValues = function(params) {};

    Terminal.prototype.manipulateWindow = function(params) {};

    Terminal.prototype.reverseAttrInRectangle = function(params) {};

    Terminal.prototype.setTitleModeFeature = function(params) {};

    Terminal.prototype.setWarningBellVolume = function(params) {};

    Terminal.prototype.setMarginBellVolume = function(params) {};

    Terminal.prototype.copyRectangle = function(params) {};

    Terminal.prototype.enableFilterRectangle = function(params) {};

    Terminal.prototype.requestParameters = function(params) {};

    Terminal.prototype.selectChangeExtent = function(params) {};

    Terminal.prototype.fillRectangle = function(params) {
      var b, ch, i, l, line, r, t;
      ch = params[0];
      t = params[1];
      l = params[2];
      b = params[3];
      r = params[4];
      while (t < b + 1) {
        line = this.lines[this.ybase + t];
        i = l;
        while (i < r) {
          line[i] = [line[i][0], String.fromCharCode(ch)];
          i++;
        }
        t++;
      }
      this.updateRange(params[1]);
      return this.updateRange(params[3]);
    };

    Terminal.prototype.enableLocatorReporting = function(params) {
      var val;
      return val = params[0] > 0;
    };

    Terminal.prototype.eraseRectangle = function(params) {
      var b, ch, i, l, line, r, t;
      t = params[0];
      l = params[1];
      b = params[2];
      r = params[3];
      ch = [this.eraseAttr(), " "];
      while (t < b + 1) {
        line = this.lines[this.ybase + t];
        i = l;
        while (i < r) {
          line[i] = ch;
          i++;
        }
        t++;
      }
      this.updateRange(params[0]);
      return this.updateRange(params[2]);
    };

    Terminal.prototype.setLocatorEvents = function(params) {};

    Terminal.prototype.selectiveEraseRectangle = function(params) {};

    Terminal.prototype.requestLocatorPosition = function(params) {};

    Terminal.prototype.insertColumns = function() {
      var ch, i, l, param;
      param = params[0];
      l = this.ybase + this.rows;
      ch = [this.eraseAttr(), " "];
      while (param--) {
        i = this.ybase;
        while (i < l) {
          this.lines[i].splice(this.x + 1, 0, ch);
          this.lines[i].pop();
          i++;
        }
      }
      return this.maxRange();
    };

    Terminal.prototype.deleteColumns = function() {
      var ch, i, l, param;
      param = params[0];
      l = this.ybase + this.rows;
      ch = [this.eraseAttr(), " "];
      while (param--) {
        i = this.ybase;
        while (i < l) {
          this.lines[i].splice(this.x, 1);
          this.lines[i].push(ch);
          i++;
        }
      }
      return this.maxRange();
    };

    Terminal.prototype.get_html_height_in_lines = function(html) {
      var html_height, temp_node;
      temp_node = document.createElement("div");
      temp_node.innerHTML = html;
      this.element.appendChild(temp_node);
      html_height = temp_node.getBoundingClientRect().height;
      this.element.removeChild(temp_node);
      return Math.ceil(html_height / this.char_size.height);
    };

    Terminal.prototype.charsets = {
      SCLD: {
        "`": "◆",
        a: "▒",
        b: "\t",
        c: "\f",
        d: "\r",
        e: "\n",
        f: "°",
        g: "±",
        h: "␤",
        i: "\x0b",
        j: "┘",
        k: "┐",
        l: "┌",
        m: "└",
        n: "┼",
        o: "⎺",
        p: "⎻",
        q: "─",
        r: "⎼",
        s: "⎽",
        t: "├",
        u: "┤",
        v: "┴",
        w: "┬",
        x: "│",
        y: "≤",
        z: "≥",
        "{": "π",
        "|": "≠",
        "}": "£",
        "~": "·"
      },
      UK: null,
      US: null,
      Dutch: null,
      Finnish: null,
      French: null,
      FrenchCanadian: null,
      German: null,
      Italian: null,
      NorwegianDanish: null,
      Spanish: null,
      Swedish: null,
      Swiss: null,
      ISOLatin: null
    };

    return Terminal;

  })();

  window.Terminal = Terminal;

}).call(this);

//# sourceMappingURL=main.js.map
