(function() {
  var Selection, alt, cancel, copy, ctrl, first, next_leaf, previous_leaf, selection, set_alarm, virtual_input,
    __indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  set_alarm = function(notification) {
    var alarm;
    alarm = function(data) {
      var note;
      butterfly.element.classList.remove('alarm');
      note = "New activity on butterfly terminal [" + butterfly.title + "]";
      if (notification) {
        new Notification(note, {
          body: data.data,
          icon: '/static/images/favicon.png'
        });
      } else {
        alert(note + '\n' + data.data);
      }
      return butterfly.ws.removeEventListener('message', alarm);
    };
    butterfly.ws.addEventListener('message', alarm);
    return butterfly.element.classList.add('alarm');
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
    if (!(e.altKey && e.keyCode === 65)) {
      return true;
    }
    if (Notification && Notification.permission === 'default') {
      Notification.requestPermission(function() {
        return set_alarm(Notification.permission === 'granted');
      });
    } else {
      set_alarm(Notification.permission === 'granted');
    }
    return cancel(e);
  });

  document.addEventListener('copy', copy = function(e) {
    var data, end, line, sel, _i, _len, _ref;
    butterfly.bell("copied");
    e.clipboardData.clearData();
    sel = getSelection().toString().replace(/\u00A0/g, ' ').replace(/\u2007/g, ' ');
    data = '';
    _ref = sel.split('\n');
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      line = _ref[_i];
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

  document.addEventListener('paste', function(e) {
    var data;
    butterfly.bell("pasted");
    data = e.clipboardData.getData('text/plain');
    data = data.replace(/\r\n/g, '\n').replace(/\n/g, '\r');
    butterfly.send(data);
    return e.preventDefault();
  });

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

  previous_leaf = function(node) {
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

  next_leaf = function(node) {
    var next;
    next = node.nextSibling;
    if (!next) {
      next = node.parentNode.nextSibling;
    }
    if (!next) {
      next = node.parentNode.parentNode.nextSibling;
    }
    while (next.firstChild) {
      next = next.firstChild;
    }
    return next;
  };

  Selection = (function() {
    function Selection() {
      butterfly.element.classList.add('selection');
      this.selection = getSelection();
    }

    Selection.prototype.reset = function() {
      var fake_range, _ref, _results;
      this.selection = getSelection();
      fake_range = document.createRange();
      fake_range.setStart(this.selection.anchorNode, this.selection.anchorOffset);
      fake_range.setEnd(this.selection.focusNode, this.selection.focusOffset);
      this.start = {
        node: this.selection.anchorNode,
        offset: this.selection.anchorOffset
      };
      this.end = {
        node: this.selection.focusNode,
        offset: this.selection.focusOffset
      };
      if (fake_range.collapsed) {
        _ref = [this.end, this.start], this.start = _ref[0], this.end = _ref[1];
      }
      this.start_line = this.start.node;
      while (!this.start_line.classList || __indexOf.call(this.start_line.classList, 'line') < 0) {
        this.start_line = this.start_line.parentNode;
      }
      this.end_line = this.end.node;
      _results = [];
      while (!this.end_line.classList || __indexOf.call(this.end_line.classList, 'line') < 0) {
        _results.push(this.end_line = this.end_line.parentNode);
      }
      return _results;
    };

    Selection.prototype.clear = function() {
      return this.selection.removeAllRanges();
    };

    Selection.prototype.destroy = function() {
      butterfly.element.classList.remove('selection');
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
      index = butterfly.children.indexOf(this.start_line) + n;
      if (!((0 <= index && index < butterfly.children.length))) {
        return;
      }
      while (!butterfly.children[index].textContent.match(/\S/)) {
        index += n;
        if (!((0 <= index && index < butterfly.children.length))) {
          return;
        }
      }
      return this.select_line(index);
    };

    Selection.prototype.apply = function() {
      var range;
      this.clear();
      range = document.createRange();
      range.setStart(this.start.node, this.start.offset);
      range.setEnd(this.end.node, this.end.offset);
      return this.selection.addRange(range);
    };

    Selection.prototype.select_line = function(index) {
      var line, line_end, line_start;
      line = butterfly.children[index];
      line_start = {
        node: line.firstChild,
        offset: 0
      };
      line_end = {
        node: line.lastChild,
        offset: line.lastChild.textContent.length
      };
      this.start = this.walk(line_start, /\S/);
      return this.end = this.walk(line_end, /\S/, true);
    };

    Selection.prototype.collapsed = function(start, end) {
      var fake_range;
      fake_range = document.createRange();
      fake_range.setStart(start.node, start.offset);
      fake_range.setEnd(end.node, end.offset);
      return fake_range.collapsed;
    };

    Selection.prototype.shrink_right = function() {
      var end, node;
      node = this.walk(this.end, /\s/, true);
      end = this.walk(node, /\S/, true);
      if (!this.collapsed(this.start, end)) {
        return this.end = end;
      }
    };

    Selection.prototype.shrink_left = function() {
      var node, start;
      node = this.walk(this.start, /\s/);
      start = this.walk(node, /\S/);
      if (!this.collapsed(start, this.end)) {
        return this.start = start;
      }
    };

    Selection.prototype.expand_right = function() {
      var node;
      node = this.walk(this.end, /\S/);
      return this.end = this.walk(node, /\s/);
    };

    Selection.prototype.expand_left = function() {
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
      text = node.textContent;
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
          node = previous_leaf(node);
          text = node.textContent;
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
          node = next_leaf(node);
          text = node.textContent;
          i = 0;
        }
      }
      return needle;
    };

    return Selection;

  })();

  document.addEventListener('keydown', function(e) {
    var _ref, _ref1;
    if (_ref = e.keyCode, __indexOf.call([16, 17, 18, 19], _ref) >= 0) {
      return true;
    }
    if (e.shiftKey && e.keyCode === 13 && !selection && !getSelection().isCollapsed) {
      butterfly.send(getSelection().toString());
      getSelection().removeAllRanges();
      return cancel(e);
    }
    if (selection) {
      selection.reset();
      if (!e.ctrlKey && e.shiftKey && (37 <= (_ref1 = e.keyCode) && _ref1 <= 40)) {
        return true;
      }
      if (e.shiftKey && e.ctrlKey) {
        if (e.keyCode === 38) {
          selection.up();
        } else if (e.keyCode === 40) {
          selection.down();
        }
      } else if (e.keyCode === 39) {
        selection.shrink_left();
      } else if (e.keyCode === 38) {
        selection.expand_left();
      } else if (e.keyCode === 37) {
        selection.shrink_right();
      } else if (e.keyCode === 40) {
        selection.expand_right();
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
      selection.select_line(butterfly.y - 1);
      selection.apply();
      return cancel(e);
    }
    return true;
  });

  document.addEventListener('keyup', function(e) {
    var _ref, _ref1;
    if (_ref = e.keyCode, __indexOf.call([16, 17, 18, 19], _ref) >= 0) {
      return true;
    }
    if (selection) {
      if (e.keyCode === 13) {
        butterfly.send(selection.text());
        selection.destroy();
        selection = null;
        return cancel(e);
      }
      if (_ref1 = e.keyCode, __indexOf.call([37, 38, 39, 40], _ref1) < 0) {
        selection.destroy();
        selection = null;
        return true;
      }
    }
    return true;
  });

  document.addEventListener('dblclick', function(e) {
    var anchorNode, anchorOffset, new_range, range, sel;
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
      new_range = document.createRange();
      new_range.setStart(sel.focusNode, sel.focusOffset);
      new_range.setEnd(sel.anchorNode, sel.anchorOffset);
      sel.addRange(new_range);
    }
    range.detach();
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

  if (/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent)) {
    ctrl = false;
    alt = false;
    first = true;
    virtual_input = document.createElement('input');
    virtual_input.type = 'password';
    virtual_input.style.position = 'fixed';
    virtual_input.style.top = 0;
    virtual_input.style.left = 0;
    virtual_input.style.border = 'none';
    virtual_input.style.outline = 'none';
    virtual_input.style.opacity = 0;
    virtual_input.value = '0';
    document.body.appendChild(virtual_input);
    virtual_input.addEventListener('blur', function() {
      return setTimeout(((function(_this) {
        return function() {
          return _this.focus();
        };
      })(this)), 10);
    });
    addEventListener('click', function() {
      return virtual_input.focus();
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
    virtual_input.addEventListener('keydown', function(e) {
      butterfly.keyDown(e);
      return true;
    });
    virtual_input.addEventListener('input', function(e) {
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
