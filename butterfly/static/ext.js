(function() {
  var Selection, alt, cancel, copy, ctrl, first, nextLeaf, previousLeaf, selection, setAlarm, virtualInput,
    indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

  setAlarm = function(notification) {
    var alarm;
    alarm = function(data) {
      var note;
      butterfly.body.classList.remove('alarm');
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
    if (!(e.altKey && e.keyCode === 65)) {
      return true;
    }
    if (Notification && Notification.permission === 'default') {
      Notification.requestPermission(function() {
        return setAlarm(Notification.permission === 'granted');
      });
    } else {
      setAlarm(Notification.permission === 'granted');
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
          node = previousLeaf(node);
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
          node = nextLeaf(node);
          text = node.textContent;
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
