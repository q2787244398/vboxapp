(function (root, factory) {
  'use strict';

  var api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  }
  if (root && root.document) {
    api.install(root);
  }
})(typeof window !== 'undefined' ? window : null, function () {
  'use strict';

  var controllerKey = '__tvsConfigCenterDpadController';
  var focusAttribute = 'data-tvs-dpad-focused';
  var clickableAttribute = 'data-tvs-dpad-clickable';
  var closeControlSelector = [
    '.ant-modal-close',
    '.ant-drawer-close',
    '.ant-modal-close-x',
    '.btn-close',
    '.close-btn',
    '.close',
    '[class*="close"]',
    '[class*="Close"]',
    '[data-close]',
    '[data-dismiss]',
  ].join(',');
  var modalSelector = [
    '.ant-modal-wrap .ant-modal',
    '.ant-modal[role="dialog"]',
    '[role="dialog"][aria-modal="true"]',
    '.ant-drawer-content[role="dialog"]',
    '.ant-drawer-content',
  ].join(',');
  var focusableSelector = [
    'a[href]',
    'button:not([disabled])',
    'input:not([disabled]):not([type="hidden"])',
    'textarea:not([disabled])',
    'select:not([disabled])',
    '[contenteditable="true"]',
    '[tabindex]:not([tabindex="-1"])',
    '[role="button"]',
    '[role="tab"]',
    '[role="checkbox"]',
    '[role="radio"]',
  ].join(',');
  var clickableCardSelector = [
    '.ant-card',
    '.ant-list-item[class*="click"]',
    '.ant-list-item[class*="hover"]',
    '[class*="card"][class*="click"]',
    '[class*="card"][class*="hover"]',
    '[data-clickable="true"]',
    '[data-action]',
    '[onclick]',
    '[style*="cursor: pointer"]',
    '[style*="cursor:pointer"]',
  ].join(',');

  function asArray(items) {
    return Array.prototype.slice.call(items || []);
  }

  function isVisible(win, element) {
    if (
      !element ||
      element.hidden ||
      element.disabled ||
      element.getAttribute('aria-disabled') === 'true' ||
      typeof element.getBoundingClientRect !== 'function'
    ) {
      return false;
    }

    if (
      typeof element.closest === 'function' &&
      element.closest('[aria-hidden="true"], [inert]')
    ) {
      return false;
    }

    var style = win.getComputedStyle(element);
    if (
      !style ||
      style.display === 'none' ||
      style.visibility === 'hidden' ||
      style.visibility === 'collapse' ||
      style.pointerEvents === 'none'
    ) {
      return false;
    }

    var ancestor = element.parentElement || element.parent || null;
    while (ancestor) {
      var ancestorStyle = win.getComputedStyle(ancestor);
      if (
        !ancestorStyle ||
        ancestorStyle.display === 'none' ||
        ancestorStyle.visibility === 'hidden' ||
        ancestorStyle.visibility === 'collapse' ||
        ancestorStyle.pointerEvents === 'none'
      ) {
        return false;
      }
      ancestor = ancestor.parentElement || ancestor.parent || null;
    }

    var rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function activeModal(win) {
    var dialogs = asArray(win.document.querySelectorAll(modalSelector)).filter(
      function (dialog) {
        return isVisible(win, dialog);
      },
    );
    if (dialogs.length > 0) return dialogs[dialogs.length - 1];

    var viewportWidth =
      win.innerWidth || win.document.documentElement.clientWidth || 0;
    var viewportHeight =
      win.innerHeight || win.document.documentElement.clientHeight || 0;
    var viewportArea = viewportWidth * viewportHeight;
    var best = null;
    var bestZIndex = Number.NEGATIVE_INFINITY;
    asArray(win.document.querySelectorAll('*')).forEach(function (element) {
      if (!isVisible(win, element)) return;
      var style = win.getComputedStyle(element);
      var zIndex = Number.parseFloat(style.zIndex);
      var rect = element.getBoundingClientRect();
      var area = rect.width * rect.height;
      if (
        (style.position !== 'fixed' && style.position !== 'absolute') ||
        style.pointerEvents === 'none' ||
        !Number.isFinite(zIndex) ||
        zIndex <= 0 ||
        viewportArea <= 0 ||
        area < viewportArea * 0.35 ||
        !hasVisibleNativeControl(win, element) ||
        !hasVisibleInteractiveOutside(win, element)
      ) {
        return;
      }
      if (zIndex >= bestZIndex) {
        best = element;
        bestZIndex = zIndex;
      }
    });
    return best;
  }

  function hasVisibleNativeControl(win, element) {
    if (typeof element.querySelectorAll !== 'function') return false;
    return asArray(element.querySelectorAll(focusableSelector)).some(function (
      candidate,
    ) {
      return isVisible(win, candidate);
    });
  }

  function hasVisibleInteractiveOutside(win, scope) {
    return asArray(win.document.querySelectorAll('*')).some(function (element) {
      return (
        !containsElement(scope, element) &&
        isVisible(win, element) &&
        (isNativeFocusable(element) || isRuntimeClickable(win, element))
      );
    });
  }

  function containsElement(scope, element) {
    if (!scope || !element) return false;
    if (typeof scope.contains === 'function') return scope.contains(element);
    var current = element;
    while (current) {
      if (current === scope) return true;
      current = current.parentElement || current.parent || null;
    }
    return false;
  }

  function focusableElements(win, scope) {
    if (!scope || typeof scope.querySelectorAll !== 'function') {
      return [];
    }
    var elements = asArray(scope.querySelectorAll('*'));

    elements.forEach(function (element) {
      // Some TV web UIs render the modal's X as a clickable div instead of a
      // native button. Promote only close controls inside an active modal so
      // the control is reachable without making page-level “close” labels
      // part of the normal document focus graph.
      if (
        scope !== win.document.body &&
        isVisible(win, element) &&
        isCloseControlElement(element)
      ) {
        promoteModalCloseControl(element);
        return;
      }
      if (
        isVisible(win, element) &&
        !isNativeFocusable(element) &&
        element.getAttribute(clickableAttribute) !== 'true'
      ) {
        promoteClickableElement(win, element);
      }
    });

    return elements.filter(function (element) {
      if (!isVisible(win, element)) return false;
      if (isEditable(element) && isInsideClickableCard(element)) return false;
      return (
        isNativeFocusable(element) ||
        element.getAttribute(clickableAttribute) === 'true'
      );
    });
  }

  function isCloseControlElement(element) {
    return (
      typeof element.matches === 'function' &&
      element.matches(closeControlSelector)
    );
  }

  function promoteModalCloseControl(element) {
    if (!element.hasAttribute('tabindex')) element.setAttribute('tabindex', '0');
    if (!element.hasAttribute('role')) element.setAttribute('role', 'button');
    element.setAttribute(clickableAttribute, 'true');
  }

  function isInsideClickableCard(element) {
    var ancestor = element.parentElement || element.parent || null;
    while (ancestor) {
      if (ancestor.getAttribute(clickableAttribute) === 'true') return true;
      ancestor = ancestor.parentElement || ancestor.parent || null;
    }
    return false;
  }

  function isNativeFocusable(element) {
    var tagName = String(element.tagName || '').toUpperCase();
    if (
      tagName === 'BUTTON' ||
      tagName === 'INPUT' ||
      tagName === 'TEXTAREA' ||
      tagName === 'SELECT'
    ) {
      return true;
    }
    if (tagName === 'A' && element.hasAttribute('href')) return true;
    return (
      element.hasAttribute('tabindex') ||
      element.getAttribute('contenteditable') === 'true' ||
      element.getAttribute('role') === 'button' ||
      element.getAttribute('role') === 'tab' ||
      element.getAttribute('role') === 'checkbox' ||
      element.getAttribute('role') === 'radio'
    );
  }

  function promoteClickableElement(win, element) {
    if (!isRuntimeClickable(win, element)) {
      return false;
    }

    // React may attach handlers to nested cards. Only the leaf handler is an item.
    if (hasNestedClickHandler(win, element)) {
      return false;
    }

    if (!element.hasAttribute('tabindex')) {
      element.setAttribute('tabindex', '0');
    }
    if (!element.hasAttribute('role')) {
      element.setAttribute('role', 'button');
    }
    element.setAttribute(clickableAttribute, 'true');
    return true;
  }

  function isRuntimeClickable(win, element) {
    if (typeof element.onclick === 'function') return true;
    if (
      typeof element.matches === 'function' &&
      element.matches(clickableCardSelector)
    ) {
      return true;
    }

    try {
      var keys = Object.keys(element);
      for (var index = 0; index < keys.length; index += 1) {
        var key = keys[index];
        if (
          key.indexOf('__reactProps$') !== 0 &&
          key.indexOf('__reactEventHandlers$') !== 0
        ) {
          continue;
        }
        var props = element[key];
        if (props && typeof props.onClick === 'function') return true;
      }
    } catch (_) {}
    return false;
  }

  function hasNestedClickHandler(win, element) {
    if (typeof element.querySelectorAll !== 'function') return false;
    return asArray(element.querySelectorAll('*')).some(function (descendant) {
      return !isNativeFocusable(descendant) && isRuntimeClickable(win, descendant);
    });
  }

  function isEditable(element) {
    var tagName = String(element.tagName || '').toUpperCase();
    return (
      tagName === 'INPUT' ||
      tagName === 'TEXTAREA' ||
      tagName === 'SELECT' ||
      element.getAttribute('contenteditable') === 'true'
    );
  }

  function isPrimaryAction(element) {
    return (
      (element.classList && element.classList.contains('ant-btn-primary')) ||
      element.getAttribute('type') === 'submit' ||
      element.getAttribute('data-primary') === 'true'
    );
  }

  function preferredElement(elements) {
    var preferred = elements.find(function (element) {
      return element.hasAttribute('autofocus');
    });
    if (preferred) return preferred;

    preferred = elements.find(isEditable);
    if (preferred) return preferred;

    preferred = elements.find(isPrimaryAction);
    return preferred || elements[0] || null;
  }

  function directionFor(event) {
    var byKey = {
      ArrowUp: 'up',
      Up: 'up',
      ArrowDown: 'down',
      Down: 'down',
      ArrowLeft: 'left',
      Left: 'left',
      ArrowRight: 'right',
      Right: 'right',
    };
    if (byKey[event.key]) return byKey[event.key];

    var byCode = {
      19: 'up',
      20: 'down',
      21: 'left',
      22: 'right',
      37: 'left',
      38: 'up',
      39: 'right',
      40: 'down',
    };
    return byCode[event.keyCode] || null;
  }

  function isActivationKey(event) {
    return (
      event.key === 'Enter' ||
      event.key === 'Select' ||
      event.key === 'Accept' ||
      event.key === ' ' ||
      event.key === 'Spacebar' ||
      event.keyCode === 13 ||
      event.keyCode === 23 ||
      event.keyCode === 32 ||
      event.keyCode === 66
    );
  }

  function center(rect, axis) {
    if (axis === 'x') return (rect.left + rect.right) / 2;
    return (rect.top + rect.bottom) / 2;
  }

  function intervalGap(startA, endA, startB, endB) {
    if (endA < startB) return startB - endA;
    if (endB < startA) return startA - endB;
    return 0;
  }

  function candidateScore(currentRect, candidateRect, direction) {
    var primaryGap;
    var crossGap;
    var primaryCenterDistance;

    if (direction === 'up' || direction === 'down') {
      var currentY = center(currentRect, 'y');
      var candidateY = center(candidateRect, 'y');
      if (
        (direction === 'up' && candidateY >= currentY) ||
        (direction === 'down' && candidateY <= currentY)
      ) {
        return null;
      }
      primaryGap =
        direction === 'up'
          ? Math.max(0, currentRect.top - candidateRect.bottom)
          : Math.max(0, candidateRect.top - currentRect.bottom);
      crossGap = intervalGap(
        currentRect.left,
        currentRect.right,
        candidateRect.left,
        candidateRect.right,
      );
      primaryCenterDistance = Math.abs(candidateY - currentY);
    } else {
      var currentX = center(currentRect, 'x');
      var candidateX = center(candidateRect, 'x');
      if (
        (direction === 'left' && candidateX >= currentX) ||
        (direction === 'right' && candidateX <= currentX)
      ) {
        return null;
      }
      primaryGap =
        direction === 'left'
          ? Math.max(0, currentRect.left - candidateRect.right)
          : Math.max(0, candidateRect.left - currentRect.right);
      crossGap = intervalGap(
        currentRect.top,
        currentRect.bottom,
        candidateRect.top,
        candidateRect.bottom,
      );
      primaryCenterDistance = Math.abs(candidateX - currentX);
    }

    // Prefer controls in the same visual row/column before nearer diagonal ones.
    return crossGap * 1000000 + primaryGap * 1000 + primaryCenterDistance;
  }

  function pickNext(elements, current, direction) {
    if (!current || typeof current.getBoundingClientRect !== 'function') {
      return null;
    }

    var currentRect = current.getBoundingClientRect();
    var best = null;
    var bestScore = Number.POSITIVE_INFINITY;
    elements.forEach(function (candidate) {
      if (candidate === current) return;
      var score = candidateScore(
        currentRect,
        candidate.getBoundingClientRect(),
        direction,
      );
      if (score !== null && score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    });
    return best;
  }

  function install(win) {
    if (win[controllerKey]) return win[controllerKey];

    var document = win.document;
    var markedElement = null;
    var logicalFocusedElement = null;
    var focusSnapshot = null;
    var pageFocusSnapshot = null;
    var modalWasOpen = false;
    var scheduled = false;
    var observer = null;

    function isCloseLabel(value) {
      return /^(关闭|取消|返回|×|✕)$/.test(value);
    }

    function visibleText(node) {
      return String(
        node.getAttribute('aria-label') ||
          node.getAttribute('title') ||
          node.textContent ||
          '',
      )
        .replace(/\s+/g, ' ')
        .trim();
    }

    function findCloseControl(scope) {
      if (!scope || typeof scope.querySelectorAll !== 'function') return null;
      var closeControl = asArray(
        scope.querySelectorAll(
          closeControlSelector,
        ),
      ).find(function (candidate) {
        return isVisible(win, candidate);
      });
      if (closeControl) return closeControl;

      return asArray(scope.querySelectorAll('button, [role="button"]')).find(
        function (candidate) {
          if (!isVisible(win, candidate)) return false;
          var label = visibleText(candidate);
          return isCloseLabel(label);
        },
      );
    }

    function closeModal(modal) {
      if (!modal || typeof modal.querySelector !== 'function') return false;
      var hadModal = !!activeModal(win);
      var closeControl = findCloseControl(modal);
      if (!closeControl || typeof closeControl.click !== 'function') {
        if (
          typeof win.KeyboardEvent !== 'function' ||
          !win.document ||
          typeof win.document.dispatchEvent !== 'function'
        ) {
          return false;
        }
        try {
          var escDown = new win.KeyboardEvent('keydown', {
            key: 'Escape',
            keyCode: 27,
            which: 27,
            bubbles: true,
          });
          var escUp = new win.KeyboardEvent('keyup', {
            key: 'Escape',
            keyCode: 27,
            which: 27,
            bubbles: true,
          });
          win.document.dispatchEvent(escDown);
          win.document.dispatchEvent(escUp);
          return hadModal;
        } catch (_) {
          return false;
        }
      }
      closeControl.click();
      return true;
    }

    function focusedModalScope() {
      var element = logicalFocusedElement || document.activeElement;
      while (element && element !== document.body) {
        if (findCloseControl(element)) return element;
        element = element.parentElement || element.parent || null;
      }
      return null;
    }

    function markFocused(element) {
      if (element) focusSnapshot = snapshotFor(element);
      if (
        markedElement === element &&
        (!element || element.getAttribute(focusAttribute) === 'true')
      ) {
        return;
      }
      if (markedElement && markedElement !== element) {
        markedElement.removeAttribute(focusAttribute);
      }
      markedElement = element || null;
      logicalFocusedElement = markedElement;
      if (markedElement) {
        markedElement.setAttribute(focusAttribute, 'true');
      }
    }

    function snapshotFor(element) {
      var rect = element.getBoundingClientRect();
      var label =
        element.getAttribute('aria-label') ||
        element.getAttribute('title') ||
        String(element.textContent || '').replace(/\s+/g, ' ').trim();
      return {
        identity: label.slice(0, 32),
        role: element.getAttribute('role') || '',
        tagName: String(element.tagName || '').toUpperCase(),
        x: center(rect, 'x'),
        y: center(rect, 'y'),
      };
    }

    function recoverFromSnapshot(elements, snapshot) {
      snapshot = snapshot || focusSnapshot;
      if (!snapshot) return null;
      var exact = elements.find(function (element) {
        var candidate = snapshotFor(element);
        return (
          candidate.identity &&
          candidate.identity === snapshot.identity &&
          candidate.role === snapshot.role
        );
      });
      if (exact) return exact;

      var best = null;
      var bestDistance = Number.POSITIVE_INFINITY;
      elements.forEach(function (element) {
        var candidate = snapshotFor(element);
        if (
          candidate.role !== snapshot.role ||
          candidate.tagName !== snapshot.tagName
        ) {
          return;
        }
        var dx = candidate.x - snapshot.x;
        var dy = candidate.y - snapshot.y;
        var distance = dx * dx + dy * dy;
        if (distance < bestDistance) {
          best = element;
          bestDistance = distance;
        }
      });
      return best;
    }

    function focus(element, enterEditing) {
      if (!element) return false;
      markFocused(element);
      var activeElement = document.activeElement;
      if (
        activeElement &&
        activeElement !== element &&
        activeElement !== document.body &&
        typeof activeElement.blur === 'function'
      ) {
        activeElement.blur();
      }

      if (isEditable(element) && !enterEditing) {
        scrollIntoView(element);
        return true;
      }

      try {
        element.focus({preventScroll: true});
      } catch (_) {
        element.focus();
      }
      scrollIntoView(element);
      return true;
    }

    function scrollIntoView(element) {
      if (typeof element.scrollIntoView === 'function') {
        try {
          element.scrollIntoView({block: 'nearest', inline: 'nearest'});
        } catch (_) {
          element.scrollIntoView(false);
        }
      }
    }

    function clearFocusMarkers(scope) {
      asArray(document.querySelectorAll('*')).forEach(function (element) {
        if (
          element.getAttribute(focusAttribute) === 'true' &&
          (!scope || !containsElement(scope, element))
        ) {
          element.removeAttribute(focusAttribute);
        }
      });
    }

    function refreshFocus() {
      var modal = activeModal(win);
      var scope = modal || document.body || document.documentElement;
      var elements = focusableElements(win, scope);
      if (modal) clearFocusMarkers(modal);
      if (modal && !modalWasOpen) {
        modalWasOpen = true;
        pageFocusSnapshot = focusSnapshot;
        return focus(preferredElement(elements));
      }
      if (!modal && modalWasOpen) {
        clearFocusMarkers(null);
        modalWasOpen = false;
        var restoredPageElement = recoverFromSnapshot(
          elements,
          pageFocusSnapshot,
        );
        pageFocusSnapshot = null;
        if (restoredPageElement) return focus(restoredPageElement);
      }
      if (elements.indexOf(logicalFocusedElement) >= 0) {
        markFocused(logicalFocusedElement);
        return false;
      }
      if (elements.indexOf(document.activeElement) >= 0) {
        markFocused(document.activeElement);
        return false;
      }
      var recovered = recoverFromSnapshot(elements);
      if (recovered) return focus(recovered);
      if (modal) return focus(preferredElement(elements));
      return false;
    }

    function scheduleRefresh() {
      if (scheduled) return;
      scheduled = true;
      var schedule = win.requestAnimationFrame || function (callback) {
        return setTimeout(callback, 0);
      };
      schedule(function () {
        scheduled = false;
        refreshFocus();
      });
    }

    function handleKeydown(event) {
      if (
        event.defaultPrevented ||
        event.altKey ||
        event.ctrlKey ||
        event.metaKey ||
        event.shiftKey ||
        event.isComposing
      ) {
        return;
      }

      var modal = activeModal(win);
      var scope = modal || document.body || document.documentElement;
      var elements = focusableElements(win, scope);
      var current =
        elements.indexOf(logicalFocusedElement) >= 0
          ? logicalFocusedElement
          : elements.indexOf(document.activeElement) >= 0
          ? document.activeElement
          : recoverFromSnapshot(elements);
      if (
        isActivationKey(event) &&
        current &&
        current.getAttribute(clickableAttribute) === 'true'
      ) {
        consume(event);
        current.click();
        return;
      }
      if (isActivationKey(event) && current && isEditable(current)) {
        consume(event);
        focus(current, true);
        return;
      }
      if (isActivationKey(event) && current && isNativeFocusable(current)) {
        consume(event);
        current.click && current.click();
        return;
      }

      var direction = directionFor(event);
      if (!direction) return;

      if (elements.length === 0) {
        if (modal) consume(event);
        return;
      }

      var target =
        elements.indexOf(current) < 0
          ? preferredElement(elements)
          : pickNext(elements, current, direction);
      if (!target) {
        consume(event);
        return;
      }

      consume(event);
      focus(target);
    }

    function consume(event) {
      event.preventDefault();
      if (typeof event.stopImmediatePropagation === 'function') {
        event.stopImmediatePropagation();
      } else {
        event.stopPropagation();
      }
    }

    function handleFocusIn(event) {
      if (
        event.target === document.body ||
        event.target === document.documentElement
      ) {
        return;
      }
      var modal = activeModal(win);
      var scope = modal || document.body || document.documentElement;
      var elements = focusableElements(win, scope);
      if (modal && !containsElement(modal, event.target)) {
        focus(
          elements.indexOf(logicalFocusedElement) >= 0
            ? logicalFocusedElement
            : preferredElement(elements),
        );
        return;
      }
      if (!isVisible(win, event.target)) return;
      if (elements.indexOf(event.target) >= 0) {
        markFocused(event.target);
        return;
      }
      var restored =
        elements.indexOf(logicalFocusedElement) >= 0
          ? logicalFocusedElement
          : recoverFromSnapshot(elements);
      if (restored) {
        focus(restored);
      }
    }

    document.addEventListener('keydown', handleKeydown, true);
    document.addEventListener('focusin', handleFocusIn, true);

    if (typeof win.MutationObserver === 'function') {
      observer = new win.MutationObserver(scheduleRefresh);
      observer.observe(document.documentElement || document.body, {
        attributeFilter: [
          'aria-disabled',
          'aria-hidden',
          'class',
          'disabled',
          'hidden',
          'open',
          'style',
          'tabindex',
        ],
        attributes: true,
        childList: true,
        subtree: true,
      });
    }

    var controller = {
      refreshFocus: refreshFocus,
      closeActiveModal: function () {
        return closeModal(activeModal(win) || focusedModalScope());
      },
      dispose: function () {
        document.removeEventListener('keydown', handleKeydown, true);
        document.removeEventListener('focusin', handleFocusIn, true);
        if (observer) observer.disconnect();
        markFocused(null);
        if (win[controllerKey] === controller) {
          delete win[controllerKey];
        }
      },
    };
    win[controllerKey] = controller;
    scheduleRefresh();
    return controller;
  }

  return {
    install: install,
    pickNext: pickNext,
  };
});
