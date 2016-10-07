(function() {
  var Popup, Selection, _set_theme_href, _theme, alt, cancel, clean_ansi, copy, ctrl, first, linkify, nextLeaf, popup, previousLeaf, selection, setAlarm, virtualInput, walk,
    indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  clean_ansi = function(data) {
    var c, i, out, state;
    if (data.indexOf('\x1b') < 0) {
      return data;
    }
    i = -1;
    out = '';
    state = 'normal';
    while (i < data.length - 1) {
      c = data.charAt(++i);
      switch (state) {
        case 'normal':
          if (c === '\x1b') {
            state = 'escaped';
            break;
          }
          out += c;
          break;
        case 'escaped':
          if (c === '[') {
            state = 'csi';
            break;
          }
          if (c === ']') {
            state = 'osc';
            break;
          }
          if ('#()%*+-./'.indexOf(c) >= 0) {
            i++;
          }
          state = 'normal';
          break;
        case 'csi':
          if ("?>!$\" '".indexOf(c) >= 0) {
            break;
          }
          if (('0' <= c && c <= '9')) {
            break;
          }
          if (c === ';') {
            break;
          }
          state = 'normal';
          break;
        case 'osc':
          if (c === "\x1b" || c === "\x07") {
            if (c === "\x1b") {
              i++;
            }
            state = 'normal';
          }
      }
    }
    return out;
  };

  setAlarm = function(notification, cond) {
    var alarm;
    alarm = function(data) {
      var message, note, notif;
      message = clean_ansi(data.data.slice(1));
      if (cond !== null && !cond.test(message)) {
        return;
      }
      butterfly.body.classList.remove('alarm');
      note = "Butterfly [" + butterfly.title + "]";
      if (notification) {
        notif = new Notification(note, {
          body: message,
          icon: '/static/images/favicon.png'
        });
        notif.onclick = function() {
          window.focus();
          return notif.close();
        };
      } else {
        alert(note + '\n' + message);
      }
      return butterfly.ws.removeEventListener('message', alarm);
    };
    butterfly.ws.addEventListener('message', alarm);
    return butterfly.body.classList.add('alarm');
  };

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

  document.addEventListener('keydown', function(e) {
    var cond;
    if (!(e.altKey && e.keyCode === 65)) {
      return true;
    }
    cond = null;
    if (e.shiftKey) {
      cond = prompt('Ring alarm when encountering the following text: (can be a regexp)');
      if (!cond) {
        return;
      }
      cond = new RegExp(cond);
    }
    if (Notification && Notification.permission === 'default') {
      Notification.requestPermission(function() {
        return setAlarm(Notification.permission === 'granted', cond);
      });
    } else {
      setAlarm(Notification.permission === 'granted', cond);
    }
    return cancel(e);
  });

  addEventListener('copy', copy = function(e) {
    var data, end, j, len1, line, ref, sel;
    butterfly.bell("copied");
    e.clipboardData.clearData();
    sel = getSelection().toString().replace(/\u00A0/g, ' ').replace(/\u2007/g, ' ');
    data = '';
    ref = sel.split('\n');
    for (j = 0, len1 = ref.length; j < len1; j++) {
      line = ref[j];
      if (line.slice(-1) === '\u23CE') {
        end = '';
        line = line.slice(0, -1);
      } else {
        end = '\n';
      }
      data += line.replace(/\s*$/, '') + end;
    }
    e.clipboardData.setData('text/plain', data.slice(0, -1));
    return e.preventDefault();
  });

  addEventListener('paste', function(e) {
    var data, send, size;
    butterfly.bell("pasted");
    data = e.clipboardData.getData('text/plain');
    data = data.replace(/\r\n/g, '\n').replace(/\n/g, '\r');
    size = 1024;
    send = function() {
      butterfly.send(data.substring(0, size));
      data = data.substring(size);
      if (data.length) {
        return setTimeout(send, 25);
      }
    };
    send();
    return e.preventDefault();
  });

  addEventListener('beforeunload', function(e) {
    if (!(butterfly.body.classList.contains('dead') || location.href.indexOf('session') > -1)) {
      return e.returnValue = 'This terminal is active and not in session. Are you sure you want to kill it?';
    }
  });

  Terminal.on('change', function(lines) {
    var j, len1, line, results;
    results = [];
    for (j = 0, len1 = lines.length; j < len1; j++) {
      line = lines[j];
      if (indexOf.call(line.classList, 'extended') >= 0) {
        results.push(line.addEventListener('click', (function(line) {
          return function() {
            var after, before;
            if (indexOf.call(line.classList, 'expanded') >= 0) {
              return line.classList.remove('expanded');
            } else {
              before = line.getBoundingClientRect().height;
              line.classList.add('expanded');
              after = line.getBoundingClientRect().height;
              return document.body.scrollTop += after - before;
            }
          };
        })(line)));
      } else {
        results.push(void 0);
      }
    }
    return results;
  });

  walk = function(node, callback) {
    var child, j, len1, ref, results;
    ref = node.childNodes;
    results = [];
    for (j = 0, len1 = ref.length; j < len1; j++) {
      child = ref[j];
      callback.call(child);
      results.push(walk(child, callback));
    }
    return results;
  };

  linkify = function(text) {
    var emailAddressPattern, pseudoUrlPattern, urlPattern;
    urlPattern = /\b(?:https?|ftp):\/\/[a-z0-9-+&@#\/%?=~_|!:,.;]*[a-z0-9-+&@#\/%=~_|]/gim;
    pseudoUrlPattern = /(^|[^\/])(www\.[\S]+(\b|$))/gim;
    emailAddressPattern = /[\w.]+@[a-zA-Z_-]+?(?:\.[a-zA-Z]{2,6})+/gim;
    return text.replace(urlPattern, '<a href="$&">$&</a>').replace(pseudoUrlPattern, '$1<a href="http://$2">$2</a>').replace(emailAddressPattern, '<a href="mailto:$&">$&</a>');
  };

  Terminal.on('change', function(lines) {
    var j, len1, line, results;
    results = [];
    for (j = 0, len1 = lines.length; j < len1; j++) {
      line = lines[j];
      results.push(walk(line, function() {
        var linkified, newNode;
        if (this.nodeType === 3) {
          linkified = linkify(this.nodeValue);
          if (linkified !== this.nodeValue) {
            newNode = document.createElement('span');
            newNode.innerHTML = linkified;
            this.parentElement.replaceChild(newNode, this);
            return true;
          }
        }
      }));
    }
    return results;
  });

  document.addEventListener('keydown', function(e) {
    if (!(e.altKey && e.keyCode === 79)) {
      return true;
    }
    open(location.href);
    return cancel(e);
  });

  Popup = (function() {
    function Popup() {
      this.el = document.getElementById('popup');
      this.bound_click_maybe_close = this.click_maybe_close.bind(this);
      this.bound_key_maybe_close = this.key_maybe_close.bind(this);
    }

    Popup.prototype.open = function(html) {
      this.el.innerHTML = html;
      this.el.classList.remove('hidden');
      if (typeof InstallTrigger !== "undefined") {
        document.body.contentEditable = 'false';
      }
      addEventListener('click', this.bound_click_maybe_close);
      return addEventListener('keydown', this.bound_key_maybe_close);
    };

    Popup.prototype.close = function() {
      removeEventListener('click', this.bound_click_maybe_close);
      removeEventListener('keydown', this.bound_key_maybe_close);
      if (typeof InstallTrigger !== "undefined") {
        document.body.contentEditable = 'true';
      }
      this.el.classList.add('hidden');
      return this.el.innerHTML = '';
    };

    Popup.prototype.click_maybe_close = function(e) {
      var t;
      t = e.target;
      while (t.parentElement) {
        if (Array.prototype.slice.call(this.el.children).indexOf(t) > -1) {
          return true;
        }
        t = t.parentElement;
      }
      this.close();
      return cancel(e);
    };

    Popup.prototype.key_maybe_close = function(e) {
      if (e.keyCode !== 27) {
        return true;
      }
      this.close();
      return cancel(e);
    };

    return Popup;

  })();

  popup = new Popup();

  selection = null;

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

  previousLeaf = function(node) {
    var previous;
    previous = node.previousSibling;
    if (!previous) {
      previous = node.parentNode.previousSibling;
    }
    if (!previous) {
      previous = node.parentNode.parentNode.previousSibling;
    }
    while (previous.lastChild) {
      previous = previous.lastChild;
    }
    return previous;
  };

  nextLeaf = function(node) {
    var next;
    next = node.nextSibling;
    if (!next) {
      next = node.parentNode.nextSibling;
    }
    if (!next) {
      next = node.parentNode.parentNode.nextSibling;
    }
    while (next != null ? next.firstChild : void 0) {
      next = next.firstChild;
    }
    return next;
  };

  Selection = (function() {
    function Selection() {
      butterfly.body.classList.add('selection');
      this.selection = getSelection();
    }

    Selection.prototype.reset = function() {
      var fakeRange, ref, results;
      this.selection = getSelection();
      fakeRange = document.createRange();
      fakeRange.setStart(this.selection.anchorNode, this.selection.anchorOffset);
      fakeRange.setEnd(this.selection.focusNode, this.selection.focusOffset);
      this.start = {
        node: this.selection.anchorNode,
        offset: this.selection.anchorOffset
      };
      this.end = {
        node: this.selection.focusNode,
        offset: this.selection.focusOffset
      };
      if (fakeRange.collapsed) {
        ref = [this.end, this.start], this.start = ref[0], this.end = ref[1];
      }
      this.startLine = this.start.node;
      while (!this.startLine.classList || indexOf.call(this.startLine.classList, 'line') < 0) {
        this.startLine = this.startLine.parentNode;
      }
      this.endLine = this.end.node;
      results = [];
      while (!this.endLine.classList || indexOf.call(this.endLine.classList, 'line') < 0) {
        results.push(this.endLine = this.endLine.parentNode);
      }
      return results;
    };

    Selection.prototype.clear = function() {
      return this.selection.removeAllRanges();
    };

    Selection.prototype.destroy = function() {
      butterfly.body.classList.remove('selection');
      return this.clear();
    };

    Selection.prototype.text = function() {
      return this.selection.toString().replace(/\u00A0/g, ' ').replace(/\u2007/g, ' ');
    };

    Selection.prototype.up = function() {
      return this.go(-1);
    };

    Selection.prototype.down = function() {
      return this.go(+1);
    };

    Selection.prototype.go = function(n) {
      var index;
      index = butterfly.children.indexOf(this.startLine) + n;
      if (!((0 <= index && index < butterfly.children.length))) {
        return;
      }
      while (!butterfly.children[index].textContent.match(/\S/)) {
        index += n;
        if (!((0 <= index && index < butterfly.children.length))) {
          return;
        }
      }
      return this.selectLine(index);
    };

    Selection.prototype.apply = function() {
      var range;
      this.clear();
      range = document.createRange();
      range.setStart(this.start.node, this.start.offset);
      range.setEnd(this.end.node, this.end.offset);
      return this.selection.addRange(range);
    };

    Selection.prototype.selectLine = function(index) {
      var line, lineEnd, lineStart;
      line = butterfly.children[index];
      lineStart = {
        node: line.firstChild,
        offset: 0
      };
      lineEnd = {
        node: line.lastChild,
        offset: line.lastChild.textContent.length
      };
      this.start = this.walk(lineStart, /\S/);
      return this.end = this.walk(lineEnd, /\S/, true);
    };

    Selection.prototype.collapsed = function(start, end) {
      var fakeRange;
      fakeRange = document.createRange();
      fakeRange.setStart(start.node, start.offset);
      fakeRange.setEnd(end.node, end.offset);
      return fakeRange.collapsed;
    };

    Selection.prototype.shrinkRight = function() {
      var end, node;
      node = this.walk(this.end, /\s/, true);
      end = this.walk(node, /\S/, true);
      if (!this.collapsed(this.start, end)) {
        return this.end = end;
      }
    };

    Selection.prototype.shrinkLeft = function() {
      var node, start;
      node = this.walk(this.start, /\s/);
      start = this.walk(node, /\S/);
      if (!this.collapsed(start, this.end)) {
        return this.start = start;
      }
    };

    Selection.prototype.expandRight = function() {
      var node;
      node = this.walk(this.end, /\S/);
      return this.end = this.walk(node, /\s/);
    };

    Selection.prototype.expandLeft = function() {
      var node;
      node = this.walk(this.start, /\S/, true);
      return this.start = this.walk(node, /\s/, true);
    };

    Selection.prototype.walk = function(needle, til, backward) {
      var i, node, text;
      if (backward == null) {
        backward = false;
      }
      if (needle.node.firstChild) {
        node = needle.node.firstChild;
      } else {
        node = needle.node;
      }
      text = node != null ? node.textContent : void 0;
      i = needle.offset;
      if (backward) {
        while (node) {
          while (i > 0) {
            if (text[--i].match(til)) {
              return {
                node: node,
                offset: i + 1
              };
            }
          }
          node = previousLeaf(node);
          text = node != null ? node.textContent : void 0;
          i = text.length;
        }
      } else {
        while (node) {
          while (i < text.length) {
            if (text[i++].match(til)) {
              return {
                node: node,
                offset: i - 1
              };
            }
          }
          node = nextLeaf(node);
          text = node != null ? node.textContent : void 0;
          i = 0;
        }
      }
      return needle;
    };

    return Selection;

  })();

  document.addEventListener('keydown', function(e) {
    var ref, ref1;
    if (ref = e.keyCode, indexOf.call([16, 17, 18, 19], ref) >= 0) {
      return true;
    }
    if (e.shiftKey && e.keyCode === 13 && !selection && !getSelection().isCollapsed) {
      butterfly.send(getSelection().toString());
      getSelection().removeAllRanges();
      return cancel(e);
    }
    if (selection) {
      selection.reset();
      if (!e.ctrlKey && e.shiftKey && (37 <= (ref1 = e.keyCode) && ref1 <= 40)) {
        return true;
      }
      if (e.shiftKey && e.ctrlKey) {
        if (e.keyCode === 38) {
          selection.up();
        } else if (e.keyCode === 40) {
          selection.down();
        }
      } else if (e.keyCode === 39) {
        selection.shrinkLeft();
      } else if (e.keyCode === 38) {
        selection.expandLeft();
      } else if (e.keyCode === 37) {
        selection.shrinkRight();
      } else if (e.keyCode === 40) {
        selection.expandRight();
      } else {
        return cancel(e);
      }
      if (selection != null) {
        selection.apply();
      }
      return cancel(e);
    }
    if (!selection && e.ctrlKey && e.shiftKey && e.keyCode === 38) {
      selection = new Selection();
      selection.selectLine(butterfly.y - 1);
      selection.apply();
      return cancel(e);
    }
    return true;
  });

  document.addEventListener('keyup', function(e) {
    var ref, ref1;
    if (ref = e.keyCode, indexOf.call([16, 17, 18, 19], ref) >= 0) {
      return true;
    }
    if (selection) {
      if (e.keyCode === 13) {
        butterfly.send(selection.text());
        selection.destroy();
        selection = null;
        return cancel(e);
      }
      if (ref1 = e.keyCode, indexOf.call([37, 38, 39, 40], ref1) < 0) {
        selection.destroy();
        selection = null;
        return true;
      }
    }
    return true;
  });

  document.addEventListener('dblclick', function(e) {
    var anchorNode, anchorOffset, newRange, range, sel;
    if (e.ctrlKey || e.altkey) {
      return;
    }
    sel = getSelection();
    if (sel.isCollapsed || sel.toString().match(/\s/)) {
      return;
    }
    range = document.createRange();
    range.setStart(sel.anchorNode, sel.anchorOffset);
    range.setEnd(sel.focusNode, sel.focusOffset);
    if (range.collapsed) {
      sel.removeAllRanges();
      newRange = document.createRange();
      newRange.setStart(sel.focusNode, sel.focusOffset);
      newRange.setEnd(sel.anchorNode, sel.anchorOffset);
      sel.addRange(newRange);
    }
    while (!(sel.toString().match(/\s/) || !sel.toString())) {
      sel.modify('extend', 'forward', 'character');
    }
    sel.modify('extend', 'backward', 'character');
    anchorNode = sel.anchorNode;
    anchorOffset = sel.anchorOffset;
    sel.collapseToEnd();
    sel.extend(anchorNode, anchorOffset);
    while (!(sel.toString().match(/\s/) || !sel.toString())) {
      sel.modify('extend', 'backward', 'character');
    }
    return sel.modify('extend', 'forward', 'character');
  });

  document.addEventListener('keydown', function(e) {
    var oReq;
    if (!(e.altKey && e.keyCode === 69)) {
      return true;
    }
    oReq = new XMLHttpRequest();
    oReq.addEventListener('load', function() {
      var j, len1, out, ref, response, session;
      response = JSON.parse(this.responseText);
      out = '<div>';
      out += '<h2>Session list</h2>';
      if (response.sessions.length === 0) {
        out += "No current session for user " + response.user;
      } else {
        out += '<ul>';
        ref = response.sessions;
        for (j = 0, len1 = ref.length; j < len1; j++) {
          session = ref[j];
          out += "<li><a href=\"/session/" + session + "\">" + session + "</a></li>";
        }
        out += '</ul>';
      }
      out += '</div>';
      return popup.open(out);
    });
    oReq.open("GET", "/sessions/list.json");
    oReq.send();
    return cancel(e);
  });

  _set_theme_href = function(href) {
    var img;
    document.getElementById('style').setAttribute('href', href);
    img = document.createElement('img');
    img.onerror = function() {
      return setTimeout((function() {
        return typeof butterfly !== "undefined" && butterfly !== null ? butterfly.resize() : void 0;
      }), 250);
    };
    return img.src = href;
  };

  _theme = typeof localStorage !== "undefined" && localStorage !== null ? localStorage.getItem('theme') : void 0;

  if (_theme) {
    _set_theme_href(_theme);
  }

  this.set_theme = function(theme) {
    _theme = theme;
    if (typeof localStorage !== "undefined" && localStorage !== null) {
      localStorage.setItem('theme', theme);
    }
    if (theme) {
      return _set_theme_href(theme);
    }
  };

  document.addEventListener('keydown', function(e) {
    var oReq, style;
    if (!(e.altKey && e.keyCode === 83)) {
      return true;
    }
    if (e.shiftKey) {
      style = document.getElementById('style').getAttribute('href');
      style = style.split('?')[0];
      _set_theme_href(style + '?' + (new Date().getTime()));
      return cancel(e);
    }
    oReq = new XMLHttpRequest();
    oReq.addEventListener('load', function() {
      var builtin_themes, inner, j, k, len1, len2, option, response, theme, theme_list, themes, url;
      response = JSON.parse(this.responseText);
      builtin_themes = response.builtin_themes;
      themes = response.themes;
      inner = "<form>\n  <h2>Pick a theme:</h2>\n  <select id=\"theme_list\">";
      option = function(url, theme) {
        inner += '<option ';
        if (_theme === url) {
          inner += 'selected ';
        }
        inner += "value=\"" + url + "\">";
        inner += theme;
        return inner += '</option>';
      };
      option("/static/main.css", 'default');
      if (themes.length) {
        inner += '<optgroup label="Local themes">';
        for (j = 0, len1 = themes.length; j < len1; j++) {
          theme = themes[j];
          url = "/theme/" + theme + "/style.css";
          option(url, theme);
        }
        inner += '</optgroup>';
      }
      inner += '<optgroup label="Built-in themes">';
      for (k = 0, len2 = builtin_themes.length; k < len2; k++) {
        theme = builtin_themes[k];
        url = "/theme/" + theme + "/style.css";
        option(url, theme.slice('built-in-'.length));
      }
      inner += '</optgroup>';
      inner += "  </select>\n  <label>You can create yours in " + response.dir + ".</label>\n</form>";
      popup.open(inner);
      theme_list = document.getElementById('theme_list');
      return theme_list.addEventListener('change', function() {
        return set_theme(theme_list.value);
      });
    });
    oReq.open("GET", "/themes/list.json");
    oReq.send();
    return cancel(e);
  });

  if (/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)) {
    ctrl = false;
    alt = false;
    first = true;
    virtualInput = document.createElement('input');
    virtualInput.type = 'password';
    virtualInput.style.position = 'fixed';
    virtualInput.style.top = 0;
    virtualInput.style.left = 0;
    virtualInput.style.border = 'none';
    virtualInput.style.outline = 'none';
    virtualInput.style.opacity = 0;
    virtualInput.value = '0';
    document.body.appendChild(virtualInput);
    virtualInput.addEventListener('blur', function() {
      return setTimeout(((function(_this) {
        return function() {
          return _this.focus();
        };
      })(this)), 10);
    });
    addEventListener('click', function() {
      return virtualInput.focus();
    });
    addEventListener('touchstart', function(e) {
      if (e.touches.length === 2) {
        return ctrl = true;
      } else if (e.touches.length === 3) {
        ctrl = false;
        return alt = true;
      } else if (e.touches.length === 4) {
        ctrl = true;
        return alt = true;
      }
    });
    virtualInput.addEventListener('keydown', function(e) {
      butterfly.keyDown(e);
      return true;
    });
    virtualInput.addEventListener('input', function(e) {
      var len;
      len = this.value.length;
      if (len === 0) {
        e.keyCode = 8;
        butterfly.keyDown(e);
        this.value = '0';
        return true;
      }
      e.keyCode = this.value.charAt(1).charCodeAt(0);
      if ((ctrl || alt) && !first) {
        e.keyCode = this.value.charAt(1).charCodeAt(0);
        e.ctrlKey = ctrl;
        e.altKey = alt;
        if (e.keyCode >= 97 && e.keyCode <= 122) {
          e.keyCode -= 32;
        }
        butterfly.keyDown(e);
        this.value = '0';
        ctrl = alt = false;
        return true;
      }
      butterfly.keyPress(e);
      first = false;
      this.value = '0';
      return true;
    });
  }

}).call(this);

//# sourceMappingURL=ext.js.map
