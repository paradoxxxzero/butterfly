(function() {
  var $, State, Terminal, cancel, cols, isMobile, openTs, quit, rows, s, ws,
    indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  cols = rows = null;

  quit = false;

  openTs = (new Date()).getTime();

  ws = {
    shell: null,
    ctl: null
  };

  $ = document.querySelectorAll.bind(document);

  document.addEventListener('DOMContentLoaded', function() {
    var close, ctl, error, init_ctl_ws, init_shell_ws, open, path, reopenOnClose, rootPath, term, write, write_request, wsUrl;
    term = null;
    if (location.protocol === 'https:') {
      wsUrl = 'wss://';
    } else {
      wsUrl = 'ws://';
    }
    rootPath = document.body.getAttribute('data-root-path');
    rootPath = rootPath.replace(/^\/+|\/+$/g, '');
    if (rootPath.length) {
      rootPath = "/" + rootPath;
    }
    wsUrl += document.location.host + rootPath;
    path = '/';
    if (path.indexOf('/session') < 0) {
      path += "session/" + (document.body.getAttribute('data-session-token'));
    }
    path += location.search;
    ws.shell = new WebSocket(wsUrl + '/ws' + path);
    ws.ctl = new WebSocket(wsUrl + '/ctl' + path);
    open = function() {
      console.log("WebSocket open", arguments);
      if (term) {
        term.body.classList.remove('stopped');
        term.out = ws.shell.send.bind(ws.shell);
        term.out('\x03\n');
        return;
      }
      if (ws.shell.readyState === WebSocket.OPEN && ws.ctl.readyState === WebSocket.OPEN) {
        term = new Terminal(document.body, ws.shell.send.bind(ws.shell), ws.ctl.send.bind(ws.ctl));
        term.ws = ws;
        window.butterfly = term;
        ws.ctl.send(JSON.stringify({
          cmd: 'open'
        }));
        ws.ctl.send(JSON.stringify({
          cmd: 'size',
          cols: term.cols,
          rows: term.rows
        }));
        openTs = (new Date()).getTime();
      }
      return console.log("WebSocket open end", arguments);
    };
    error = function() {
      return console.error("WebSocket error", arguments);
    };
    close = function() {
      console.log("WebSocket closed", arguments);
      if (quit) {
        return;
      }
      quit = true;
      term.write('Closed');
      term.skipNextKey = true;
      term.body.classList.add('dead');
      if ((new Date()).getTime() - openTs > 60 * 1000) {
        return window.open('', '_self').close();
      }
    };
    reopenOnClose = function() {
      return setTimeout(function() {
        if (quit) {
          return;
        }
        ws.shell = new WebSocket(wsUrl + '/ws' + path);
        return init_shell_ws();
      }, 100);
    };
    write = function(data) {
      if (term) {
        return term.write(data);
      }
    };
    write_request = function(e) {
      return setTimeout(write, 1, e.data);
    };
    ctl = function(e) {
      var cmd;
      cmd = JSON.parse(e.data);
      if (cmd.cmd === 'size') {
        return term.resize(cmd.cols, cmd.rows, true);
      }
    };
    init_shell_ws = function() {
      ws.shell.addEventListener('open', open);
      ws.shell.addEventListener('message', write_request);
      ws.shell.addEventListener('error', error);
      return ws.shell.addEventListener('close', reopenOnClose);
    };
    init_ctl_ws = function() {
      ws.ctl.addEventListener('open', open);
      ws.ctl.addEventListener('message', ctl);
      ws.ctl.addEventListener('error', error);
      return ws.ctl.addEventListener('close', close);
    };
    init_shell_ws();
    init_ctl_ws();
    return addEventListener('beforeunload', function() {
      if (!quit) {
        return 'This will exit the terminal session';
      }
    });
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

  isMobile = function() {
    return /iPhone|iPad|iPod|Android/i.test(navigator.userAgent);
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
    Terminal.hooks = {};

    Terminal.on = function(hook, fun) {
      if (Terminal.hooks[hook] == null) {
        Terminal.hooks[hook] = [];
      }
      return Terminal.hooks[hook].push(fun);
    };

    Terminal.off = function(hook, fun) {
      if (Terminal.hooks[hook] == null) {
        Terminal.hooks[hook] = [];
      }
      return Terminal.hooks[hook].pop(fun);
    };

    function Terminal(parent, out, ctl1) {
      var div;
      this.parent = parent;
      this.out = out;
      this.ctl = ctl1 != null ? ctl1 : function() {};
      this.document = this.parent.ownerDocument;
      this.html = this.document.getElementsByTagName('html')[0];
      this.body = this.document.getElementsByTagName('body')[0];
      this.term = this.document.getElementById('term');
      this.forceWidth = this.body.getAttribute('data-force-unicode-width') === 'yes';
      this.inputHelper = this.document.getElementById('input-helper');
      this.inputView = this.document.getElementById('input-view');
      this.body.className = 'terminal focus';
      this.body.style.outline = 'none';
      this.body.setAttribute('tabindex', 0);
      this.body.setAttribute('spellcheck', 'false');
      this.inputHelper.setAttribute('tabindex', 0);
      this.inputHelper.setAttribute('spellcheck', 'false');
      div = this.document.createElement('div');
      div.className = 'line';
      this.term.appendChild(div);
      this.computeCharSize();
      this.cols = Math.floor(this.body.clientWidth / this.charSize.width);
      this.rows = Math.floor(window.innerHeight / this.charSize.height);
      this.visualBell = 100;
      this.convertEol = false;
      this.termName = 'xterm';
      this.cursorBlink = true;
      this.cursorState = 0;
      this.inComposition = false;
      this.compositionText = "";
      this.resetVars();
      this.focus();
      this.startBlink();
      this.inputHelper.addEventListener('compositionstart', this.compositionStart.bind(this));
      this.inputHelper.addEventListener('compositionupdate', this.compositionUpdate.bind(this));
      this.inputHelper.addEventListener('compositionend', this.compositionEnd.bind(this));
      addEventListener('keydown', this.keyDown.bind(this));
      addEventListener('keypress', this.keyPress.bind(this));
      addEventListener('keyup', (function(_this) {
        return function() {
          return _this.inputHelper.focus();
        };
      })(this));
      if (isMobile()) {
        addEventListener('click', (function(_this) {
          return function() {
            return _this.inputHelper.focus();
          };
        })(this));
      }
      addEventListener('focus', this.focus.bind(this));
      addEventListener('blur', this.blur.bind(this));
      addEventListener('resize', (function(_this) {
        return function() {
          return _this.resize();
        };
      })(this));
      this.body.addEventListener('load', (function(_this) {
        return function() {
          return _this.nativeScrollTo();
        };
      })(this), true);
      this.initmouse();
      addEventListener('load', (function(_this) {
        return function() {
          return _this.resize();
        };
      })(this));
      this.emit('load');
      this.active = null;
    }

    Terminal.prototype.emit = function(hook, obj) {
      var fun, k, len, ref, results;
      if (Terminal.hooks[hook] == null) {
        Terminal.hooks[hook] = [];
      }
      ref = Terminal.hooks[hook];
      results = [];
      for (k = 0, len = ref.length; k < len; k++) {
        fun = ref[k];
        results.push(setTimeout((function(f) {
          return function() {
            return f.call(this, obj);
          };
        })(fun), 10));
      }
      return results;
    };

    Terminal.prototype.cloneAttr = function(a, char) {
      if (char == null) {
        char = null;
      }
      return {
        bg: a.bg,
        fg: a.fg,
        ch: char !== null ? char : a.ch,
        bold: a.bold,
        underline: a.underline,
        blink: a.blink,
        inverse: a.inverse,
        invisible: a.invisible,
        italic: a.italic,
        faint: a.faint,
        crossed: a.crossed,
        placeholder: false
      };
    };

    Terminal.prototype.equalAttr = function(a, b) {
      return a.bg === b.bg && a.fg === b.fg && a.bold === b.bold && a.underline === b.underline && a.blink === b.blink && a.inverse === b.inverse && a.invisible === b.invisible && a.italic === b.italic && a.faint === b.faint && a.crossed === b.crossed;
    };

    Terminal.prototype.putChar = function(c, placeholder) {
      var newChar;
      if (placeholder == null) {
        placeholder = false;
      }
      newChar = this.cloneAttr(this.curAttr, c);
      newChar.placeholder = placeholder;
      if (this.insertMode) {
        this.screen[this.y + this.shift].chars.splice(this.x, 0, newChar);
        this.screen[this.y + this.shift].chars.pop();
      } else {
        this.screen[this.y + this.shift].chars[this.x] = newChar;
      }
      return this.screen[this.y + this.shift].dirty = true;
    };

    Terminal.prototype.resetVars = function() {
      var k, ref, row;
      this.x = 0;
      this.y = 0;
      this.cursorHidden = false;
      this.state = State.normal;
      this.queue = '';
      this.scrollTop = 0;
      this.scrollBottom = this.rows - 1;
      this.scrollLock = false;
      this.applicationKeypad = false;
      this.applicationCursor = false;
      this.originMode = false;
      this.autowrap = true;
      this.horizontalWrap = false;
      this.normal = null;
      this.charset = null;
      this.gcharset = null;
      this.glevel = 0;
      this.charsets = [null];
      this.defAttr = {
        bg: 256,
        fg: 257,
        ch: " ",
        bold: false,
        underline: false,
        blink: 0,
        inverse: false,
        invisible: false,
        italic: false,
        faint: false,
        crossed: false,
        placeholder: false
      };
      this.curAttr = this.cloneAttr(this.defAttr);
      this.params = [];
      this.currentParam = 0;
      this.prefix = "";
      this.screen = [];
      this.shift = 0;
      for (row = k = 0, ref = this.rows - 1; 0 <= ref ? k <= ref : k >= ref; row = 0 <= ref ? ++k : --k) {
        this.screen.push(this.blankLine(false, false));
      }
      this.setupStops();
      return this.skipNextKey = null;
    };

    Terminal.prototype.computeCharSize = function() {
      var line, testSpan;
      testSpan = document.createElement('span');
      testSpan.textContent = '0123456789';
      line = this.term.firstChild;
      line.appendChild(testSpan);
      this.charSize = {
        width: testSpan.getBoundingClientRect().width / 10,
        height: line.getBoundingClientRect().height
      };
      return line.removeChild(testSpan);
    };

    Terminal.prototype.eraseAttr = function() {
      var erased;
      erased = this.cloneAttr(this.defAttr);
      erased.bg = this.curAttr.bg;
      return erased;
    };

    Terminal.prototype.focus = function() {
      var old_sl;
      old_sl = this.scrollLock;
      this.scrollLock = true;
      if (this.sendFocus) {
        this.send('\x1b[I');
      }
      this.showCursor();
      this.body.classList.add('focus');
      this.body.classList.remove('blur');
      this.inputHelper.focus();
      this.resize();
      return this.scrollLock = old_sl;
    };

    Terminal.prototype.blur = function() {
      var old_sl;
      old_sl = this.scrollLock;
      this.scrollLock = true;
      this.cursorState = 1;
      this.screen[this.y + this.shift].dirty = true;
      this.refresh();
      if (this.sendFocus) {
        this.send('\x1b[O');
      }
      this.body.classList.add('blur');
      this.body.classList.remove('focus');
      return this.scrollLock = old_sl;
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
        sendEvent(button, pos, ev.type);
        return pressed = button;
      };
      sendMove = function(ev) {
        var button, pos;
        button = pressed;
        pos = getCoords(ev);
        if (!pos) {
          return;
        }
        button += 32;
        return sendEvent(button, pos, ev.type);
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
        return function(button, pos, type) {
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
            button -= 32;
            _this.send("\x1b[<" + button + ";" + pos.x + ";" + pos.y + (type === "mouseup" ? "m" : "M"));
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
          var h, w, x, y;
          x = ev.pageX;
          y = ev.pageY - window.scrollY;
          w = _this.body.clientWidth;
          h = window.innerHeight;
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
      addEventListener("contextmenu", (function(_this) {
        return function(ev) {
          if (!_this.mouseEvents) {
            return;
          }
          return cancel(ev);
        };
      })(this));
      addEventListener("mousedown", (function(_this) {
        return function(ev) {
          var sm, up;
          if (!_this.mouseEvents) {
            return;
          }
          sendButton(ev);
          sm = sendMove.bind(_this);
          addEventListener("mousemove", sm);
          if (!_this.x10Mouse) {
            addEventListener("mouseup", up = function(ev) {
              sendButton(ev);
              removeEventListener("mousemove", sm);
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
            return cancel(ev);
          }
        };
      })(this));
    };

    Terminal.prototype.getClasses = function(data) {
      var classes, fg, styles;
      classes = [];
      styles = [];
      if (data.bold) {
        classes.push("bold");
      }
      if (data.underline) {
        classes.push("underline");
      }
      if (data.blink === 1) {
        classes.push("blink");
      }
      if (data.blink === 2) {
        classes.push("blink-fast");
      }
      if (data.inverse) {
        classes.push("reverse-video");
      }
      if (data.invisible) {
        classes.push("invisible");
      }
      if (data.italic) {
        classes.push("italic");
      }
      if (data.faint) {
        classes.push("faint");
      }
      if (data.crossed) {
        classes.push("crossed");
      }
      if (typeof data.fg === 'number') {
        fg = data.fg;
        if (data.bold && fg < 8) {
          fg += 8;
        }
        classes.push("fg-color-" + fg);
      } else if (typeof data.fg === 'string') {
        styles.push("color: " + data.fg);
      }
      if (typeof data.bg === 'number') {
        classes.push("bg-color-" + data.bg);
      } else if (typeof data.bg === 'string') {
        styles.push("background-color: " + data.bg);
      }
      return [classes, styles];
    };

    Terminal.prototype.isCJK = function(ch) {
      return ("\u4e00" <= ch && ch <= "\u9fff") || ("\u3040" <= ch && ch <= "\u30ff") || ("\u31f0" <= ch && ch <= "\u31ff") || ("\u3190" <= ch && ch <= "\u319f") || ("\u3301" <= ch && ch <= "\u3356") || ("\uac00" <= ch && ch <= "\ud7ff") || ("\u3000" <= ch && ch <= "\u303f") || ("\uff00" <= ch && ch <= "\uff60") || ("\uffe0" <= ch && ch <= "\uffe6");
    };

    Terminal.prototype.charToDom = function(data, attr, cursor) {
      var ch, char, classes, ref, styles;
      if (data.placeholder) {
        return;
      }
      if (data.html) {
        return data.html;
      }
      attr = attr || this.cloneAttr(this.defAttr);
      ch = data.ch;
      char = '';
      if (!this.equalAttr(data, attr)) {
        if (!this.equalAttr(attr, this.defAttr)) {
          char += "</span>";
        }
        if (!this.equalAttr(data, this.defAttr)) {
          ref = this.getClasses(data), classes = ref[0], styles = ref[1];
          char += "<span class=\"" + (classes.join(" ")) + "\"";
          if (styles.length) {
            char += " style=\"" + styles.join("; ") + "\"";
          }
          char += ">";
        }
      }
      if (cursor) {
        char += "<span class=\"" + (this.cursorState ? "reverse-video " : "") + "cursor\">";
      }
      switch (ch) {
        case "&":
          char += "&amp;";
          break;
        case "<":
          char += "&lt;";
          break;
        case ">":
          char += "&gt;";
          break;
        case " ":
          char += '<span class="nbsp">\u2007</span>';
          break;
        default:
          if (ch <= " ") {
            char += "&nbsp;";
          } else if (!(this.forceWidth || this.isCJK(ch))) {
            char += ch;
          } else {
            if (ch <= "~") {
              char += ch;
            } else if (this.isCJK(ch)) {
              char += "<span style=\"display: inline-block; width: " + (2 * this.charSize.width) + "px\">" + ch + "</span>";
            } else {
              char += "<span style=\"display: inline-block; width: " + this.charSize.width + "px\">" + ch + "</span>";
            }
          }
      }
      if (cursor) {
        char += "</span>";
      }
      return char;
    };

    Terminal.prototype.lineToDom = function(y, line, active) {
      var cursorX, eol, k, ref, results, x;
      if (active) {
        cursorX = this.x;
      }
      results = [];
      for (x = k = 0, ref = this.cols; 0 <= ref ? k <= ref : k >= ref; x = 0 <= ref ? ++k : --k) {
        if (x !== this.cols) {
          results.push(this.charToDom(line.chars[x], line.chars[x - 1], x === cursorX));
        } else {
          eol = '';
          if (!this.equalAttr(line.chars[x - 1], this.defAttr)) {
            eol += '</span>';
          }
          if (line.wrap) {
            eol += '\u23CE';
          }
          if (line.extra) {
            results.push(eol += "<span class=\"extra\">" + line.extra + "</span>");
          } else {
            results.push(void 0);
          }
        }
      }
      return results;
    };

    Terminal.prototype.screenToDom = function(force) {
      var active, div, k, len, line, ref, results, y;
      ref = this.screen;
      results = [];
      for (y = k = 0, len = ref.length; k < len; y = ++k) {
        line = ref[y];
        if (line.dirty || force) {
          active = y === this.y + this.shift && !this.cursorHidden;
          div = document.createElement('div');
          div.classList.add('line');
          if (active) {
            div.classList.add('active');
          }
          if (line.extra) {
            div.classList.add('extended');
          }
          div.innerHTML = (this.lineToDom(y, line, active)).join('');
          if (active) {
            this.active = div;
            this.cursor = div.querySelectorAll('.cursor')[0];
          }
          results.push(div);
        } else {
          results.push(void 0);
        }
      }
      return results;
    };

    Terminal.prototype.writeDom = function(dom) {
      var frag, k, len, line, r, y;
      r = Math.max(this.term.childElementCount - this.rows, 0);
      for (y = k = 0, len = dom.length; k < len; y = ++k) {
        line = dom[y];
        if (!line) {
          continue;
        }
        this.screen[y].dirty = false;
        if (y < this.rows && y < this.term.childElementCount) {
          this.term.replaceChild(line, this.term.childNodes[r + y]);
        } else {
          frag = frag || document.createDocumentFragment('fragment');
          frag.appendChild(line);
        }
        this.emit('change', line);
      }
      frag && this.term.appendChild(frag);
      this.shift = 0;
      return this.screen = this.screen.slice(-this.rows);
    };

    Terminal.prototype.refresh = function(force) {
      var dom, ref;
      if (force == null) {
        force = false;
      }
      if (this.active != null) {
        this.active.classList.remove('active');
      }
      if (this.cursor) {
        if ((ref = this.cursor.parentNode) != null) {
          ref.replaceChild(this.document.createTextNode(this.cursor.textContent), this.cursor);
        }
      }
      dom = this.screenToDom(force);
      this.writeDom(dom);
      this.nativeScrollTo();
      this.updateInputViews();
      return this.emit('refresh');
    };

    Terminal.prototype._cursorBlink = function() {
      this.cursorState ^= 1;
      if (!this.cursor) {
        return;
      }
      if (this.cursor.classList.contains("reverse-video")) {
        return this.cursor.classList.remove("reverse-video");
      } else {
        return this.cursor.classList.add("reverse-video");
      }
    };

    Terminal.prototype.showCursor = function() {
      if (!this.cursorState) {
        this.cursorState = 1;
        this.screen[this.y + this.shift].dirty = true;
        return this.refresh();
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
      var i, k, ref, ref1, results;
      if (this.normal || this.scrollTop !== 0 || this.scrollBottom !== this.rows - 1) {
        this.screen.splice(this.shift + this.scrollBottom + 1, 0, this.blankLine());
        this.screen.splice(this.shift + this.scrollTop, 1);
        results = [];
        for (i = k = ref = this.scrollTop, ref1 = this.scrollBottom; ref <= ref1 ? k <= ref1 : k >= ref1; i = ref <= ref1 ? ++k : --k) {
          results.push(this.screen[i + this.shift].dirty = true);
        }
        return results;
      } else {
        this.screen.push(this.blankLine());
        return this.shift++;
      }
    };

    Terminal.prototype.unscroll = function() {
      var i, k, ref, ref1, results;
      this.screen.splice(this.shift + this.scrollTop, 0, this.blankLine(true));
      this.screen.splice(this.shift + this.scrollBottom + 1, 1);
      results = [];
      for (i = k = ref = this.scrollTop, ref1 = this.scrollBottom; ref <= ref1 ? k <= ref1 : k >= ref1; i = ref <= ref1 ? ++k : --k) {
        results.push(this.screen[i + this.shift].dirty = true);
      }
      return results;
    };

    Terminal.prototype.nativeScrollTo = function(scroll) {
      if (scroll == null) {
        scroll = 2000000000;
      }
      if (this.scrollLock) {
        return;
      }
      return window.scrollTo(0, scroll);
    };

    Terminal.prototype.scrollDisplay = function(disp) {
      return this.nativeScrollTo(window.scrollY + disp * this.charSize.height);
    };

    Terminal.prototype.nextLine = function() {
      this.y++;
      if (this.y > this.scrollBottom) {
        this.y--;
        return this.scroll();
      }
    };

    Terminal.prototype.prevLine = function() {
      this.y--;
      if (this.y < this.scrollTop) {
        this.y++;
        return this.unscroll();
      }
    };

    Terminal.prototype.write = function(data) {
      var attr, b64, c, ch, content, cs, i, k, l, len, line, m, mime, num, pt, ref, ref1, ref2, ref3, safe, type, valid, x, y;
      i = 0;
      l = data.length;
      while (i < l) {
        ch = data.charAt(i);
        switch (this.state) {
          case State.normal:
            switch (ch) {
              case "\x07":
                this.bell();
                break;
              case "\n":
              case "\x0b":
              case "\x0c":
                if (this.horizontalWrap) {
                  this.screen[this.y + this.shift].extra += ch;
                } else {
                  this.screen[this.y + this.shift].dirty = true;
                  this.nextLine();
                }
                break;
              case "\r":
                if (!this.horizontalWrap) {
                  this.x = 0;
                }
                break;
              case "\b":
                if (this.x >= this.cols) {
                  this.x--;
                }
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
                if (("\u0300" <= ch && ch <= "\u036F") || ("\u1AB0" <= ch && ch <= "\u1AFF") || ("\u1DC0" <= ch && ch <= "\u1DFF") || ("\u20D0" <= ch && ch <= "\u20FF") || ("\uFE20" <= ch && ch <= "\uFE2F")) {
                  x = this.x;
                  y = this.y + this.shift;
                  if (this.x > 0) {
                    x -= 1;
                  } else if (this.y > 0) {
                    y -= 1;
                    x = this.cols - 1;
                  } else {
                    break;
                  }
                  this.screen[y].chars[x].ch += ch;
                  break;
                }
                if (ch >= " ") {
                  if ((ref = this.charset) != null ? ref[ch] : void 0) {
                    ch = this.charset[ch];
                  }
                  if (this.x >= this.cols) {
                    if (this.horizontalWrap) {
                      this.screen[this.y + this.shift].extra += ch;
                    } else {
                      if (this.autowrap) {
                        this.screen[this.y + this.shift].wrap = true;
                        this.nextLine();
                      }
                      this.x = 0;
                    }
                  }
                  this.putChar(ch);
                  this.x++;
                  if (this.isCJK(ch)) {
                    this.putChar(" ", true);
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
                this.clearScrollback();
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
                num = data.charAt(i);
                switch (num) {
                  case "3":
                    break;
                  case "4":
                    break;
                  case "5":
                    break;
                  case "6":
                    break;
                  case "8":
                    ref1 = this.screen;
                    for (k = 0, len = ref1.length; k < len; k++) {
                      line = ref1[k];
                      line.dirty = true;
                      for (c = m = 0, ref2 = line.chars.length; 0 <= ref2 ? m <= ref2 : m >= ref2; c = 0 <= ref2 ? ++m : --m) {
                        line.chars[c] = this.cloneAttr(this.curAttr, "E");
                      }
                    }
                    this.x = this.y = 0;
                }
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
            if (ch <= " " || ch >= "~") {
              if (ch === '\b') {
                this.currentParam = (this.currentParam / 10) & 1;
              }
              if (ch === '\r') {
                this.x = 0;
              }
              if (["\n", "\x0b", "\x0c"].indexOf(ch) >= 0) {
                this.screen[this.y + this.shift].dirty = true;
                this.nextLine();
              }
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
                this.deviceStatus(this.params);
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
                console.error("Unknown CSI code: %s (%d).", ch, ch.charCodeAt(0));
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
                  pt = this.currentParam;
                  if (pt[0] !== ';') {
                    console.error("Unknown DECUDK: " + pt);
                    break;
                  }
                  pt = pt.slice(1);
                  ref3 = pt.split('|', 2), type = ref3[0], content = ref3[1];
                  if (!content) {
                    console.error("No type for inline DECUDK: " + pt);
                    break;
                  }
                  switch (type) {
                    case "HTML":
                      safe = html_sanitize(content, function(l) {
                        return l;
                      });
                      attr = this.cloneAttr(this.curAttr);
                      attr.html = "<div class=\"inline-html\">" + safe + "</div>";
                      this.screen[this.y + this.shift].chars[this.x] = attr;
                      this.resetLine(this.screen[this.y + this.shift]);
                      this.nextLine();
                      break;
                    case "IMAGE":
                      content = encodeURI(content);
                      if (content.indexOf(';')) {
                        mime = content.slice(0, content.indexOf(';'));
                        b64 = content.slice(content.indexOf(';') + 1);
                      } else {
                        mime = 'image';
                        b64 = content;
                      }
                      attr = this.cloneAttr(this.curAttr);
                      attr.html = "<img class=\"inline-image\" src=\"data:" + mime + ";base64," + b64 + "\" />";
                      this.screen[this.y + this.shift].chars[this.x] = attr;
                      this.resetLine(this.screen[this.y + this.shift]);
                      break;
                    case "PROMPT":
                      this.send(content);
                      break;
                    case "TEXT":
                      l += content.length;
                      data = data.slice(0, i + 1) + content + data.slice(i + 1);
                      break;
                    default:
                      console.error("Unknown type " + type + " for DECUDK");
                  }
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
      this.screen[this.y + this.shift].dirty = true;
      return this.refresh();
    };

    Terminal.prototype.writeln = function(data) {
      return this.write(data + "\r\n");
    };

    Terminal.prototype.updateInputViews = function() {
      var cursorPos;
      cursorPos = this.cursor.getBoundingClientRect();
      this.inputView.style['left'] = cursorPos.left + "px";
      this.inputView.style['top'] = cursorPos.top + "px";
      this.inputHelper.style['left'] = cursorPos.left + "px";
      this.inputHelper.style['top'] = cursorPos.top + "px";
      return this.inputHelper.value = "";
    };

    Terminal.prototype.compositionStart = function(ev) {
      ev.preventDefault();
      ev.stopPropagation();
      this.updateInputViews();
      this.inputView.className = "";
      this.inputView.innerText = "";
      this.cursor.style['visibility'] = "hidden";
      this.inComposition = true;
      this.compositionText = "";
      return false;
    };

    Terminal.prototype.compositionUpdate = function(ev) {
      ev.preventDefault();
      ev.stopPropagation();
      this.compositionText = ev.data;
      this.inputView.innerText = this.compositionText;
      return false;
    };

    Terminal.prototype.compositionEnd = function(ev) {
      ev.preventDefault();
      ev.stopPropagation();
      this.finishComposition();
      return false;
    };

    Terminal.prototype.finishComposition = function() {
      this.inComposition = false;
      this.showCursor();
      this.inputHelper.value = "";
      this.inputView.className = "hidden";
      this.send(this.compositionText);
      this.compositionText = "";
      return this.inputHelper.focus();
    };

    Terminal.prototype.keyDown = function(ev) {
      var key, ref;
      if (this.inComposition) {
        if (ev.keyCode === 229) {
          return false;
        } else if (ev.keyCode === 16 || ev.keyCode === 17 || ev.keyCode === 18) {
          return false;
        }
        this.finishComposition();
      }
      if (ev.keyCode === 229) {
        ev.preventDefault();
        ev.stopPropagation();
        setTimeout((function(_this) {
          return function() {
            var char, e, val;
            if (!(_this.inComposition || _this.inputHelper.value.length > 1)) {
              val = _this.inputHelper.value;
              _this.inputHelper.value = "";
              char = val.toUpperCase().charCodeAt(0);
              if ((65 <= char && char <= 90)) {
                e = new KeyboardEvent('keydown', {
                  keyCode: char
                });
                if (window.mobileKeydown(e)) {
                  return;
                }
              }
              return _this.send(val);
            }
          };
        })(this), 0);
        return false;
      }
      if (ev.keyCode > 15 && ev.keyCode < 19) {
        return true;
      }
      if (window.mobileKeydown(ev)) {
        return true;
      }
      if (ev.keyCode === 19) {
        this.body.classList.add('stopped');
        this.out('\x03');
        this.ws.shell.close();
        return false;
      }
      if ((ev.shiftKey || ev.ctrlKey) && ev.keyCode === 45) {
        return true;
      }
      if ((ev.shiftKey && ev.ctrlKey) && ((ref = ev.keyCode) === 67 || ref === 86)) {
        this.body.contentEditable = true;
        return true;
      }
      if (ev.altKey && ev.keyCode === 90 && !this.skipNextKey) {
        this.skipNextKey = true;
        this.body.classList.add('skip');
        return cancel(ev);
      }
      if (this.skipNextKey) {
        this.skipNextKey = false;
        this.body.classList.remove('skip');
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
            this.scrollDisplay(-1);
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
            this.scrollDisplay(1);
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
          key = "\x1b[H";
          break;
        case 35:
          if (this.applicationKeypad) {
            key = "\x1bOF";
            break;
          }
          key = "\x1b[F";
          break;
        case 33:
          if (ev.shiftKey) {
            if (ev.ctrlKey) {
              break;
            }
            this.scrollDisplay(-(this.rows - 1));
            return cancel(ev);
          } else {
            key = "\x1b[5~";
          }
          break;
        case 34:
          if (ev.shiftKey) {
            if (ev.ctrlKey) {
              break;
            }
            this.scrollDisplay(this.rows - 1);
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
        case 145:
          this.scrollLock = !this.scrollLock;
          if (this.scrollLock) {
            this.body.classList.add('locked');
          } else {
            this.body.classList.remove('locked');
          }
          return cancel(ev);
        default:
          if (ev.ctrlKey) {
            if (ev.keyCode >= 65 && ev.keyCode <= 90) {
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
          } else if ((ev.altKey && indexOf.call(navigator.platform, 'Mac') < 0) || (ev.metaKey && indexOf.call(navigator.platform, 'Mac') >= 0)) {
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
      this.showCursor();
      this.send(key);
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
      var key, ref;
      if (this.skipNextKey === false) {
        this.skipNextKey = null;
        return true;
      }
      if (ev.keyCode > 15 && ev.keyCode < 19) {
        return true;
      }
      if ((ev.shiftKey || ev.ctrlKey) && ev.keyCode === 45) {
        return true;
      }
      if ((ev.shiftKey && ev.ctrlKey) && ((ref = ev.keyCode) === 67 || ref === 86)) {
        return true;
      }
      cancel(ev);
      if (ev.charCode) {
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
      this.send(key);
      return false;
    };

    Terminal.prototype.bell = function(cls) {
      if (cls == null) {
        cls = "bell";
      }
      if (!this.visualBell) {
        return;
      }
      this.body.classList.add(cls);
      return this.t_bell = setTimeout(((function(_this) {
        return function() {
          return _this.body.classList.remove(cls);
        };
      })(this)), this.visualBell);
    };

    Terminal.prototype.resize = function(x, y, notif) {
      var h, insert, k, len, len1, len2, len3, line, m, n, o, oldCols, oldRows, ref, ref1, ref2, ref3, w;
      if (x == null) {
        x = null;
      }
      if (y == null) {
        y = null;
      }
      if (notif == null) {
        notif = false;
      }
      oldCols = this.cols;
      oldRows = this.rows;
      this.computeCharSize();
      w = this.body.clientWidth;
      h = this.html.clientHeight;
      if (this.charSize.width === 0 || this.charSize.height === 0) {
        console.error('Null size in refresh');
        return;
      }
      this.cols = x || Math.floor(w / this.charSize.width);
      this.rows = y || Math.floor(h / this.charSize.height);
      this.cols = Math.max(1, this.cols);
      this.rows = Math.max(1, this.rows);
      this.nativeScrollTo();
      if ((!x && !y) && oldCols === this.cols && oldRows === this.rows) {
        return;
      }
      if (!notif) {
        this.ctl(JSON.stringify({
          cmd: 'size',
          cols: this.cols,
          rows: this.rows
        }));
      }
      if (this.cols > oldCols) {
        ref = this.screen;
        for (k = 0, len = ref.length; k < len; k++) {
          line = ref[k];
          while (line.chars.length < this.cols) {
            line.chars.push(this.defAttr);
          }
          line.wrap = false;
        }
        if (this.normal) {
          ref1 = this.normal.screen;
          for (m = 0, len1 = ref1.length; m < len1; m++) {
            line = ref1[m];
            while (line.chars.length < this.cols) {
              line.chars.push(this.defAttr);
            }
            line.wrap = false;
          }
        }
      } else if (this.cols < oldCols) {
        ref2 = this.screen;
        for (n = 0, len2 = ref2.length; n < len2; n++) {
          line = ref2[n];
          while (line.chars.length > this.cols) {
            line.chars.pop();
          }
        }
        if (this.normal) {
          ref3 = this.normal.screen;
          for (o = 0, len3 = ref3.length; o < len3; o++) {
            line = ref3[o];
            while (line.chars.length > this.cols) {
              line.chars.pop();
            }
          }
        }
      }
      this.setupStops(oldCols);
      if (this.term.childElementCount >= this.rows) {
        this.y += this.rows - oldRows;
        insert = 'unshift';
      } else {
        insert = 'push';
      }
      while (this.screen.length > this.rows) {
        this.screen.shift();
      }
      while (this.screen.length < this.rows) {
        this.screen[insert](this.blankLine(false, false));
      }
      if (this.normal) {
        while (this.normal.screen.length > this.rows) {
          this.normal.screen.shift();
        }
        while (this.normal.screen.length < this.rows) {
          this.normal.screen[insert](this.blankLine(false, false));
        }
      }
      if (this.y >= this.rows) {
        this.y = this.rows - 1;
      }
      if (this.y < 0) {
        this.y = 0;
      }
      if (this.x >= this.cols) {
        this.x = this.cols - 1;
      }
      this.scrollTop = 0;
      this.scrollBottom = this.rows - 1;
      this.refresh();
      if (!notif && (x || y)) {
        return this.reset();
      }
    };

    Terminal.prototype.resizeWindowPlease = function(cols) {
      var margin, width;
      margin = window.innerWidth - this.body.clientWidth;
      width = cols * this.charSize.width + margin;
      return resizeTo(width, window.innerHeight);
    };

    Terminal.prototype.setupStops = function(i) {
      var results;
      if (i != null) {
        if (!this.tabs[i]) {
          i = this.prevStop(i);
        }
      } else {
        this.tabs = {};
        i = 0;
      }
      results = [];
      while (i < this.cols) {
        this.tabs[i] = true;
        results.push(i += 8);
      }
      return results;
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
      var line;
      line = this.screen[y + this.shift].chars;
      while (x < this.cols) {
        line[x] = this.eraseAttr();
        x++;
      }
      return this.resetLine(this.screen[y + this.shift]);
    };

    Terminal.prototype.eraseLeft = function(x, y) {
      x++;
      while (x--) {
        this.screen[y + this.shift].chars[x] = this.eraseAttr();
      }
      return this.resetLine(this.screen[y + this.shift]);
    };

    Terminal.prototype.eraseLine = function(y) {
      return this.eraseRight(0, y);
    };

    Terminal.prototype.resetLine = function(l) {
      l.dirty = true;
      l.wrap = false;
      return l.extra = '';
    };

    Terminal.prototype.blankLine = function(cur, dirty) {
      var attr, i, line;
      if (cur == null) {
        cur = false;
      }
      if (dirty == null) {
        dirty = true;
      }
      attr = (cur ? this.eraseAttr() : this.defAttr);
      line = [];
      i = 0;
      while (i < this.cols) {
        line[i] = attr;
        i++;
      }
      return {
        chars: line,
        dirty: dirty,
        wrap: false,
        extra: ''
      };
    };

    Terminal.prototype.ch = function(cur) {
      if (cur) {
        return this.eraseAttr();
      } else {
        return this.defAttr;
      }
    };

    Terminal.prototype.isterm = function(term) {
      return ("" + this.termName).indexOf(term) === 0;
    };

    Terminal.prototype.send = function(data) {
      return this.out(data);
    };

    Terminal.prototype.handleTitle = function(title) {
      return document.title = title;
    };

    Terminal.prototype.index = function() {
      this.nextLine();
      return this.state = State.normal;
    };

    Terminal.prototype.reverseIndex = function() {
      this.prevLine();
      return this.state = State.normal;
    };

    Terminal.prototype.reset = function() {
      this.resetVars();
      return this.refresh(true);
    };

    Terminal.prototype.clearScrollback = function() {
      while (this.term.childElementCount > this.rows) {
        this.term.firstChild.remove();
      }
      return this.emit('clear');
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
      return this.y = row + (this.originMode ? this.scrollTop : 0);
    };

    Terminal.prototype.eraseInDisplay = function(params) {
      var j, results, results1, results2;
      switch (params[0]) {
        case 0:
          this.eraseRight(this.x, this.y);
          j = this.y + 1;
          results = [];
          while (j < this.rows) {
            this.eraseLine(j);
            results.push(j++);
          }
          return results;
          break;
        case 1:
          this.eraseLeft(this.x, this.y);
          j = this.y;
          results1 = [];
          while (j--) {
            results1.push(this.eraseLine(j));
          }
          return results1;
          break;
        case 2:
          j = this.rows;
          results2 = [];
          while (j--) {
            results2.push(this.eraseLine(j));
          }
          return results2;
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
      var i, l, p, results;
      if (params.length === 1 && params[0] === 0) {
        this.curAttr = this.cloneAttr(this.defAttr);
        return;
      }
      l = params.length;
      i = 0;
      results = [];
      while (i < l) {
        p = params[i];
        if (p >= 30 && p <= 37) {
          this.curAttr.fg = p - 30;
        } else if (p >= 40 && p <= 47) {
          this.curAttr.bg = p - 40;
        } else if (p >= 90 && p <= 97) {
          p += 8;
          this.curAttr.fg = p - 90;
        } else if (p >= 100 && p <= 107) {
          p += 8;
          this.curAttr.bg = p - 100;
        } else if (p === 0) {
          this.curAttr = this.cloneAttr(this.defAttr);
        } else if (p === 1) {
          this.curAttr.bold = true;
        } else if (p === 2) {
          this.curAttr.faint = true;
        } else if (p === 3) {
          this.curAttr.italic = true;
        } else if (p === 4) {
          this.curAttr.underline = true;
        } else if (p === 5) {
          this.curAttr.blink = 1;
        } else if (p === 6) {
          this.curAttr.blink = 2;
        } else if (p === 7) {
          this.curAttr.inverse = true;
        } else if (p === 8) {
          this.curAttr.invisible = true;
        } else if (p === 9) {
          this.curAttr.crossed = true;
        } else if (p === 10) {
          void 0;
        } else if (p === 21) {
          this.curAttr.bold = false;
        } else if (p === 22) {
          this.curAttr.bold = false;
          this.curAttr.faint = false;
        } else if (p === 23) {
          this.curAttr.italic = false;
        } else if (p === 24) {
          this.curAttr.underline = false;
        } else if (p === 25) {
          this.curAttr.blink = false;
        } else if (p === 27) {
          this.curAttr.inverse = false;
        } else if (p === 28) {
          this.curAttr.invisible = false;
        } else if (p === 29) {
          this.curAttr.crossed = false;
        } else if (p === 39) {
          this.curAttr.fg = 257;
        } else if (p === 49) {
          this.curAttr.bg = 256;
        } else if (p === 38) {
          if (params[i + 1] === 2) {
            i += 2;
            this.curAttr.fg = "rgb(" + params[i] + ", " + params[i + 1] + ", " + params[i + 2] + ")";
            i += 2;
          } else if (params[i + 1] === 5) {
            i += 2;
            this.curAttr.fg = params[i] & 0xff;
          }
        } else if (p === 48) {
          if (params[i + 1] === 2) {
            i += 2;
            this.curAttr.bg = "rgb(" + params[i] + ", " + params[i + 1] + ", " + params[i + 2] + ")";
            i += 2;
          } else if (params[i + 1] === 5) {
            i += 2;
            this.curAttr.bg = params[i] & 0xff;
          }
        } else if (p === 100) {
          this.curAttr.fg = 257;
          this.curAttr.bg = 256;
        } else {
          console.error("Unknown SGR attribute: %d.", p);
        }
        results.push(i++);
      }
      return results;
    };

    Terminal.prototype.deviceStatus = function(params) {
      var ref, ref1;
      if (!this.prefix) {
        switch (params[0]) {
          case 5:
            return this.send("\x1b[0n");
          case 6:
            return this.send("\x1b[" + (this.y + 1) + ";" + (this.x + 1) + "R");
        }
      } else if (this.prefix === "?") {
        if (params[0] === 6) {
          this.send("\x1b[?" + (this.y + 1) + ";" + (this.x + 1) + "R");
        }
        if (params[0] === 99) {
          if (((ref = navigator.geolocation) != null ? ref.getCurrentPosition : void 0) == null) {
            this.send('\x1b[?R');
            return;
          }
          return (ref1 = navigator.geolocation) != null ? ref1.getCurrentPosition((function(_this) {
            return function(position) {
              return _this.send("\x1b[?" + position.coords.latitude + ";" + position.coords.longitude + "R");
            };
          })(this), (function(_this) {
            return function(error) {
              return _this.send('\x1b[?R');
            };
          })(this)) : void 0;
        }
      }
    };

    Terminal.prototype.insertChars = function(params) {
      var j, param, row;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      row = this.y;
      j = this.x;
      while (param-- && j < this.cols) {
        this.screen[row + this.shift].chars.splice(j++, 0, [this.eraseAttr(), true]);
        this.screen[row + this.shift].chars.pop();
      }
      return this.screen[row + this.shift].dirty = true;
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
      var i, k, param, ref, ref1, results;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      while (param--) {
        this.screen.splice(this.y + this.shift, 0, this.blankLine(true));
        this.screen.splice(this.scrollBottom + 1 + this.shift, 1);
      }
      results = [];
      for (i = k = ref = this.y + this.shift, ref1 = this.screen.length - 1; ref <= ref1 ? k <= ref1 : k >= ref1; i = ref <= ref1 ? ++k : --k) {
        results.push(this.screen[i].dirty = true);
      }
      return results;
    };

    Terminal.prototype.deleteLines = function(params) {
      var i, k, node, param, ref, ref1, results;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      while (param--) {
        this.screen.splice(this.scrollBottom + this.shift, 0, this.blankLine(true));
        this.screen.splice(this.y + this.shift, 1);
        if (!(this.normal || this.scrollTop !== 0 || this.scrollBottom !== this.rows - 1)) {
          node = this.term.childElementCount - this.rows + this.y + this.shift;
          this.term.childNodes[node].remove();
        }
      }
      if (this.normal || this.scrollTop !== 0 || this.scrollBottom !== this.rows - 1) {
        results = [];
        for (i = k = ref = this.y + this.shift, ref1 = this.screen.length - 1; ref <= ref1 ? k <= ref1 : k >= ref1; i = ref <= ref1 ? ++k : --k) {
          results.push(this.screen[i].dirty = true);
        }
        return results;
      }
    };

    Terminal.prototype.deleteChars = function(params) {
      var param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      while (param--) {
        this.screen[this.y + this.shift].chars.splice(this.x, 1);
        this.screen[this.y + this.shift].chars.push(this.eraseAttr());
      }
      return this.resetLine(this.screen[this.y + this.shift]);
    };

    Terminal.prototype.eraseChars = function(params) {
      var j, param;
      param = params[0];
      if (param < 1) {
        param = 1;
      }
      j = this.x;
      while (param-- && j < this.cols) {
        this.screen[this.y + this.shift].chars[j++] = this.eraseAttr();
      }
      return this.resetLine(this.screen[this.y + this.shift]);
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
      if (!this.prefix) {
        switch (params) {
          case 4:
            this.insertMode = true;
            break;
          case 20:
            this.convertEol = true;
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
            this.resize(132, this.rows);
            this.resizeWindowPlease(132);
            return this.reset();
          case 6:
            return this.originMode = true;
          case 7:
            return this.autowrap = true;
          case 66:
            return this.applicationKeypad = true;
          case 77:
            return this.horizontalWrap = true;
          case 9:
          case 1000:
          case 1002:
          case 1003:
            this.x10Mouse = params === 9;
            this.vt200Mouse = params === 1000;
            this.normalMouse = params > 1000;
            this.mouseEvents = true;
            return this.body.style.cursor = 'pointer';
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
                screen: this.screen,
                x: this.x,
                y: this.y,
                shift: this.shift,
                scrollTop: this.scrollTop,
                scrollBottom: this.scrollBottom,
                tabs: this.tabs,
                curAttr: this.curAttr
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
      if (!this.prefix) {
        switch (params) {
          case 4:
            this.insertMode = false;
            break;
          case 20:
            this.convertEol = false;
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
            this.resizeWindowPlease(80);
            this.reset();
            return delete this.savedCols;
          case 6:
            return this.originMode = false;
          case 7:
            return this.autowrap = false;
          case 66:
            return this.applicationKeypad = false;
          case 77:
            return this.horizontalWrap = false;
          case 9:
          case 1000:
          case 1002:
          case 1003:
            this.x10Mouse = false;
            this.vt200Mouse = false;
            this.normalMouse = false;
            this.mouseEvents = false;
            return this.body.style.cursor = "";
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
              this.screen = this.normal.screen;
              this.x = this.normal.x;
              this.y = this.normal.y;
              this.shift = this.normal.shift;
              this.scrollTop = this.normal.scrollTop;
              this.scrollBottom = this.normal.scrollBottom;
              this.tabs = this.normal.tabs;
              this.curAttr = this.normal.curAttr;
              this.normal = null;
              this.refresh(true);
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
      var param, results;
      param = params[0] || 1;
      results = [];
      while (param--) {
        results.push(this.x = this.nextStop());
      }
      return results;
    };

    Terminal.prototype.scrollUp = function(params) {
      var i, k, param, ref, ref1, results;
      param = params[0] || 1;
      while (param--) {
        this.screen.splice(this.scrollTop, 1);
        this.screen.splice(this.scrollBottom, 0, this.blankLine());
      }
      results = [];
      for (i = k = ref = this.scrollTop, ref1 = this.scrollBottom; ref <= ref1 ? k <= ref1 : k >= ref1; i = ref <= ref1 ? ++k : --k) {
        results.push(this.screen[i + this.shift].dirty = true);
      }
      return results;
    };

    Terminal.prototype.scrollDown = function(params) {
      var i, k, param, ref, ref1, results;
      param = params[0] || 1;
      while (param--) {
        this.screen.splice(this.scrollBottom, 1);
        this.screen.splice(this.scrollTop, 0, this.blankLine());
      }
      results = [];
      for (i = k = ref = this.scrollTop, ref1 = this.scrollBottom; ref <= ref1 ? k <= ref1 : k >= ref1; i = ref <= ref1 ? ++k : --k) {
        results.push(this.screen[i + this.shift].dirty = true);
      }
      return results;
    };

    Terminal.prototype.initMouseTracking = function(params) {};

    Terminal.prototype.resetTitleModes = function(params) {};

    Terminal.prototype.cursorBackwardTab = function(params) {
      var param, results;
      param = params[0] || 1;
      results = [];
      while (param--) {
        results.push(this.x = this.prevStop());
      }
      return results;
    };

    Terminal.prototype.repeatPrecedingCharacter = function(params) {
      var ch, line, param;
      param = params[0] || 1;
      line = this.screen[this.y + this.shift].chars;
      ch = line[this.x - 1] || this.defAttr;
      while (param--) {
        line[this.x++] = ch;
      }
      return this.screen[this.y + this.shift].dirty = true;
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
      this.autowrap = true;
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
      var attr, b, i, l, line, r, results, t;
      t = params[0];
      l = params[1];
      b = params[2];
      r = params[3];
      attr = params[4];
      results = [];
      while (t < b + 1) {
        line = this.screen[t + this.shift].chars;
        this.screen[t + this.shift].dirty = true;
        i = l;
        while (i < r) {
          line[i] = this.cloneAttr(attr, line[i].ch);
          i++;
        }
        results.push(t++);
      }
      return results;
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
      var b, ch, i, l, line, r, results, t;
      ch = params[0];
      t = params[1];
      l = params[2];
      b = params[3];
      r = params[4];
      results = [];
      while (t < b + 1) {
        line = this.screen[t + this.shift].chars;
        this.screen[t + this.shift].dirty = true;
        i = l;
        while (i < r) {
          line[i] = this.cloneAttr(line[i][0], String.fromCharCode(ch));
          i++;
        }
        results.push(t++);
      }
      return results;
    };

    Terminal.prototype.enableLocatorReporting = function(params) {
      var val;
      return val = params[0] > 0;
    };

    Terminal.prototype.eraseRectangle = function(params) {
      var b, i, l, line, r, results, t;
      t = params[0];
      l = params[1];
      b = params[2];
      r = params[3];
      results = [];
      while (t < b + 1) {
        line = this.screen[t + this.shift].chars;
        this.screen[t + this.shift].dirty = true;
        i = l;
        while (i < r) {
          line[i] = this.eraseAttr();
          i++;
        }
        results.push(t++);
      }
      return results;
    };

    Terminal.prototype.setLocatorEvents = function(params) {};

    Terminal.prototype.selectiveEraseRectangle = function(params) {};

    Terminal.prototype.requestLocatorPosition = function(params) {};

    Terminal.prototype.insertColumns = function() {
      var i, l, param, results;
      param = params[0];
      l = this.rows + this.shift;
      results = [];
      while (param--) {
        i = this.shift;
        results.push((function() {
          var results1;
          results1 = [];
          while (i < l) {
            this.screen[i].chars.splice(this.x + 1, 0, this.eraseAttr());
            this.screen[i].chars.pop();
            this.screen[i].dirty = true;
            results1.push(i++);
          }
          return results1;
        }).call(this));
      }
      return results;
    };

    Terminal.prototype.deleteColumns = function() {
      var i, l, param, results;
      param = params[0];
      l = this.rows + this.shift;
      results = [];
      while (param--) {
        i = this.shift;
        results.push((function() {
          var results1;
          results1 = [];
          while (i < l) {
            this.screen[i].chars.splice(this.x, 1);
            this.screen[i].chars.push(this.eraseAttr());
            this.resetLine(this.screen[i].dirty);
            results1.push(i++);
          }
          return results1;
        }).call(this));
      }
      return results;
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
